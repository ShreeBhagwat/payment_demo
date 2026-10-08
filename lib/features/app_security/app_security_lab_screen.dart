import 'package:flutter/material.dart';

import '../../app/lab_module.dart';
import '../../widgets/lab_widgets.dart';
import 'sections/biometric_section.dart';
import 'sections/integrity_section.dart';
import 'sections/pin_section.dart';
import 'sections/pinning_section.dart';
import 'sections/screenshot_section.dart';
import 'sections/session_section.dart';
import 'sections/storage_section.dart';

/// Module 6. Pure composition: every card is its own widget with its own
/// controller (single responsibility); this screen only lays them out.
class AppSecurityLabScreen extends StatelessWidget {
  const AppSecurityLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LabScaffold(
      module: LabModule.appSecurity,
      children: [
        StorageSection(),
        PinSection(),
        BiometricSection(),
        SessionSection(),
        ScreenshotSection(),
        IntegritySection(),
        PinningSection(),
        CodeSnippet(title: 'Code · lock on background + session timeout', code: _lockSnippet),
        CodeSnippet(title: 'Code · biometrics (local_auth 3)', code: _biometricSnippet),
        CodeSnippet(title: 'Code · certificate pinning with Dio', code: _pinningSnippet),
      ],
    );
  }
}

const _lockSnippet = r'''
final appLockProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

class AppLockController extends Notifier<AppLockState> {
  @override
  AppLockState build() {
    final l = AppLifecycleListener(onStateChange: onLifecycleChanged);
    ref.onDispose(l.dispose);
    return AppLockState(lastActivity: now());
  }

  void onLifecycleChanged(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) state = state.copyWith(obscured: true);
    if (s == AppLifecycleState.paused) backgroundedAt = now();
    if (s == AppLifecycleState.resumed &&
        now().difference(backgroundedAt) >= state.backgroundGrace) lock();
  }

  void userActivity() {                    // Listener(onPointerDown: ...)
    _idle?.cancel();
    _idle = Timer(state.inactivityTimeout, () => lock(LockReason.inactivity));
  }
}

// Server-side session expiry: refresh once, then force re-login
dio.interceptors.add(InterceptorsWrapper(onError: (e, h) async {
  if (e.response?.statusCode == 401 && await auth.tryRefresh()) {
    return h.resolve(await dio.fetch(e.requestOptions));
  }
  if (e.response?.statusCode == 401) {
    ref.read(appLockProvider.notifier).lock(LockReason.inactivity);
  }
  h.next(e);
}));''';

const _biometricSnippet = r'''
final auth = LocalAuthentication();
final types = await auth.getAvailableBiometrics();   // face, fingerprint…

try {
  final ok = await auth.authenticate(
    localizedReason: 'Unlock SecurePay',
    biometricOnly: true,              // our PIN is the fallback
    persistAcrossBackgrounding: true,
  );
} on LocalAuthException catch (e) {
  if (e.code == LocalAuthExceptionCode.biometricLockout) usePinInstead();
}
// iOS  : NSFaceIDUsageDescription in Info.plist
// Droid: MainActivity extends FlutterFragmentActivity''';

const _pinningSnippet = r'''
dio.httpClientAdapter = IOHttpClientAdapter(
  createHttpClient: () => HttpClient()
    ..badCertificateCallback = (_, __, ___) => false,
  validateCertificate: (cert, host, port) {
    if (cert == null) return false;
    final pin = base64(sha256(extractSpki(cert.der)));
    return const {          // example values: use your server's real pins
      'api.mybank.com': {
        'r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E=', // current key
        'YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=', // backup key
      },
    }[host]?.contains(pin) ?? false;
  },
);''';
