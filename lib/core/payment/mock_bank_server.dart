import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/aes_gcm_service.dart';
import '../crypto/hmac_service.dart';
import '../crypto/key_exchange_service.dart';
import '../crypto/signature_service.dart';
import '../utils/bytes.dart';
import '../utils/clock.dart';
import 'bank_api.dart';
import 'models.dart';

/// IN-APP SIMULATION of the bank's backend + payment gateway.
///
/// In production every line of this class runs on the server. It lives here
/// only so the training app works fully offline. The most important lesson:
/// [_merchantKeySecret] must NEVER ship inside a mobile app — anyone can
/// decompile an APK/IPA and extract it.
class MockBankServer implements BankApi, MerchantApi {
  MockBankServer({Duration? clockSkew, Clock? clock})
      : _maxSkew = clockSkew ?? const Duration(minutes: 5),
        _clock = clock ?? DateTime.now;

  final Duration _maxSkew;
  final Clock _clock;

  final _kex = KeyExchangeService();
  final _aes = AesGcmService();
  final _sig = SignatureService();
  final _hmac = const HmacService();

  final Map<String, SessionKeys> _sessions = {};
  final Map<String, Uint8List> _devices = {}; // deviceId -> Ed25519 pubkey
  final Map<String, PaymentOrder> _orders = {};
  final Set<String> _paidOrders = {};
  final Set<String> _seenNonces = {};

  // Razorpay-style merchant secret: server-side only!
  final Uint8List _merchantKeySecret = Bytes.random(32);

  // ---------------------------------------------------------------- onboarding

  @override
  Future<HandshakeResponse> handshake(List<int> clientPublicKey) async {
    final serverKp = await _kex.newEphemeralKeyPair();
    final salt = Bytes.random(32);
    final keys = await _kex.deriveSessionKeys(myKeyPair: serverKp, theirPublicKey: clientPublicKey, salt: salt);
    final keyId = 'kid_${Bytes.toHex(Bytes.random(6))}';
    _sessions[keyId] = keys;
    return HandshakeResponse(serverPublicKey: await _kex.publicKeyOf(serverKp), salt: salt, keyId: keyId);
  }

  @override
  Future<void> registerDevice(String deviceId, List<int> publicKey) async =>
      _devices[deviceId] = Uint8List.fromList(publicKey);

  // -------------------------------------------------------------------- orders

  @override
  PaymentOrder createOrder({required int amountPaise, required String payee}) {
    final order = PaymentOrder(
      id: 'order_${Bytes.toHex(Bytes.random(7))}',
      amountPaise: amountPaise,
      currency: 'INR',
      payee: payee,
      receipt: 'rcpt_${_clock().millisecondsSinceEpoch}',
    );
    _orders[order.id] = order;
    return order;
  }

  // ------------------------------------------------------------------ payments

  /// Runs every defence in order and reports each one, so trainees can see
  /// exactly which layer stopped which attack.
  @override
  Future<PaymentResult> processPayment(ApiRequest req) async {
    final checks = <SecurityCheck>[];
    const names = [
      'Session key lookup',
      'Timestamp freshness',
      'Nonce (anti-replay)',
      'Body hash',
      'HMAC-SHA256 signature',
      'AES-256-GCM decrypt + tag',
      'Ed25519 device signature',
      'Order & amount rules',
    ];

    PaymentResult fail(String detail) {
      checks.add(SecurityCheck(names[checks.length], CheckStatus.failed, detail));
      for (var i = checks.length; i < names.length; i++) {
        checks.add(SecurityCheck(names[i], CheckStatus.skipped, 'Not reached'));
      }
      return PaymentResult(success: false, checks: checks, message: detail);
    }

    void pass(String detail) => checks.add(SecurityCheck(names[checks.length], CheckStatus.passed, detail));

    final h = req.headers;

    // 1. Which session?
    final keys = _sessions[h['X-Key-Id']];
    if (keys == null) return fail('Unknown key id ${h['X-Key-Id']}');
    pass('Session ${h['X-Key-Id']} found');

    // 2. Fresh?
    final ts = int.tryParse(h['X-Timestamp'] ?? '');
    if (ts == null) return fail('Missing timestamp');
    final age = _clock().difference(DateTime.fromMillisecondsSinceEpoch(ts));
    if (age.abs() > _maxSkew) {
      return fail('Request is ${age.inSeconds}s old (limit ${_maxSkew.inSeconds}s)');
    }
    pass('Age ${age.inMilliseconds} ms (limit ${_maxSkew.inSeconds}s)');

    // 3. Seen before? (In production: Redis SETNX with TTL = skew window.)
    final nonce = h['X-Nonce'] ?? '';
    if (nonce.isEmpty || _seenNonces.contains(nonce)) {
      return fail('Nonce ${Bytes.ellipsize(nonce, keep: 6)} already used → replay');
    }
    _seenNonces.add(nonce);
    pass('Nonce ${Bytes.ellipsize(nonce, keep: 6)} is new');

    // 4. Body untouched?
    final bodyHash = HmacService.sha256Hex(Bytes.utf8Bytes(req.body));
    if (!Bytes.constantTimeEquals(Bytes.utf8Bytes(bodyHash), Bytes.utf8Bytes(h['X-Content-SHA256'] ?? ''))) {
      return fail('Body hash mismatch — payload modified in transit');
    }
    pass('SHA-256 ${Bytes.ellipsize(bodyHash, keep: 6)}');

    // 5. HMAC over the canonical request.
    final canonical = HmacService.canonicalRequest(
      method: req.method,
      path: req.path,
      timestamp: ts,
      nonce: nonce,
      bodySha256: bodyHash,
    );
    if (!_hmac.verifyHex(keys.macKey, canonical, h['X-Signature'] ?? '')) {
      return fail('HMAC mismatch — sender does not hold the session key');
    }
    pass('Constant-time compare OK');

    // 6. Decrypt.
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final enc = EncryptedPayload.fromJson(body['enc'] as Map<String, dynamic>);
    late final String clear;
    try {
      clear = await _aes.decryptString(enc, key: SecretKey(keys.encKey));
    } on SecretBoxAuthenticationError {
      return fail('GCM tag invalid — ciphertext or AAD tampered');
    }
    final payload = jsonDecode(clear) as Map<String, dynamic>;
    pass('Decrypted ${clear.length} bytes, AAD bound to ${enc.aad}');

    // 7. Signed by the registered device?
    final deviceKey = _devices[body['deviceId']];
    final sigOk = deviceKey != null &&
        await _sig.verify(
          Bytes.utf8Bytes(Bytes.canonicalJson(payload)),
          signature: Bytes.fromBase64(body['sig'] as String),
          publicKey: deviceKey,
        );
    if (!sigOk) return fail('Signature not from registered device ${body['deviceId']}');
    pass('Verified with device ${body['deviceId']}');

    // 8. Business rules — crypto proves WHO sent it, not that it's sensible.
    final order = _orders[payload['orderId']];
    if (order == null) return fail('Unknown order');
    if (enc.aad != order.id) return fail('Encrypted payload bound to another order');
    if (payload['amount'] != order.amountPaise) {
      return fail('Amount ${payload['amount']} ≠ order amount ${order.amountPaise}');
    }
    if (_paidOrders.contains(order.id)) return fail('Order already paid');
    _paidOrders.add(order.id);
    pass('${order.displayAmount} to ${order.payee}');

    final paymentId = 'pay_${Bytes.toHex(Bytes.random(7))}';
    return PaymentResult(
      success: true,
      checks: checks,
      paymentId: paymentId,
      gatewaySignature: gatewaySignature(order.id, paymentId),
      message: 'Payment captured',
    );
  }

  /// Razorpay formula: HMAC_SHA256(order_id + "|" + payment_id, key_secret).
  String gatewaySignature(String orderId, String paymentId) => _hmac.signHex(_merchantKeySecret, '$orderId|$paymentId');

  /// What the MERCHANT BACKEND does after the checkout callback, before
  /// marking an order paid. Never trust the app's "success" callback alone.
  @override
  bool verifyGatewaySignature(String orderId, String paymentId, String signature) =>
      _hmac.verifyHex(_merchantKeySecret, '$orderId|$paymentId', signature);
}
