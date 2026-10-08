import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/payment/models.dart';
import '../../../core/payment/trace.dart';
import '../../../widgets/lab_widgets.dart';

/// Small caption separating the client and server lanes of a trace.
class TraceLane extends StatelessWidget {
  const TraceLane({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: const TextStyle(fontSize: 11.5, letterSpacing: 1.1, color: AppColors.muted)),
      );
}

/// One client-side step, fading/sliding in when first shown.
class TraceRow extends StatelessWidget {
  const TraceRow({super.key, required this.step, required this.color});

  final TraceStep step;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = step.danger ? AppColors.red : color;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.code,
          border: Border(left: BorderSide(color: c, width: 3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: TextStyle(fontWeight: FontWeight.w600, color: step.danger ? AppColors.red : null),
            ),
            const SizedBox(height: 2),
            Text(step.value, style: mono.copyWith(color: AppColors.muted, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

/// One server-side security check, popping in with its pass/fail status.
class CheckRow extends StatelessWidget {
  const CheckRow({super.key, required this.check});

  final SecurityCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (check.status) {
      CheckStatus.passed => (Icons.check_circle_rounded, AppColors.teal),
      CheckStatus.failed => (Icons.cancel_rounded, AppColors.red),
      CheckStatus.skipped => (Icons.remove_circle_outline_rounded, AppColors.muted),
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, alignment: Alignment.centerLeft, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    check.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: check.status == CheckStatus.skipped ? AppColors.muted : null,
                    ),
                  ),
                  Text(check.detail, style: TextStyle(fontSize: 12, color: color.withValues(alpha: .85))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
