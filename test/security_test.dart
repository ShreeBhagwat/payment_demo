import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_demo/core/crypto/aes_gcm_service.dart';
import 'package:payment_demo/core/crypto/hmac_service.dart';
import 'package:payment_demo/core/crypto/signature_service.dart';
import 'package:payment_demo/app/providers.dart';
import 'package:payment_demo/core/payment/attack_simulation.dart';
import 'package:payment_demo/core/payment/bank_api.dart';
import 'package:payment_demo/core/payment/models.dart';
import 'package:payment_demo/core/payment/secure_payment_client.dart';
import 'package:payment_demo/core/utils/bytes.dart';
import 'package:payment_demo/features/hmac/hmac_controller.dart';
import 'package:payment_demo/features/payment/payment_controller.dart';
import 'package:payment_demo/features/signature/signature_controller.dart';

import 'support/fakes.dart';

void main() {
  group('HMAC', () {
    const hmac = HmacService();

    test('matches RFC 4231 test case 2', () {
      expect(
        hmac.signHex(Bytes.utf8Bytes('Jefe'), 'what do ya want for nothing?'),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('rejects a modified message', () {
      final key = Bytes.random(32);
      final mac = hmac.signHex(key, 'amount=100');
      expect(hmac.verifyHex(key, 'amount=100', mac), isTrue);
      expect(hmac.verifyHex(key, 'amount=900', mac), isFalse);
      expect(hmac.verifyHex(key, 'amount=100', 'zz'), isFalse);
    });
  });

  group('AES-256-GCM', () {
    final aes = AesGcmService();

    test('round-trips and uses a fresh nonce each time', () async {
      final key = await aes.newKey();
      final a = await aes.encryptString('PAN 4111 1111 1111 1111', key: key);
      final b = await aes.encryptString('PAN 4111 1111 1111 1111', key: key);
      expect(a.nonce, isNot(b.nonce));
      expect(a.cipherText, isNot(b.cipherText));
      expect(await aes.decryptString(a, key: key), 'PAN 4111 1111 1111 1111');
    });

    test('detects tampering of ciphertext and AAD', () async {
      final key = await aes.newKey();
      final p = await aes.encryptString('hello', key: key, aad: 'order_1');
      final flipped = p.copyWith(cipherText: (p.cipherText.toList()..[0] ^= 1).toBytes());
      await expectLater(aes.decrypt(flipped, key: key), throwsA(isA<SecretBoxAuthenticationError>()));
      await expectLater(
        aes.decrypt(p.copyWith(aad: 'order_2'), key: key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('compact format round-trips', () async {
      final key = await aes.newKey();
      final p = await aes.encryptString('x', key: key);
      expect(await aes.decryptString(EncryptedPayload.fromCompact(p.toCompact()), key: key), 'x');
    });
  });

  group('Ed25519', () {
    final sig = SignatureService();

    test('signs, verifies and restores from seed', () async {
      final id = await sig.generate();
      final msg = Bytes.utf8Bytes('pay 500');
      final s = await sig.sign(msg, id);
      expect(await sig.verify(msg, signature: s, publicKey: id.publicKey), isTrue);
      expect(await sig.verify(Bytes.utf8Bytes('pay 900'), signature: s, publicKey: id.publicKey), isFalse);
      final restored = await sig.fromSeed(await sig.exportSeed(id));
      expect(restored.publicKey, id.publicKey);
    });
  });

  group('Secure payment flow', () {
    late SecurePaymentClient client;
    late MerchantApi merchant;

    setUp(() async {
      final c = testContainer();
      client = c.read(paymentClientProvider);
      merchant = c.read(merchantApiProvider);
      await client.onboard();
    });

    PaymentOrder order() => merchant.createOrder(amountPaise: 2500000, payee: 'Acme');

    test('legit payment passes every check', () async {
      final r = (await client.pay(order())).result;
      expect(r.success, isTrue);
      expect(r.checks.every((c) => c.status == CheckStatus.passed), isTrue);
    });

    final expected = {
      AttackMode.tamperInTransit: 'Body hash',
      AttackMode.replay: 'Nonce (anti-replay)',
      AttackMode.staleRequest: 'Timestamp freshness',
      AttackMode.forgedDevice: 'Ed25519 device signature',
      AttackMode.amountManipulation: 'Order & amount rules',
      AttackMode.hmacTamper: 'HMAC-SHA256 signature',
      AttackMode.signatureTamper: 'Ed25519 device signature',
    };
    for (final e in expected.entries) {
      test('${e.key.label} is blocked at "${e.value}"', () async {
        final r = (await client.pay(order(), attack: e.key)).result;
        expect(r.success, isFalse);
        expect(r.checks.firstWhere((c) => c.status == CheckStatus.failed).name, e.value);
      });
    }

    test('a tamper left on in the HMAC lab is applied to the payment', () {
      final c = testContainer();
      final payment = c.read(paymentLabProvider.notifier);
      expect(payment.effectiveAttack, AttackMode.none);
      c.read(hmacLabProvider.notifier).tamper();
      expect(payment.effectiveAttack, AttackMode.hmacTamper);
      c.read(hmacLabProvider.notifier).restore();
      expect(payment.effectiveAttack, AttackMode.none);
    });

    test('a tamper left on in the Signatures lab is applied to the payment', () {
      final c = testContainer();
      final payment = c.read(paymentLabProvider.notifier);
      final sig = c.read(signatureLabProvider.notifier);
      sig.setOtherKey(true);
      expect(payment.effectiveAttack, AttackMode.forgedDevice);
      sig.setTamperAmount(true);
      expect(payment.effectiveAttack, AttackMode.signatureTamper);
      c.read(labTamperProvider)!.restore();
      expect(payment.effectiveAttack, AttackMode.forgedDevice);
      c.read(labTamperProvider)!.restore();
      expect(payment.effectiveAttack, AttackMode.none);
    });

    test('every AttackMode has a simulation (open/closed registry)', () {
      expect(attackSimulations.keys, containsAll(AttackMode.values));
    });

    test('unbinding removes only the SDK keys', () async {
      final c = testContainer();
      final vault = c.read(secureVaultProvider);
      await vault.put('pin.pbkdf2.hash', 'keep-me');
      await c.read(paymentClientProvider).onboard();
      await c.read(paymentClientProvider).reset();
      expect(await vault.dump(), {'pin.pbkdf2.hash': 'keep-me'});
    });
  });

  test('Indian amount formatting', () {
    const o = PaymentOrder(id: 'o', amountPaise: 1234567890, currency: 'INR', payee: 'p', receipt: 'r');
    expect(o.displayAmount, '₹1,23,45,678.90');
  });
}

extension on List<int> {
  Uint8List toBytes() => Uint8List.fromList(this);
}
