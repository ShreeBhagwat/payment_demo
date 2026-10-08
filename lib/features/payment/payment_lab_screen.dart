import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../widgets/lab_widgets.dart';
import 'payment_controller.dart';
import 'widgets/checkout_card.dart';
import 'widgets/device_binding_card.dart';
import 'widgets/live_trace_card.dart';
import 'widgets/red_team_card.dart';

const _module = LabModule.payment;

/// Composes the payment lab from independent section widgets; each one
/// watches only the slice of [paymentLabProvider] it renders. The screen
/// itself only decides which sections exist yet.
class PaymentLabScreen extends ConsumerWidget {
  const PaymentLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bound = ref.watch(paymentLabProvider.select((s) => s.onboarded == true));
    final hasOrder = ref.watch(paymentLabProvider.select((s) => s.order != null));
    final hasAttempt = ref.watch(paymentLabProvider.select((s) => s.attempt != null));
    return LabScaffold(
      module: _module,
      children: [
        const DeviceBindingCard(),
        if (bound) const CheckoutCard(),
        if (bound && hasOrder) const RedTeamCard(),
        if (hasAttempt) LiveTraceCard(color: _module.color),
        const _ArchitectureCard(),
        const CodeSnippet(
          title: 'Plugging in a real gateway (Razorpay)',
          code: r'''
// 1. App asks YOUR backend to create an order (amount decided server-side)
final order = await api.createOrder(cartId);       // order_xxx

// 2. Open the gateway checkout with the public key only
_razorpay.open({
  'key': 'rzp_live_PUBLIC_KEY',                     // never the secret
  'order_id': order.id,
  'amount': order.amountPaise,
  'prefill': {'contact': user.phone},
});

// 3. On success, send the 3 values to YOUR backend
_razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) =>
    api.confirm(r.orderId, r.paymentId, r.signature));

// 4. Backend (never the app) verifies:
//    HMAC_SHA256(order_id + "|" + payment_id, key_secret) == signature
//    and also listens to the signed webhook before fulfilling.''',
        ),
      ],
    );
  }
}

class _ArchitectureCard extends StatelessWidget {
  const _ArchitectureCard();

  @override
  Widget build(BuildContext context) {
    return const ConceptCard(
      title: 'Why each layer exists',
      points: [
        ('Body hash + HMAC', '→ stops MITM edits, even if TLS is intercepted by a malicious proxy/CA.'),
        ('Timestamp + nonce', '→ stops delayed and replayed requests.'),
        ('AES-GCM + AAD', '→ payload unreadable in logs/proxies, and bound to one order.'),
        ('Ed25519 device signature', '→ stolen session keys are not enough; non-repudiation for disputes.'),
        ('Server-side order rules', '→ crypto proves who sent it, not that the amount is right.'),
        ('Gateway signature', '→ the merchant backend never trusts the app\'s "success" callback.'),
      ],
    );
  }
}
