import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/payment/models.dart';
import '../../../widgets/lab_widgets.dart';
import '../payment_controller.dart';

/// Step 3: pick a legitimate payment or one of the attack scenarios.
class RedTeamCard extends ConsumerWidget {
  const RedTeamCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(paymentLabProvider.select((s) => s.onboarded));
    final order = ref.watch(paymentLabProvider.select((s) => s.order));
    if (onboarded != true || order == null) return const SizedBox.shrink();
    final tamper = ref.watch(labTamperProvider);
    final chosen = ref.watch(paymentLabProvider.select((s) => s.attack));
    final attack = tamper?.attack ?? chosen;
    final busy = ref.watch(paymentLabProvider.select((s) => s.busy));
    final controller = ref.read(paymentLabProvider.notifier);
    final legit = attack == AttackMode.none;

    Future<void> pay() async {
      final message = await controller.pay();
      if (message != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    }

    return SectionCard(
      title: 'Step 3 · Pay — or attack',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tamper != null) ...[
            StatusBanner(
              ok: false,
              text: 'Tamper is active in Module ${tamper.module.number} (${tamper.module.shortTitle}) — '
                  'this payment will be sent tampered.',
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : tamper.restore,
                child: Text('Restore original in ${tamper.module.shortTitle} lab'),
              ),
            ),
            const SizedBox(height: 6),
          ],
          OptionChips<AttackMode>(
            options: AttackMode.values,
            selected: attack,
            labelOf: (a) => a.label,
            isDanger: (a) => a != AttackMode.none,
            enabled: !busy && tamper == null,
            onSelected: controller.setAttack,
          ),
          const SizedBox(height: 10),
          Text(
            attack.description,
            style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 14),
          BusyButton(
            label: legit ? 'Pay ${order.displayAmount} securely' : 'Launch attack',
            icon: legit ? Icons.lock_rounded : Icons.bug_report_rounded,
            danger: !legit,
            onPressed: busy ? null : pay,
          ),
        ],
      ),
    );
  }
}
