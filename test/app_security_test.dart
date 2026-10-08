import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_demo/app/providers.dart';
import 'package:payment_demo/core/security/biometric_service.dart';
import 'package:payment_demo/core/security/certificate_pinning.dart';
import 'package:payment_demo/core/security/device_integrity.dart';
import 'package:payment_demo/core/security/pin_service.dart';
import 'package:payment_demo/core/storage/secure_vault.dart';
import 'package:payment_demo/core/utils/bytes.dart';
import 'package:payment_demo/features/app_lock/app_lock_controller.dart';
import 'package:payment_demo/features/app_security/integrity_controller.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PinService', () {
    late InMemoryStore store;
    late DateTime now;
    late PinService pins;

    setUp(() {
      store = InMemoryStore();
      now = DateTime(2026, 10, 2, 10);
      pins = PinService(store, iterations: 1000, clock: () => now);
    });

    test('rejects weak PINs', () {
      for (final weak in ['111111', '123456', '654321', '121212', '123123', '081994', '12345', '12a456']) {
        expect(pins.validateNewPin(weak), isNotNull, reason: weak);
      }
      expect(pins.validateNewPin('482913'), isNull);
    });

    test('stores only a salted hash, never the PIN', () async {
      await pins.setPin('482913');
      final all = await store.readAll();
      expect(all.values.any((v) => v.contains('482913')), isFalse);
      expect(all.keys, containsAll([PinService.kHash, PinService.kSalt]));
    });

    test('verifies, counts failures and locks out with doubling backoff', () async {
      await pins.setPin('482913');
      expect((await pins.verify('482913')).ok, isTrue);

      for (var left = 4; left >= 1; left--) {
        final r = await pins.verify('000000');
        expect(r.status, PinStatus.wrong);
        expect(r.attemptsLeft, left);
      }
      final locked = await pins.verify('000000');
      expect(locked.status, PinStatus.lockedOut);
      expect(locked.lockedUntil, now.add(const Duration(seconds: 30)));

      // Even the correct PIN is refused while locked out.
      expect((await pins.verify('482913')).status, PinStatus.lockedOut);

      // Lockout survives an app restart (new instance, same store).
      final restarted = PinService(store, iterations: 1000, clock: () => now);
      expect((await restarted.verify('482913')).status, PinStatus.lockedOut);

      now = now.add(const Duration(seconds: 31));
      final again = await pins.verify('000000');
      expect(again.lockedUntil, now.add(const Duration(seconds: 60)));

      now = now.add(const Duration(seconds: 61));
      expect((await pins.verify('482913')).ok, isTrue);
      expect(await store.read(PinService.kFailures), isNull);
    });

    test('change flow requires the current PIN and a different strong PIN', () async {
      await pins.setPin('482913');
      expect((await pins.changePin(current: '000000', next: '736251')).status, PinStatus.wrong);
      expect(() => pins.changePin(current: '482913', next: '111111'), throwsArgumentError);
      expect(() => pins.changePin(current: '482913', next: '482913'), throwsArgumentError);
      expect((await pins.changePin(current: '482913', next: '736251')).ok, isTrue);
      expect((await pins.verify('736251')).ok, isTrue);
      expect((await pins.verify('482913')).ok, isFalse);
    });
  });

  group('AppLockController (Riverpod)', () {
    late InMemoryStore store;
    late FakeBiometrics bio;
    late DateTime now;

    ProviderContainer container() => testContainer(store: store, biometrics: bio, clock: () => now);

    /// Reads the lock provider and lets its async vault load finish.
    Future<AppLockController> ready(ProviderContainer c) async {
      c.read(appLockProvider);
      for (var i = 0; i < 50 && !c.read(appLockProvider).ready; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return c.read(appLockProvider.notifier);
    }

    setUp(() {
      store = InMemoryStore();
      bio = FakeBiometrics();
      now = DateTime(2026, 10, 2, 10);
    });

    test('no PIN → never locks', () async {
      final c = container();
      (await ready(c)).lock(LockReason.manual);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('cold start with a PIN starts locked; PIN unlocks', () async {
      await PinService(store, iterations: 1000).setPin('482913');
      final c = container();
      final lock = await ready(c);
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).reason, LockReason.coldStart);
      expect((await lock.unlockWithPin('000000')).ok, isFalse);
      expect(c.read(appLockProvider).locked, isTrue);
      expect((await lock.unlockWithPin('482913')).ok, isTrue);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('background: obscured immediately, locks only after grace period', () async {
      final c = container();
      final lock = await ready(c);
      await lock.setPin('482913');
      lock.setBackgroundGrace(const Duration(seconds: 10));

      lock.onLifecycleChanged(AppLifecycleState.inactive);
      expect(c.read(appLockProvider).obscured, isTrue);
      lock.onLifecycleChanged(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 5));
      lock.onLifecycleChanged(AppLifecycleState.resumed);
      expect(c.read(appLockProvider).obscured, isFalse);
      expect(c.read(appLockProvider).locked, isFalse, reason: 'within 10 s grace');

      lock.onLifecycleChanged(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 11));
      lock.onLifecycleChanged(AppLifecycleState.resumed);
      expect(c.read(appLockProvider).locked, isTrue);
      expect(c.read(appLockProvider).reason, LockReason.background);
    });

    test('inactivity timer locks; activity resets it', () {
      fakeAsync((fa) {
        final c = ProviderContainer(
          overrides: testOverrides(store: store, biometrics: bio, clock: () => now),
        );
        c.read(appLockProvider);
        fa.flushMicrotasks();
        final lock = c.read(appLockProvider.notifier);
        lock.setPin('482913');
        fa.flushMicrotasks();
        lock.setInactivityTimeout(const Duration(seconds: 30));

        fa.elapse(const Duration(seconds: 20));
        lock.userActivity();
        fa.elapse(const Duration(seconds: 20));
        expect(c.read(appLockProvider).locked, isFalse, reason: 'activity at 20 s restarted the 30 s timer');
        fa.elapse(const Duration(seconds: 11));
        expect(c.read(appLockProvider).locked, isTrue);
        expect(c.read(appLockProvider).reason, LockReason.inactivity);
        c.dispose();
      });
    });

    test('biometrics: enabling needs a scan; blocked during PIN lockout', () async {
      final c = container();
      final lock = await ready(c);
      await lock.setPin('482913');

      bio.next = BiometricOutcome.canceled;
      expect(await lock.setBiometricEnabled(true), BiometricOutcome.canceled);
      expect(c.read(appLockProvider).biometricEnabled, isFalse);

      bio.next = BiometricOutcome.success;
      await lock.setBiometricEnabled(true);
      expect(c.read(appLockProvider).biometricEnabled, isTrue);

      lock.lock(LockReason.manual);
      for (var i = 0; i < 5; i++) {
        await lock.unlockWithPin('000000');
      }
      final callsBefore = bio.calls;
      expect(await lock.unlockWithBiometrics(), BiometricOutcome.lockedOut);
      expect(bio.calls, callsBefore, reason: 'no prompt shown during lockout');
      expect(c.read(appLockProvider).locked, isTrue);
    });

    test('biometric prompt pausing the app does not re-lock it', () async {
      final c = container();
      final lock = await ready(c);
      await lock.setPin('482913');
      await lock.setBiometricEnabled(true);
      lock.lock(LockReason.manual);

      // iOS: showing Face ID sends the app inactive → paused → resumed.
      bio.duringPrompt = () {
        lock.onLifecycleChanged(AppLifecycleState.inactive);
        lock.onLifecycleChanged(AppLifecycleState.paused);
        now = now.add(const Duration(seconds: 20));
        lock.onLifecycleChanged(AppLifecycleState.resumed);
      };
      expect(await lock.unlockWithBiometrics(), BiometricOutcome.success);
      expect(c.read(appLockProvider).locked, isFalse);
    });

    test('Forgot PIN wipes every credential and bumps the vault generation', () async {
      await store.write(VaultKeys.deviceSigningSeed, 'seed');
      final c = container();
      final lock = await ready(c);
      await lock.setPin('482913');
      final gen = c.read(vaultGenerationProvider);
      await lock.resetCredentials();
      expect(await store.readAll(), isEmpty);
      expect(c.read(appLockProvider).pinSet, isFalse);
      expect(c.read(vaultGenerationProvider), gen + 1);
    });
  });

  group('Device integrity', () {
    test('rooted device + Block policy blocks payments; Warn does not', () async {
      final c = testContainer(probe: FakeIntegrityProbe(compromised: true));
      final integrity = c.read(integrityProvider.notifier);
      await integrity.scan();
      expect(c.read(integrityProvider).report!.risk, RiskLevel.critical);
      expect(c.read(integrityProvider).paymentBlockReason, isNull, reason: 'default policy is Warn');
      integrity.setPolicy(IntegrityPolicy.block);
      expect(c.read(integrityProvider).paymentBlockReason, isNotNull);
    });

    test('emulator alone is only a warning, never blocks', () async {
      final c = testContainer(probe: FakeIntegrityProbe(realDevice: false));
      final integrity = c.read(integrityProvider.notifier)..setPolicy(IntegrityPolicy.block);
      await integrity.scan();
      expect(c.read(integrityProvider).report!.risk, RiskLevel.warn);
      expect(c.read(integrityProvider).paymentBlockReason, isNull);
    });
  });

  group('Certificate pinning', () {
    // Generated with openssl; expected pins from:
    // openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    const ecCert =
        'MIIBkDCCATWgAwIBAgIUJX4azVp0/hZRhX7SkAuwvuEIEpkwCgYIKoZIzj0EAwIwHTEbMBkGA1UEAwwSYXBpLnNlY3VyZXBheS50ZXN0MB4XDTI2MTAwMjA1MzIwM1oXDTM2MDkyOTA1MzIwM1owHTEbMBkGA1UEAwwSYXBpLnNlY3VyZXBheS50ZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAES76IGVeSj242YdbciLbjr7Q9mk/Bv1gXYbbzZ/EOXBveP9AeKoaNKsB207o6IfK3l7yNh3Gncx/3g+y6U0FGAaNTMFEwHQYDVR0OBBYEFCDC/94KPRzpYPYwF2zgKm4gG+fZMB8GA1UdIwQYMBaAFCDC/94KPRzpYPYwF2zgKm4gG+fZMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAK3i6CRNPR5/nhgDfCSdPACfPfC4wzNlPwVNibs3b3LxAiEA39rUArDjElEUB9afilh7wzq5a1FBCaPQ2z/JiOMQle8=';
    const rsaCert =
        'MIIDGzCCAgOgAwIBAgIULrtudQYGZl93szcbFfi1IWLf6CgwDQYJKoZIhvcNAQELBQAwHTEbMBkGA1UEAwwScnNhLnNlY3VyZXBheS50ZXN0MB4XDTI2MTAwMjA1MzIwNFoXDTM2MDkyOTA1MzIwNFowHTEbMBkGA1UEAwwScnNhLnNlY3VyZXBheS50ZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqDLF5UnqGIcX5+zyF+xl+TOo4cgRJThK6Seh6I6iaYesHhHa3IcJ6MFA57YroBU3RDZ+rh0SX0Y6xGmbjkQq/0p6tvwv8BsyWL2ht8LC2wJ6AYGW/5b8NvLX3juj7Pi2JvNTFF5bYUcpm8N1nDGkpzyUHm52fTHgrQfqkQNMeuU44X69a0xx5i2bmYaqT33ktoiKgwOJmLAAiLnhagXZCUm1W809HZIT3eXy3kqlhnNLXUYy5dKV0h84tFDVEA4bkaZY+aoe7YYFxvyizBCEtN0PHVZmuZp9ai+y7pYihVNyjgYqT52J7jc45mD3NmmIaA1x6/eY5M7OCJhYQeRvpwIDAQABo1MwUTAdBgNVHQ4EFgQUCG+clkRs2b5EDvoaClWVxb+KeR0wHwYDVR0jBBgwFoAUCG+clkRs2b5EDvoaClWVxb+KeR0wDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAPZAL9saLGjCm4Xxz71kzyFrh0tspgDbS15dScjXZ0BqQY7MRppSUrTMG9rJo5P2nxB9GKcgJvwUbi9A+Um/nzodUR19J0gR3RTtz5buxXsF1lTiBwJxbnRzpzzC8pNljmhWpYAjZMUHok/fi+VMr77Eg0hYv1Sm8zxBlhINkfZ3C5BsTgekNKzPErDm7Gc1ywLOOhrk4BSXaH3EphMsN/R/fI12bEgAgjBEhH5snTYjVnT2g9UqMeWex3JC3vlZUSTfu6PJCuPR+YoqpYtVvBGaPt58h6TiT7v6xVTGrA3cVYqCEJBuki04Hl3589SFB/smfN1SJlH9nw08KqHyzQg==';

    test('SPKI pin matches openssl (EC P-256)', () {
      expect(CertificatePinning.spkiPin(Bytes.fromBase64(ecCert)), 'Yfzqqyy+qVAQIEWEfFuDapEuy6pb0FcTJ1bz/kuO3Fc=');
    });

    test('SPKI pin matches openssl (RSA-2048, long-form DER lengths)', () {
      expect(CertificatePinning.spkiPin(Bytes.fromBase64(rsaCert)), 'SLZFvNFESp/b5F1wUcKUct+qXpTn6NupiP4fg90SbkU=');
    });

    test('rejects garbage', () {
      expect(() => CertificatePinning.spkiPin([0x30, 0x82, 0xFF, 0xFF, 0x00]), throwsFormatException);
    });
  });
}
