import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/providers.dart';
import '../../core/payment/models.dart';
import '../../core/payment/secure_payment_client.dart';
import '../../core/security/biometric_service.dart';
import '../app_lock/app_lock_controller.dart';
import '../app_security/integrity_controller.dart';
import '../hmac/hmac_controller.dart';
import '../signature/signature_controller.dart';

@immutable
class PaymentLabState {
  const PaymentLabState({
    this.onboarded,
    this.onboardTrace = const [],
    this.amountText = '25000',
    this.order,
    this.attack = AttackMode.none,
    this.busy = false,
    this.attempt,
    this.revealed = 0,
  });

  final bool? onboarded; // null while loading
  final List<TraceStep> onboardTrace;
  final String amountText;
  final PaymentOrder? order;
  final AttackMode attack;
  final bool busy;
  final PaymentAttempt? attempt;
  final int revealed; // trace + checks revealed so far (for the animation)

  /// Total reveal steps for [attempt]: client trace, server checks, verdict.
  int get revealTotal => attempt == null ? 0 : attempt!.trace.length + attempt!.result.checks.length + 1;

  bool get revealDone => attempt != null && revealed >= revealTotal;

  PaymentLabState copyWith({
    bool? Function()? onboarded,
    List<TraceStep>? onboardTrace,
    String? amountText,
    PaymentOrder? Function()? order,
    AttackMode? attack,
    bool? busy,
    PaymentAttempt? Function()? attempt,
    int? revealed,
  }) =>
      PaymentLabState(
        onboarded: onboarded != null ? onboarded() : this.onboarded,
        onboardTrace: onboardTrace ?? this.onboardTrace,
        amountText: amountText ?? this.amountText,
        order: order != null ? order() : this.order,
        attack: attack ?? this.attack,
        busy: busy ?? this.busy,
        attempt: attempt != null ? attempt() : this.attempt,
        revealed: revealed ?? this.revealed,
      );
}

/// A tamper left switched on in an earlier lab, carried into the payment.
@immutable
class LabTamper {
  const LabTamper(this.module, this.attack, this.restore);

  final LabModule module;
  final AttackMode attack;
  final VoidCallback restore;
}

/// The active cross-lab tamper, if any (HMAC lab first, then Signatures).
final labTamperProvider = Provider.autoDispose<LabTamper?>((ref) {
  if (!ref.watch(hmacLabProvider.select((s) => s.valid))) {
    return LabTamper(LabModule.hmac, AttackMode.hmacTamper, ref.read(hmacLabProvider.notifier).restore);
  }
  final (amount, otherKey) = ref.watch(signatureLabProvider.select((s) => (s.tamperAmount, s.otherKey)));
  final sig = ref.read(signatureLabProvider.notifier);
  if (amount) return LabTamper(LabModule.signature, AttackMode.signatureTamper, () => sig.setTamperAmount(false));
  if (otherKey) return LabTamper(LabModule.signature, AttackMode.forgedDevice, () => sig.setOtherKey(false));
  return null;
});

final paymentLabProvider = NotifierProvider.autoDispose<PaymentLabController, PaymentLabState>(
  PaymentLabController.new,
);

class PaymentLabController extends Notifier<PaymentLabState> {
  static const stepDelay = Duration(milliseconds: 260);
  static const stepUpThresholdPaise = 10000 * 100; // ₹10,000
  static const _payee = 'Acme Electronics Pvt Ltd';

  Timer? _revealTimer;

  SecurePaymentClient get _client => ref.read(paymentClientProvider);

  @override
  PaymentLabState build() {
    // A wholesale vault wipe ("Forgot PIN") unbinds the device: start over.
    ref.watch(vaultGenerationProvider);
    ref.onDispose(() => _revealTimer?.cancel());
    Future.microtask(_loadOnboarded);
    return const PaymentLabState();
  }

  Future<void> _loadOnboarded() async {
    bool bound;
    try {
      bound = await _client.isOnboarded;
    } catch (_) {
      bound = false;
    }
    if (ref.mounted) state = state.copyWith(onboarded: () => bound);
  }

  Future<void> onboard() async {
    state = state.copyWith(busy: true);
    final trace = await _client.onboard();
    if (!ref.mounted) return;
    state = state.copyWith(onboardTrace: trace, onboarded: () => true, busy: false);
  }

  Future<void> unbind() async {
    _revealTimer?.cancel();
    await _client.reset();
    if (!ref.mounted) return;
    state = state.copyWith(
      onboarded: () => false,
      onboardTrace: const [],
      attempt: () => null,
      order: () => null,
      busy: false,
    );
  }

  void setAmount(String text) => state = state.copyWith(amountText: text);

  void setAttack(AttackMode attack) => state = state.copyWith(attack: attack);

  /// A tamper left active in another lab overrides the red-team choice.
  AttackMode get effectiveAttack => ref.read(labTamperProvider)?.attack ?? state.attack;

  void createOrder() {
    final rupees = int.tryParse(state.amountText.replaceAll(',', '')) ?? 0;
    if (rupees <= 0) return;
    state = state.copyWith(order: () => _newOrder(rupees * 100), attempt: () => null);
  }

  /// Runs one payment (or attack). Returns a user-facing message when the
  /// payment is refused before reaching the bank, else null.
  Future<String?> pay() async {
    final order = state.order;
    if (order == null) return null;

    // Device-integrity policy (configured in the App Security lab).
    final blocked = ref.read(integrityProvider).paymentBlockReason;
    if (blocked != null) return blocked;

    // Step-up auth: high-value payments need a fresh biometric scan even
    // though the app is already unlocked.
    if (order.amountPaise >= stepUpThresholdPaise && ref.read(appLockProvider).biometricEnabled) {
      final r = await ref
          .read(appLockProvider.notifier)
          .confirmWithBiometrics('Approve ${order.displayAmount} to ${order.payee}');
      if (r != BiometricOutcome.success) return 'Payment not approved: ${r.message}';
    }
    if (!ref.mounted) return null;

    _revealTimer?.cancel();
    state = state.copyWith(busy: true, attempt: () => null, revealed: 0);
    final attempt = await _client.pay(order, attack: effectiveAttack);
    if (!ref.mounted) return null;

    // Each attempt consumes the order (a replay's first send pays it), so
    // issue a fresh one for the next run, as a real checkout would.
    state = state.copyWith(attempt: () => attempt, order: () => _newOrder(order.amountPaise));
    _revealTimer = Timer.periodic(stepDelay, (t) {
      if (!ref.mounted) return t.cancel();
      final revealed = state.revealed + 1;
      final done = revealed >= state.revealTotal;
      if (done) t.cancel();
      state = state.copyWith(revealed: revealed, busy: done ? false : null);
    });
    return null;
  }

  PaymentOrder _newOrder(int amountPaise) =>
      ref.read(merchantApiProvider).createOrder(amountPaise: amountPaise, payee: _payee);
}
