import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../screen_security_controller.dart';

class ScreenshotSection extends ConsumerWidget {
  const ScreenshotSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sc = ref.watch(screenSecurityProvider);
    return SectionCard(
      title: '5 · Screenshot & recording prevention',
      trailing: Pill(sc.active ? 'Protected' : 'Off', color: sc.active ? AppColors.teal : AppColors.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Block capture app-wide'),
            subtitle: const Text('PIN screens are always protected via SecureScreen'),
            value: sc.globalOn,
            onChanged: ref.read(screenSecurityProvider.notifier).setGlobal,
          ),
          const ConceptBullets(
            points: [
              'Android: FLAG_SECURE → black screenshots, recordings & thumbnails',
              'iOS: no official API; content rendered in a secure layer + capture detection',
              'Try it: take a screenshot now, then turn protection on and try again',
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'DETECTED CAPTURE EVENTS',
            style: TextStyle(fontSize: 11, letterSpacing: 1, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          if (sc.events.isEmpty)
            const Text('None yet', style: TextStyle(color: AppColors.muted))
          else
            for (final e in sc.events.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('⚠ $e', style: mono.copyWith(color: AppColors.gold)),
              ),
        ],
      ),
    );
  }
}
