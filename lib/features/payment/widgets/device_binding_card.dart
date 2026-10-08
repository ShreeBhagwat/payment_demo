import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../payment_controller.dart';
import 'trace_rows.dart';

/// Step 1: bind the device (Ed25519 key + X25519 session) or unbind it.
class DeviceBindingCard extends ConsumerWidget {
  const DeviceBindingCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarded = ref.watch(paymentLabProvider.select((s) => s.onboarded));
    final trace = ref.watch(paymentLabProvider.select((s) => s.onboardTrace));
    final busy = ref.watch(paymentLabProvider.select((s) => s.busy));
    final controller = ref.read(paymentLabProvider.notifier);

    return SectionCard(
      title: 'Step 1 · Device binding',
      trailing: onboarded == true ? TextButton(onPressed: controller.unbind, child: const Text('Unbind')) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onboarded == null)
            const Center(child: CircularProgressIndicator())
          else if (!onboarded) ...[
            const Text(
              'Generate an Ed25519 device key, register its public half with the bank, '
              'then run an X25519 handshake to derive session keys. Everything is saved in Secure Storage.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            BusyButton(
              label: 'Bind this device',
              icon: Icons.phonelink_lock_rounded,
              busy: busy,
              onPressed: controller.onboard,
            ),
          ] else ...[
            const StatusBanner(ok: true, text: 'Device bound — keys in Secure Storage'),
            if (trace.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final s in trace) TraceRow(step: s, color: AppColors.teal),
            ],
          ],
        ],
      ),
    );
  }
}
