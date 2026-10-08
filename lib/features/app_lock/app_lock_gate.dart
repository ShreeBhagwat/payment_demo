import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/security/biometric_service.dart';
import '../../core/security/pin_service.dart';
import '../../widgets/pin_pad.dart';
import 'app_lock_controller.dart';

/// Sits above the Navigator (MaterialApp.builder) so NO route — including
/// deep links and dialogs — can render without passing the lock.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(appLockProvider.notifier).userActivity(),
      child: Stack(
        children: [
          // Locked content is neither readable by accessibility services nor
          // animating behind the lock screen.
          ExcludeSemantics(
            excluding: lock.guarded,
            child: TickerMode(enabled: !lock.guarded, child: child),
          ),
          if (lock.guarded) Positioned.fill(child: lock.ready ? const LockScreen() : const PrivacyShield()),
          if (lock.obscured && !lock.guarded) const Positioned.fill(child: PrivacyShield()),
        ],
      ),
    );
  }
}

/// Shown in the OS app switcher so balances/OTPs aren't in the snapshot.
class PrivacyShield extends StatelessWidget {
  const PrivacyShield({super.key});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: const ColoredBox(
        color: Color(0xEE0B1B3A),
        child: Center(child: Icon(Icons.shield_rounded, size: 72, color: AppColors.gold)),
      ),
    );
  }
}

// ------------------------------------------------------------- lock screen

@immutable
class LockScreenState {
  const LockScreenState({this.message, this.lockedUntil, this.busy = false, this.rejections = 0});

  final String? message;
  final DateTime? lockedUntil;
  final bool busy;
  final int rejections; // bumps on every wrong PIN so the pad can shake

  LockScreenState copyWith({
    String? Function()? message,
    DateTime? Function()? lockedUntil,
    bool? busy,
    int? rejections,
  }) =>
      LockScreenState(
        message: message != null ? message() : this.message,
        lockedUntil: lockedUntil != null ? lockedUntil() : this.lockedUntil,
        busy: busy ?? this.busy,
        rejections: rejections ?? this.rejections,
      );
}

final lockScreenProvider = NotifierProvider.autoDispose<LockScreenController, LockScreenState>(
  LockScreenController.new,
);

class LockScreenController extends Notifier<LockScreenState> {
  AppLockController get _lock => ref.read(appLockProvider.notifier);

  @override
  LockScreenState build() {
    Future.microtask(_refreshLockout);
    return const LockScreenState();
  }

  Future<void> _refreshLockout() async {
    final until = await ref.read(pinServiceProvider).lockedUntil();
    if (ref.mounted) state = state.copyWith(lockedUntil: () => until);
  }

  /// True while a PIN lockout is still running at [now].
  bool isLockedOut(DateTime now) => state.lockedUntil?.isAfter(now) ?? false;

  Future<void> submit(String pin) async {
    state = state.copyWith(busy: true);
    final r = await _lock.unlockWithPin(pin);
    if (!ref.mounted) return;
    state = switch (r.status) {
      PinStatus.ok || PinStatus.notSet => state.copyWith(busy: false),
      PinStatus.wrong => state.copyWith(
          busy: false,
          rejections: state.rejections + 1,
          message: () => 'Incorrect PIN · ${r.attemptsLeft} attempt${r.attemptsLeft == 1 ? '' : 's'} left',
        ),
      PinStatus.lockedOut => state.copyWith(
          busy: false,
          rejections: state.rejections + 1,
          message: () => 'Too many attempts',
          lockedUntil: () => r.lockedUntil,
        ),
    };
  }

  Future<void> biometric() async {
    final r = await _lock.unlockWithBiometrics();
    if (!ref.mounted || r == BiometricOutcome.success || r == BiometricOutcome.canceled) return;
    state = state.copyWith(message: () => r.message);
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pad = GlobalKey<PinPadState>();

  @override
  void initState() {
    super.initState();
    // Auto-prompt biometrics, like most banking apps.
    if (ref.read(appLockProvider).biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(lockScreenProvider.notifier).biometric());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrong PIN → shake & clear the pad (PinPad owns its own animation).
    ref.listen(lockScreenProvider.select((s) => s.rejections), (_, _) => _pad.currentState?.reject());

    final lock = ref.watch(appLockProvider);
    final screen = ref.watch(lockScreenProvider);
    final controller = ref.read(lockScreenProvider.notifier);
    final now = ref.watch(secondTickerProvider).value ?? ref.read(clockProvider)();
    final lockedOut = controller.isLockedOut(now);
    final secsLeft = lockedOut ? screen.lockedUntil!.difference(now).inSeconds + 1 : 0;

    return Material(
      color: AppColors.navy,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: .15), shape: BoxShape.circle),
                    child: const Icon(Icons.lock_rounded, color: AppColors.gold, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text('Enter your PIN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(lock.reason?.label ?? '', style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 22,
                    child: Text(
                      lockedOut ? 'Locked — try again in ${secsLeft}s' : (screen.message ?? ''),
                      style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 18),
                  PinPad(
                    key: _pad,
                    length: ref.read(pinServiceProvider).pinLength,
                    enabled: !lockedOut && !screen.busy,
                    onCompleted: controller.submit,
                    extraAction: lock.biometricEnabled
                        ? IconButton(
                            iconSize: 34,
                            color: AppColors.gold,
                            onPressed: lockedOut ? null : controller.biometric,
                            icon: const Icon(Icons.fingerprint_rounded),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: ref.read(appLockProvider.notifier).resetCredentials,
                    child: const Text('Forgot PIN? Reset device (wipes all keys)'),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
