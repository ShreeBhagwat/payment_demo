import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricCapability {
  const BiometricCapability({required this.deviceSupported, required this.types});

  final bool deviceSupported; // has biometric hardware OR device passcode
  final List<BiometricType> types; // enrolled biometrics

  bool get enrolled => types.isNotEmpty;

  String get label {
    if (types.contains(BiometricType.face)) return 'Face ID / Face unlock';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.iris)) return 'Iris';
    if (types.isNotEmpty) return 'Biometrics';
    return 'None enrolled';
  }
}

enum BiometricOutcome {
  success('Authenticated'),
  failed('Not recognised'),
  canceled('Cancelled by user'),
  notAvailable('No biometrics enrolled on this device'),
  lockedOut('Too many attempts — biometrics locked by the OS. Use your PIN.'),
  error('Biometric error');

  const BiometricOutcome(this.message);

  final String message;
}

/// Abstraction so the lock logic can be unit-tested with a fake.
abstract interface class BiometricAuthenticator {
  Future<BiometricCapability> capability();
  Future<BiometricOutcome> authenticate(String reason);
}

/// `local_auth` wrapper.
///
/// Setup checklist:
///  * iOS: NSFaceIDUsageDescription in Info.plist (app crashes on Face ID without it).
///  * Android: MainActivity must extend FlutterFragmentActivity.
///
/// Important: `authenticate()` only returns a bool. On a rooted device a hook
/// (Frida) can make it return true. For high-value actions, bind a key to
/// biometrics instead (Keystore `setUserAuthenticationRequired`, Keychain
/// `.biometryCurrentSet`), e.g. `AndroidOptions.biometric()` in
/// flutter_secure_storage, so the secret is only released after a real scan.
class LocalAuthBiometrics implements BiometricAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<BiometricCapability> capability() async {
    try {
      return BiometricCapability(
        deviceSupported: await _auth.isDeviceSupported(),
        types: await _auth.getAvailableBiometrics(),
      );
    } on PlatformException {
      return const BiometricCapability(deviceSupported: false, types: []);
    }
  }

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true, // the PIN is our fallback, not the device passcode
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricOutcome.success : BiometricOutcome.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout =>
          BiometricOutcome.canceled,
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          BiometricOutcome.notAvailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          BiometricOutcome.lockedOut,
        _ => BiometricOutcome.error,
      };
    } on PlatformException {
      return BiometricOutcome.error;
    }
  }
}
