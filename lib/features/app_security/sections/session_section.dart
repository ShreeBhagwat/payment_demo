import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/lab_module.dart';
import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../../app_lock/app_lock_controller.dart';

class SessionSection extends ConsumerWidget {
  const SessionSection({super.key});

  static String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockProvider);
    final controller = ref.read(appLockProvider.notifier);
    final now = ref.watch(secondTickerProvider).value ?? ref.read(clockProvider)();
    final left = lock.timeUntilAutoLock(now);
    final total = lock.inactivityTimeout.inMilliseconds;
    final fraction = total == 0 ? 0.0 : left.inMilliseconds / total;

    return SectionCard(
      title: '4 · App lock & session timeout',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: lock.pinSet ? fraction : 0,
                      strokeWidth: 6,
                      backgroundColor: AppColors.surface,
                      color: fraction < .25 ? AppColors.red : LabModule.appSecurity.color,
                    ),
                    Center(
                      child: Text(
                        lock.pinSet ? _fmt(left) : '--:--',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  lock.pinSet
                      ? 'Auto-lock countdown. Any touch resets it. Leave the phone alone to watch it lock.'
                      : 'Set up a PIN to activate app lock and session timeout.',
                  style: const TextStyle(color: Colors.white70, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _Label('Inactivity timeout'),
          SegmentedButton<Duration>(
            segments: const [
              ButtonSegment(value: Duration(seconds: 15), label: Text('15 s')),
              ButtonSegment(value: Duration(minutes: 1), label: Text('1 min')),
              ButtonSegment(value: Duration(minutes: 2), label: Text('2 min')),
              ButtonSegment(value: Duration(minutes: 5), label: Text('5 min')),
            ],
            selected: {lock.inactivityTimeout},
            onSelectionChanged: (s) => controller.setInactivityTimeout(s.first),
          ),
          const SizedBox(height: 14),
          const _Label('Lock after leaving the app for'),
          SegmentedButton<Duration>(
            segments: const [
              ButtonSegment(value: Duration.zero, label: Text('Immediately')),
              ButtonSegment(value: Duration(seconds: 10), label: Text('10 s')),
              ButtonSegment(value: Duration(minutes: 1), label: Text('1 min')),
            ],
            selected: {lock.backgroundGrace},
            onSelectionChanged: (s) => controller.setBackgroundGrace(s.first),
          ),
          const SizedBox(height: 12),
          const ConceptBullets(
            points: [
              'Client timer = UX. The server must ALSO expire tokens (short access token, refresh rotation)',
              "Lock gate sits above the Navigator, so deep links can't skip it",
              'App-switcher shows a shield, not your balance',
            ],
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
      );
}
