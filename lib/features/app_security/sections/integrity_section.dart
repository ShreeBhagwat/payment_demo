import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/security/device_integrity.dart';
import '../../../widgets/lab_widgets.dart';
import '../integrity_controller.dart';

class IntegritySection extends ConsumerWidget {
  const IntegritySection({super.key});

  static Color _riskColor(RiskLevel? r) => switch (r) {
        RiskLevel.critical => AppColors.red,
        RiskLevel.warn => AppColors.gold,
        _ => AppColors.teal,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(integrityProvider);
    final controller = ref.read(integrityProvider.notifier);
    final r = s.report;
    return SectionCard(
      title: '6 · Jailbreak & root detection',
      trailing: r == null ? null : Pill(r.risk.name.toUpperCase(), color: _riskColor(r.risk)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BusyButton(
            label: r == null ? 'Scan this device' : 'Scan again',
            icon: Icons.radar_rounded,
            busy: s.checking,
            onPressed: controller.scan,
          ),
          if (r != null) ...[const SizedBox(height: 12), for (final c in r.checks) _CheckRow(check: c)],
          const SizedBox(height: 12),
          const Text(
            'Response policy (applies to the Payment lab)',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          SegmentedButton<IntegrityPolicy>(
            segments: [for (final p in IntegrityPolicy.values) ButtonSegment(value: p, label: Text(p.label))],
            selected: {s.policy},
            onSelectionChanged: (sel) => controller.setPolicy(sel.first),
          ),
          const SizedBox(height: 6),
          Text(s.policy.description, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 10),
          const ConceptBullets(
            points: [
              'Client checks can be hooked (Frida, Magisk DenyList). They are one signal, not proof',
              'Back them with server-verified Play Integrity / App Attest tokens',
              'Commercial RASP (e.g. freeRASP, Promon) adds hook, debugger & repackaging detection',
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final IntegrityCheck check;

  @override
  Widget build(BuildContext context) {
    final color =
        !check.flagged ? AppColors.teal : (check.level == RiskLevel.critical ? AppColors.red : AppColors.gold);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(check.flagged ? Icons.warning_rounded : Icons.check_circle_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(check.why, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
