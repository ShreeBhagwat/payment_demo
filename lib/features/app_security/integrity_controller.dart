import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/security/device_integrity.dart';

@immutable
class IntegrityState {
  const IntegrityState({this.report, this.checking = false, this.policy = IntegrityPolicy.warn});

  final IntegrityReport? report;
  final bool checking;
  final IntegrityPolicy policy;

  /// Null when payments are allowed; otherwise the reason to show.
  String? get paymentBlockReason => report?.blockReason(policy);

  IntegrityState copyWith({IntegrityReport? report, bool? checking, IntegrityPolicy? policy}) =>
      IntegrityState(report: report ?? this.report, checking: checking ?? this.checking, policy: policy ?? this.policy);
}

/// App-wide (not autoDispose): the scan result and policy configured in the
/// App Security lab also gate payments in the Payment lab.
final integrityProvider = NotifierProvider<IntegrityController, IntegrityState>(IntegrityController.new);

class IntegrityController extends Notifier<IntegrityState> {
  @override
  IntegrityState build() => const IntegrityState();

  Future<void> scan() async {
    state = state.copyWith(checking: true);
    final report = await ref.read(deviceIntegrityServiceProvider).check();
    if (ref.mounted) state = state.copyWith(report: report, checking: false);
  }

  void setPolicy(IntegrityPolicy policy) => state = state.copyWith(policy: policy);
}
