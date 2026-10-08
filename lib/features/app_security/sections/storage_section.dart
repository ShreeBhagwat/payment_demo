import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/utils/bytes.dart';
import '../../../widgets/lab_widgets.dart';
import '../app_security_lab_controller.dart';

class StorageSection extends ConsumerWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(pinRecordProvider).value ?? const {};
    return SectionCard(
      title: '1 · What the lock stores (Secure Storage)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The PIN itself is never stored. Only a salted PBKDF2 hash, plus the failed-attempt '
            'counter, so killing and reopening the app does not reset the lockout.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (record.isEmpty)
            const Text('Nothing yet — set up a PIN below.', style: TextStyle(color: AppColors.muted))
          else
            for (final e in record.entries) OutputField(label: e.key, value: Bytes.ellipsize(e.value, keep: 12)),
        ],
      ),
    );
  }
}
