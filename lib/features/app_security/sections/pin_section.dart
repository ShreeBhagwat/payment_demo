import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../../app_lock/app_lock_controller.dart';
import '../app_security_lab_controller.dart';
import '../pin_flow_screen.dart';

class PinSection extends ConsumerWidget {
  const PinSection({super.key});

  Future<void> _openFlow(BuildContext context, WidgetRef ref, PinFlowMode mode) async {
    final shuffle = ref.read(appSecurityLabProvider).shuffleKeypad;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PinFlowScreen(mode: mode, shuffleKeys: shuffle),
      ),
    );
    if (ok == true) {
      messenger.showSnackBar(
        SnackBar(content: Text(mode == PinFlowMode.setup ? 'PIN created — app lock is now active' : 'PIN changed')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinSet = ref.watch(appLockProvider.select((s) => s.pinSet));
    final shuffle = ref.watch(appSecurityLabProvider.select((s) => s.shuffleKeypad));
    return SectionCard(
      title: '2 · PIN set-up & change flow',
      trailing: Pill(pinSet ? 'PIN active' : 'No PIN', color: pinSet ? AppColors.teal : AppColors.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConceptBullets(
            points: [
              'Re-authenticate with the current PIN before changing it',
              'Reject weak PINs: 111111, 123456, 121212, MMYYYY',
              '5 wrong attempts → lockout 30 s, doubling each time',
              'Custom keypad: no system keyboard, no IME logging',
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shuffle keypad digits'),
            subtitle: const Text('Defeats shoulder-surfing & tap-position loggers'),
            value: shuffle,
            onChanged: ref.read(appSecurityLabProvider.notifier).setShuffle,
          ),
          const SizedBox(height: 4),
          if (!pinSet)
            BusyButton(
              label: 'Set up PIN',
              icon: Icons.pin_rounded,
              onPressed: () => _openFlow(context, ref, PinFlowMode.setup),
            )
          else
            Row(
              children: [
                Expanded(
                  child: BusyButton(
                    label: 'Change PIN',
                    icon: Icons.password_rounded,
                    onPressed: () => _openFlow(context, ref, PinFlowMode.change),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BusyButton(
                    label: 'Lock now',
                    icon: Icons.lock_rounded,
                    outlined: true,
                    onPressed: () => ref.read(appLockProvider.notifier).lock(LockReason.manual),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
