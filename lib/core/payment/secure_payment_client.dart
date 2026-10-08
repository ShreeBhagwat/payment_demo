import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../crypto/aes_gcm_service.dart';
import '../crypto/hmac_service.dart';
import '../crypto/key_exchange_service.dart';
import '../crypto/signature_service.dart';
import '../storage/secure_vault.dart';
import '../utils/bytes.dart';
import '../utils/clock.dart';
import 'attack_simulation.dart';
import 'bank_api.dart';
import 'models.dart';
import 'trace.dart';

export 'trace.dart';

class PaymentAttempt {
  const PaymentAttempt({required this.trace, required this.result, required this.request});

  final List<TraceStep> trace;
  final PaymentResult result;
  final ApiRequest request;
}

/// Keys this SDK keeps in Secure Storage. Single source of truth (DRY) for
/// onboarding, payment and unbinding.
const _sdkVaultKeys = [
  VaultKeys.deviceSigningSeed,
  VaultKeys.deviceId,
  VaultKeys.sessionEncKey,
  VaultKeys.sessionMacKey,
  VaultKeys.sessionKeyId,
];

/// Client-side payment SDK: the code that really ships in the app.
///
/// Layers, outermost first:
///   HMAC request signing → AES-GCM payload encryption → Ed25519 authorisation
/// Each layer defends against something the others don't.
///
/// Dependency inversion: every collaborator is injected. The SDK knows the
/// [BankApi] interface, not the in-process mock; swapping in a real HTTPS
/// client changes no code here.
class SecurePaymentClient {
  SecurePaymentClient({
    required this._bank,
    required this._merchant,
    required this._vault,
    required this._hmac,
    required this._aes,
    required this._signatures,
    required this._keyExchange,
    Clock? clock,
  }) : _clock = clock ?? DateTime.now;

  final BankApi _bank;
  final MerchantApi _merchant; // only to show the backend's verification step
  final SecureVault _vault;
  final HmacService _hmac;
  final AesGcmService _aes;
  final SignatureService _signatures;
  final KeyExchangeService _keyExchange;
  final Clock _clock;

  static const _path = '/v1/payments/authorize';

  Future<bool> get isOnboarded async =>
      await _vault.get(VaultKeys.deviceSigningSeed) != null && await _vault.get(VaultKeys.sessionKeyId) != null;

  /// Device binding: create a signing identity and a session with the bank.
  Future<List<TraceStep>> onboard() async {
    final trace = <TraceStep>[];

    final identity = await _signatures.generate();
    final deviceId = 'dev_${Bytes.toHex(Bytes.random(4))}';
    await _vault.put(VaultKeys.deviceSigningSeed, Bytes.toBase64(await _signatures.exportSeed(identity)));
    await _vault.put(VaultKeys.deviceId, deviceId);
    await _bank.registerDevice(deviceId, identity.publicKey);
    trace
      ..add(TraceStep('Ed25519 device key generated', 'Fingerprint ${await identity.fingerprint()}'))
      ..add(const TraceStep('Private seed → Secure Storage', 'Keychain / Android Keystore'))
      ..add(TraceStep('Public key registered', '$deviceId · ${Bytes.ellipsize(identity.publicKeyB64)}'));

    final eph = await _keyExchange.newEphemeralKeyPair();
    final hs = await _bank.handshake(await _keyExchange.publicKeyOf(eph));
    final keys = await _keyExchange.deriveSessionKeys(
      myKeyPair: eph,
      theirPublicKey: hs.serverPublicKey,
      salt: hs.salt,
    );
    await _vault.put(VaultKeys.sessionEncKey, Bytes.toBase64(keys.encKey));
    await _vault.put(VaultKeys.sessionMacKey, Bytes.toBase64(keys.macKey));
    await _vault.put(VaultKeys.sessionKeyId, hs.keyId);
    trace
      ..add(TraceStep('X25519 handshake', 'Server pub ${Bytes.ellipsize(Bytes.toHex(hs.serverPublicKey), keep: 8)}'))
      ..add(TraceStep('HKDF-SHA256 → 2 keys', 'AES-256 + HMAC key · ${hs.keyId}'));
    return trace;
  }

  Future<PaymentAttempt> pay(PaymentOrder order, {AttackMode attack = AttackMode.none}) async {
    final sim = attackSimulations[attack]!;
    final trace = <TraceStep>[];
    final session = await _loadSession();
    trace.add(const TraceStep('Keys loaded from Secure Storage', 'enc · mac · signing seed'));

    // 1. Payload
    final payload = sim.tamperPayload({
      'orderId': order.id,
      'amount': order.amountPaise,
      'currency': order.currency,
      'payee': order.payee,
      'issuedAt': _clock().toUtc().toIso8601String(),
    }, trace);
    final canonical = Bytes.canonicalJson(payload);
    trace.add(TraceStep('Canonical payload', canonical));

    // 2. Signature (authorisation / non-repudiation)
    final signer = await sim.signingIdentity(session.identity, _signatures, trace);
    final signature = await _signatures.sign(Bytes.utf8Bytes(canonical), signer);
    trace.add(TraceStep('Ed25519 signature (64 B)', Bytes.ellipsize(Bytes.toBase64(signature))));

    // 3. Encryption (confidentiality); AAD binds the ciphertext to this order.
    final sent = sim.alterSignedPayload(canonical, trace);
    final enc = await _aes.encryptString(sent, key: session.encKey, aad: order.id);
    trace.add(TraceStep('AES-256-GCM ciphertext', Bytes.ellipsize(Bytes.toBase64(enc.cipherText))));

    final body = jsonEncode({'deviceId': session.deviceId, 'enc': enc.toJson(), 'sig': Bytes.toBase64(signature)});

    // 4. HMAC (request integrity + authenticity + freshness)
    final headers = _hmac.signRequest(
      keyId: session.keyId,
      key: session.macKey,
      method: 'POST',
      path: _path,
      body: body,
      timestamp: sim.requestTimestamp(_clock()),
    );
    trace.add(TraceStep('HMAC-SHA256 headers', 'X-Signature ${Bytes.ellipsize(headers.signature, keep: 8)}'));

    // 5. Network: where the attacker lives.
    final request = await sim.intercept(
      ApiRequest(method: 'POST', path: _path, headers: headers.toMap(), body: body),
      _bank,
      trace,
    );
    final result = await _bank.processPayment(request);

    // 6. Gateway signature check (belongs on the merchant backend).
    if (result.success) {
      final ok = _merchant.verifyGatewaySignature(order.id, result.paymentId!, result.gatewaySignature!);
      trace.add(TraceStep('Gateway signature verified', ok ? 'HMAC(order_id|payment_id) ✓' : 'INVALID'));
    }
    return PaymentAttempt(trace: trace, result: result, request: request);
  }

  /// Unbind: remove only this SDK's keys (the app PIN etc. must survive).
  Future<void> reset() async {
    for (final k in _sdkVaultKeys) {
      await _vault.remove(k);
    }
  }

  Future<_Session> _loadSession() async {
    Future<String> need(String key) async =>
        await _vault.get(key) ?? (throw StateError('Device not bound: missing $key'));
    return _Session(
      encKey: SecretKey(Bytes.fromBase64(await need(VaultKeys.sessionEncKey))),
      macKey: Bytes.fromBase64(await need(VaultKeys.sessionMacKey)),
      keyId: await need(VaultKeys.sessionKeyId),
      deviceId: await need(VaultKeys.deviceId),
      identity: await _signatures.fromSeed(Bytes.fromBase64(await need(VaultKeys.deviceSigningSeed))),
    );
  }
}

class _Session {
  const _Session({
    required this.encKey,
    required this.macKey,
    required this.keyId,
    required this.deviceId,
    required this.identity,
  });

  final SecretKey encKey;
  final List<int> macKey;
  final String keyId;
  final String deviceId;
  final DeviceIdentity identity;
}
