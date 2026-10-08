import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:payment_demo/app/providers.dart';
import 'package:payment_demo/core/security/biometric_service.dart';
import 'package:payment_demo/core/security/certificate_pinning.dart';
import 'package:payment_demo/core/security/device_integrity.dart';
import 'package:payment_demo/core/security/screen_protector.dart';
import 'package:payment_demo/core/storage/secure_vault.dart';
import 'package:payment_demo/core/utils/clock.dart';

class FakeBiometrics implements BiometricAuthenticator {
  FakeBiometrics({this.enrolled = true});

  final bool enrolled;
  BiometricOutcome next = BiometricOutcome.success;
  int calls = 0;

  /// Runs during authenticate(), e.g. to simulate the OS sheet pausing the app.
  void Function()? duringPrompt;

  @override
  Future<BiometricCapability> capability() async =>
      BiometricCapability(deviceSupported: enrolled, types: enrolled ? [BiometricType.fingerprint] : []);

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    calls++;
    duringPrompt?.call();
    return next;
  }
}

class FakeScreenProtector implements ScreenProtector {
  bool protected = false;

  @override
  Future<void> setProtected(bool on) async => protected = on;

  @override
  Stream<CaptureEvent> events() => const Stream.empty();
}

class FakeIntegrityProbe implements IntegrityProbe {
  FakeIntegrityProbe({this.compromised = false, this.realDevice = true});

  final bool compromised;
  final bool realDevice;

  @override
  Future<bool> isCompromised() async => compromised;
  @override
  Future<bool> isRealDevice() async => realDevice;
  @override
  Future<bool> isDeveloperModeOn() async => false;
  @override
  Future<bool> isUsbDebuggingOn() async => false;
  @override
  Future<bool> isOnExternalStorage() async => false;
}

class FakeCertificateInspector implements CertificateInspector {
  @override
  Future<CertInfo> inspect(String host, {int port = 443}) async => CertInfo(
        subject: 'CN=$host',
        issuer: 'CN=Test CA',
        validUntil: DateTime(2030),
        spkiPin: 'Yfzqqyy+qVAQIEWEfFuDapEuy6pb0FcTJ1bz/kuO3Fc=',
        certSha256: '00',
      );
}

/// Replaces every platform-bound provider, so app code runs in plain tests.
/// This is the payoff of the composition root: no feature code changes.
List<Override> testOverrides({
  KeyValueStore? store,
  BiometricAuthenticator? biometrics,
  IntegrityProbe? probe,
  Clock? clock,
}) =>
    [
      keyValueStoreProvider.overrideWithValue(store ?? InMemoryStore()),
      biometricAuthenticatorProvider.overrideWithValue(biometrics ?? FakeBiometrics(enrolled: false)),
      screenProtectorProvider.overrideWithValue(FakeScreenProtector()),
      integrityProbeProvider.overrideWithValue(probe ?? FakeIntegrityProbe()),
      certificateInspectorProvider.overrideWithValue(FakeCertificateInspector()),
      pinIterationsProvider.overrideWithValue(1000),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ];

ProviderContainer testContainer({
  KeyValueStore? store,
  BiometricAuthenticator? biometrics,
  IntegrityProbe? probe,
  Clock? clock,
}) =>
    ProviderContainer.test(
      overrides: testOverrides(store: store, biometrics: biometrics, probe: probe, clock: clock),
    );
