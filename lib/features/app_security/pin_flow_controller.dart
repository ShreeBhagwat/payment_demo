import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/pin_service.dart';
import '../app_lock/app_lock_controller.dart';

enum PinFlowMode { setup, change }

enum PinFlowStep { current, enterNew, confirm }

@immutable
class PinFlowState {
  const PinFlowState({
    required this.step,
    this.current = '',
    this.next = '',
    this.error,
    this.busy = false,
    this.rejections = 0,
    this.done = false,
  });

  final PinFlowStep step;
  final String current; // verified current PIN (change mode)
  final String next; // new PIN awaiting confirmation
  final String? error;
  final bool busy;
  final int rejections; // bumped on every rejection so the pad can shake
  final bool done;

  PinFlowState copyWith({
    PinFlowStep? step,
    String? current,
    String? next,
    String? Function()? error,
    bool? busy,
    int? rejections,
    bool? done,
  }) =>
      PinFlowState(
        step: step ?? this.step,
        current: current ?? this.current,
        next: next ?? this.next,
        error: error != null ? error() : this.error,
        busy: busy ?? this.busy,
        rejections: rejections ?? this.rejections,
        done: done ?? this.done,
      );
}

final pinFlowProvider = NotifierProvider.autoDispose.family<PinFlowController, PinFlowState, PinFlowMode>(
  PinFlowController.new,
);

/// Set-up and change-PIN flow:
///   change: current PIN → new PIN (strength rules) → confirm → save
///   setup:                 new PIN (strength rules) → confirm → save
class PinFlowController extends Notifier<PinFlowState> {
  PinFlowController(this.mode);

  final PinFlowMode mode;

  PinService get _pins => ref.read(pinServiceProvider);

  @override
  PinFlowState build() => PinFlowState(step: mode == PinFlowMode.change ? PinFlowStep.current : PinFlowStep.enterNew);

  int get stepCount => mode == PinFlowMode.setup ? 2 : 3;
  int get stepIndex => state.step.index - (mode == PinFlowMode.setup ? 1 : 0);

  String get title => switch (state.step) {
        PinFlowStep.current => 'Enter current PIN',
        PinFlowStep.enterNew => mode == PinFlowMode.setup ? 'Create a 6-digit PIN' : 'Enter new PIN',
        PinFlowStep.confirm => 'Confirm new PIN',
      };

  Future<void> submit(String pin) async {
    switch (state.step) {
      case PinFlowStep.current:
        // Verify immediately so a wrong current PIN counts toward lockout
        // here, rather than after the user types a new PIN twice.
        state = state.copyWith(busy: true);
        final r = await _pins.verify(pin);
        if (!ref.mounted) return;
        if (r.ok) {
          state = state.copyWith(busy: false, current: pin, step: PinFlowStep.enterNew, error: () => null);
        } else {
          _reject(
            r.status == PinStatus.lockedOut
                ? 'Too many attempts. Locked until ${r.lockedUntil!.toIso8601String().substring(11, 16)}'
                : 'Incorrect PIN · ${r.attemptsLeft} attempts left',
          );
        }
      case PinFlowStep.enterNew:
        final weak =
            _pins.validateNewPin(pin) ?? (pin == state.current ? 'New PIN must differ from the current PIN' : null);
        if (weak != null) return _reject(weak);
        state = state.copyWith(next: pin, step: PinFlowStep.confirm, error: () => null);
      case PinFlowStep.confirm:
        if (pin != state.next) {
          _reject('PINs did not match. Start again.');
          state = state.copyWith(next: '', step: PinFlowStep.enterNew);
          return;
        }
        state = state.copyWith(busy: true);
        final lock = ref.read(appLockProvider.notifier);
        if (mode == PinFlowMode.setup) {
          await lock.setPin(pin);
        } else {
          final r = await lock.changePin(current: state.current, next: pin);
          if (!ref.mounted) return;
          if (!r.ok) return _reject('Could not change PIN (${r.status.name})');
        }
        // Production: also notify the user out-of-band (SMS/email:
        // "Your PIN was changed. Not you? Call us.") and log the event.
        if (ref.mounted) state = state.copyWith(busy: false, done: true);
    }
  }

  void _reject(String message) =>
      state = state.copyWith(error: () => message, busy: false, rejections: state.rejections + 1);
}
