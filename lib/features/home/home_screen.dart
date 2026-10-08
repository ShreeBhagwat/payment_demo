import 'package:flutter/material.dart';

import '../../app/lab_module.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../widgets/lab_widgets.dart';
import 'defence_in_depth.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _Hero(),
            const SizedBox(height: 22),
            const Text('TRAINING MODULES', style: TextStyle(fontSize: 12, letterSpacing: 1.4, color: AppColors.muted)),
            const SizedBox(height: 10),
            for (final m in LabModule.values) ...[_ModuleTile(module: m), const SizedBox(height: 12)],
            const SizedBox(height: 8),
            const DefenceInDepth(),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF1C3A7A), Color(0xFF0B1B3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.gold, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('SecurePay Academy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Hands-on Flutter security for banking apps. Every lab runs real '
            'cryptography on-device — no mocks, no network required.',
            style: TextStyle(color: Colors.white70, height: 1.45),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill('OWASP MASVS aligned', color: AppColors.gold),
              Pill('RBI digital payment guidelines', color: AppColors.teal),
              Pill('PCI DSS mindset', color: Color(0xFFB57BFF)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});

  final LabModule module;

  @override
  Widget build(BuildContext context) {
    final color = module.color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openModule(context, module),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: .18), borderRadius: BorderRadius.circular(16)),
                child: Icon(module.icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MODULE ${module.number}', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: color)),
                    const SizedBox(height: 2),
                    Text(module.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(module.tagline, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final t in module.tags) Pill(t, color: color)]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
