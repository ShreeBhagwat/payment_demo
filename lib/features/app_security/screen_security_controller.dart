import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/screen_protector.dart';

@immutable
class ScreenSecurityState {
  const ScreenSecurityState({this.globalOn = false, this.claims = 0, this.events = const []});

  final bool globalOn;
  final int claims; // SecureScreen pages currently visible
  final List<String> events; // newest first

  bool get active => globalOn || claims > 0;

  ScreenSecurityState copyWith({bool? globalOn, int? claims, List<String>? events}) => ScreenSecurityState(
        globalOn: globalOn ?? this.globalOn,
        claims: claims ?? this.claims,
        events: events ?? this.events,
      );
}

/// App-wide capture protection. Reference-counted: the global toggle and
/// any number of [SecureScreen] pages (PIN entry, card details) can each
/// request protection; it's on while anyone wants it.
final screenSecurityProvider = NotifierProvider<ScreenSecurityController, ScreenSecurityState>(
  ScreenSecurityController.new,
);

class ScreenSecurityController extends Notifier<ScreenSecurityState> {
  ScreenProtector get _protector => ref.read(screenProtectorProvider);

  @override
  ScreenSecurityState build() {
    final sub = _protector.events().listen(_onEvent);
    ref.onDispose(sub.cancel);
    return const ScreenSecurityState();
  }

  Future<void> setGlobal(bool on) => _apply(state.copyWith(globalOn: on));

  Future<void> claim() => _apply(state.copyWith(claims: state.claims + 1));

  Future<void> release() => _apply(state.copyWith(claims: state.claims > 0 ? state.claims - 1 : 0));

  Future<void> _apply(ScreenSecurityState next) async {
    // SecureScreen releases from a microtask after dispose; on app teardown
    // or hot restart the provider may already be gone.
    if (!ref.mounted) return;
    final changed = next.active != state.active;
    state = next;
    if (changed) await _protector.setProtected(next.active);
  }

  /// Detection, e.g. to warn the user or log to fraud monitoring when an
  /// OTP screen is captured.
  void _onEvent(CaptureEvent e) {
    final stamp = ref.read(clockProvider)().toIso8601String().substring(11, 19);
    final label = switch (e) {
      CaptureEvent.screenshot => 'Screenshot taken',
      CaptureEvent.recording => 'Screen recording active',
    };
    state = state.copyWith(events: ['$stamp  $label', ...state.events]);
  }
}
