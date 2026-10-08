import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/lab_widgets.dart';
import '../payment_controller.dart';
import 'trace_rows.dart';

/// Client trace, then server checks, revealed step by step by the controller.
class LiveTraceCard extends ConsumerWidget {
  const LiveTraceCard({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(paymentLabProvider.select((s) => s.attempt));
    if (a == null) return const SizedBox.shrink();
    final revealed = ref.watch(paymentLabProvider.select((s) => s.revealed));
    final done = ref.watch(paymentLabProvider.select((s) => s.revealDone));
    final traceShown = revealed.clamp(0, a.trace.length);
    final checksShown = (revealed - a.trace.length).clamp(0, a.result.checks.length);

    return SectionCard(
      title: 'Live trace',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TraceLane(label: '📱  CLIENT (Flutter app)'),
          for (final s in a.trace.take(traceShown)) TraceRow(step: s, color: color),
          if (checksShown > 0) ...[
            const SizedBox(height: 10),
            const TraceLane(label: '🏦  BANK SERVER (simulated)'),
            for (final c in a.result.checks.take(checksShown)) CheckRow(check: c),
          ],
          if (done) ...[
            const SizedBox(height: 12),
            StatusBanner(
              ok: a.result.success,
              text: a.result.success ? 'Payment captured · ${a.result.paymentId}' : 'Blocked: ${a.result.message}',
            ),
            if (a.result.success) ...[
              const SizedBox(height: 10),
              OutputField(label: 'Gateway signature  HMAC(order_id|payment_id)', value: a.result.gatewaySignature!),
            ],
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Raw HTTP request', style: TextStyle(fontSize: 14)),
              children: [
                OutputField(
                  label: '${a.request.method} ${a.request.path}',
                  value: a.request.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                ),
                OutputField(label: 'Body', value: a.request.body),
              ],
            ),
          ] else
            const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
