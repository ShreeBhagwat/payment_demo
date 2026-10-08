import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/pin_service.dart';

enum LockReason {
  coldStart('App launched'),
  background('Returned from background'),
  inactivity('Session timed out'),
  manual('Locked manually');

  const LockReason(this.label);

  final String label;
}

@immutable
class AppLockState {
  const AppLockState({
    required this.lastActivity,
    this.ready = false,
    this.pinSet = false,
    this.biometricEnabled = false,
    this.locked = false,
    this.obscured = false,
    this.reason,
    this.inactivityTimeout = const Duration(minutes: 2),
    this.backgroundGrace = Duration.zero,
  });

  final bool ready;
  final bool pinSet;
  final bool biometricEnabled;
  final bool locked;
  final bool obscured; // app-switcher privacy shield
  final LockReason? reason;
  final DateTime lastActivity;
  final Duration inactivityTimeout;
  final Duration backgroundGrace;

  /// Content must be hidden behind the lock screen (or splash while loading).
  bool get guarded => !ready || locked;

  Duration timeUntilAutoLock(DateTime now) {
    if (!pinSet || locked) return Duration.zero;
    final left = inactivityTimeout - now.difference(lastActivity);
    return left.isNegative ? Duration.zero : left;
  }

  AppLockState copyWith({
    bool? ready,
    bool? pinSet,
    bool? biometricEnabled,
    bool? locked,
    bool? obscured,
    LockReason? Function()? reason,
    DateTime? lastActivity,
    Duration? inactivityTimeout,
    Duration? backgroundGrace,
  }) =>
      AppLockState(
        ready: ready ?? this.ready,
        pinSet: pinSet ?? this.pinSet,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        locked: locked ?? this.locked,
        obscured: obscured ?? this.obscured,
        reason: reason != null ? reason() : this.reason,
        lastActivity: lastActivity ?? this.lastActivity,
        inactivityTimeout: inactivityTimeout ?? this.inactivityTimeout,
        backgroundGrace: backgroundGrace ?? this.backgroundGrace,
      );
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(AppLockController.new);

/// Enrolled biometrics on this device (Face ID, fingerprint…).
final biometricCapabilityProvider = FutureProvider<BiometricCapability>(
  (ref) => ref.watch(biometricAuthenticatorProvider).capability(),
);

/// App-wide lock: cold start, background, inactivity, manual.
///
/// The lock only engages once a PIN exists: the PIN is the root credential,
/// biometrics are a convenience on top of it.
class AppLockController extends Notifier<AppLockState> {
  static const kBiometricEnabled = 'settings.biometric_unlock';

  Timer? _idleTimer;
  DateTime? _backgroundedAt;
  bool _systemPromptActive = false; // a biometric sheet can pause the app

  PinService get _pins => ref.read(pinServiceProvider);
  BiometricAuthenticator get _biometrics => ref.read(biometricAuthenticatorProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  AppLockState build() {
    final lifecycle = AppLifecycleListener(onStateChange: onLifecycleChanged);
    ref.onDispose(() {
      lifecycle.dispose();
      _idleTimer?.cancel();
    });
    Future.microtask(_load);
    return AppLockState(lastActivity: _now());
  }

  Future<void> _load() async {
    final pinSet = await _pins.isSet;
    final bio = pinSet && await ref.read(keyValueStoreProvider).read(kBiometricEnabled) == 'true';
    if (!ref.mounted) return;
    state = state.copyWith(ready: true, pinSet: pinSet, biometricEnabled: bio);
    if (pinSet) lock(LockReason.coldStart);
  }

  // ------------------------------------------------------------ session timer

  /// Call on every user interaction (wired to a root Listener).
  void userActivity() {
    if (state.locked) return;
    state = state.copyWith(lastActivity: _now());
    _restartIdleTimer();
  }

  void setInactivityTimeout(Duration d) {
    state = state.copyWith(inactivityTimeout: d);
    userActivity();
  }

  void setBackgroundGrace(Duration d) => state = state.copyWith(backgroundGrace: d);

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!state.pinSet) return;
    _idleTimer = Timer(state.inactivityTimeout, () => lock(LockReason.inactivity));
  }

  // --------------------------------------------------------------- lifecycle

  void onLifecycleChanged(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _setObscured(true);
      case AppLifecycleState.paused:
        _setObscured(true);
        _backgroundedAt ??= _now();
        _idleTimer?.cancel(); // timers don't run reliably in background
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        _setObscured(false);
        if (!state.pinSet || state.locked || _systemPromptActive) return;
        if (since != null && _now().difference(since) >= state.backgroundGrace) {
          lock(LockReason.background);
        } else if (_now().difference(state.lastActivity) >= state.inactivityTimeout) {
          lock(LockReason.inactivity);
        } else {
          _restartIdleTimer();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  void _setObscured(bool v) {
    if (state.obscured != v) state = state.copyWith(obscured: v);
  }

  // ------------------------------------------------------------- lock/unlock

  void lock(LockReason reason) {
    if (!state.pinSet) return;
    _idleTimer?.cancel();
    state = state.copyWith(locked: true, reason: () => reason);
  }

  Future<PinVerifyResult> unlockWithPin(String pin) async {
    final r = await _pins.verify(pin);
    if (r.ok && ref.mounted) _unlock();
    return r;
  }

  Future<BiometricOutcome> unlockWithBiometrics() async {
    if (!state.biometricEnabled) return BiometricOutcome.notAvailable;
    // PIN lockout also blocks biometrics: otherwise they become a bypass.
    if (await _pins.lockedUntil() != null) return BiometricOutcome.lockedOut;
    final r = await confirmWithBiometrics('Unlock SecurePay');
    if (r == BiometricOutcome.success && ref.mounted) _unlock();
    return r;
  }

  /// Any OS biometric prompt (unlock, payment step-up) goes through here so
  /// the inactive/paused events it causes don't re-lock the app.
  Future<BiometricOutcome> confirmWithBiometrics(String reason) async {
    _systemPromptActive = true;
    try {
      return await _biometrics.authenticate(reason);
    } finally {
      _systemPromptActive = false;
    }
  }

  void _unlock() {
    state = state.copyWith(locked: false, reason: () => null);
    userActivity();
  }

  // ---------------------------------------------------------------- settings

  Future<void> setPin(String pin) async {
    await _pins.setPin(pin);
    state = state.copyWith(pinSet: true);
    userActivity();
  }

  Future<PinVerifyResult> changePin({required String current, required String next}) =>
      _pins.changePin(current: current, next: next);

  /// Enabling requires a successful scan, so a bystander can't turn on
  /// "their" biometrics through an unlocked phone.
  Future<BiometricOutcome> setBiometricEnabled(bool enable) async {
    if (enable) {
      if (!state.pinSet) return BiometricOutcome.notAvailable;
      final r = await confirmWithBiometrics('Enable biometric unlock');
      if (r != BiometricOutcome.success) return r;
    }
    await ref.read(keyValueStoreProvider).write(kBiometricEnabled, '$enable');
    state = state.copyWith(biometricEnabled: enable);
    return BiometricOutcome.success;
  }

  /// "Forgot PIN": treated as a NEW device. Everything in the vault goes
  /// (PIN, biometrics flag, device signing key, session keys), so the user
  /// must re-bind with OTP / re-KYC before transacting again. A PIN reset
  /// that kept the old device binding would be a lock-screen bypass.
  Future<void> resetCredentials() async {
    await ref.read(keyValueStoreProvider).deleteAll();
    _idleTimer?.cancel();
    state = state.copyWith(pinSet: false, biometricEnabled: false, locked: false, reason: () => null);
    ref.read(vaultGenerationProvider.notifier).bump();
  }
}
