import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/biometric_service.dart';
import '../app_lock/app_lock_controller.dart';

@immutable
class AppSecurityLabState {
  const AppSecurityLabState({this.shuffleKeypad = true, this.biometricMessage, this.biometricOk = false});

  final bool shuffleKeypad;
  final String? biometricMessage;
  final bool biometricOk;

  AppSecurityLabState copyWith({bool? shuffleKeypad, String? biometricMessage, bool? biometricOk}) =>
      AppSecurityLabState(
        shuffleKeypad: shuffleKeypad ?? this.shuffleKeypad,
        biometricMessage: biometricMessage ?? this.biometricMessage,
        biometricOk: biometricOk ?? this.biometricOk,
      );
}

/// Lab-only UI state (keypad shuffle, last biometric result). The real
/// security settings live in [appLockProvider].
final appSecurityLabProvider = NotifierProvider.autoDispose<AppSecurityLabController, AppSecurityLabState>(
  AppSecurityLabController.new,
);

class AppSecurityLabController extends Notifier<AppSecurityLabState> {
  AppLockController get _lock => ref.read(appLockProvider.notifier);

  @override
  AppSecurityLabState build() => const AppSecurityLabState();

  void setShuffle(bool v) => state = state.copyWith(shuffleKeypad: v);

  Future<void> setBiometricUnlock(bool enable) async {
    final r = await _lock.setBiometricEnabled(enable);
    if (!ref.mounted) return;
    final ok = r == BiometricOutcome.success;
    state = state.copyWith(
      biometricOk: ok,
      biometricMessage: !enable ? 'Biometric unlock disabled' : (ok ? 'Biometric unlock enabled' : r.message),
    );
  }

  Future<void> testBiometric() async {
    final r = await _lock.confirmWithBiometrics('Confirm it is you');
    if (!ref.mounted) return;
    state = state.copyWith(biometricOk: r == BiometricOutcome.success, biometricMessage: r.message);
  }
}

/// What the lock stores in Secure Storage (PIN hash, salt, counters,
/// settings). Re-reads whenever lock state or the vault changes.
final pinRecordProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  ref
    ..watch(appLockProvider)
    ..watch(vaultGenerationProvider);
  final all = await ref.read(keyValueStoreProvider).readAll();
  final entries = all.entries.where((e) => e.key.startsWith('pin.') || e.key.startsWith('settings.')).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return Map.fromEntries(entries);
});
