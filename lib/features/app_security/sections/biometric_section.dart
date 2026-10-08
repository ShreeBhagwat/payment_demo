import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../widgets/lab_widgets.dart';
import '../../app_lock/app_lock_controller.dart';
import '../app_security_lab_controller.dart';

class BiometricSection extends ConsumerWidget {
  const BiometricSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(biometricCapabilityProvider).value;
    final lock = ref.watch(appLockProvider);
    final lab = ref.watch(appSecurityLabProvider);
    final controller = ref.read(appSecurityLabProvider.notifier);
    final enrolled = cap?.enrolled ?? false;

    return SectionCard(
      title: '3 · Biometric authentication',
      trailing: cap == null ? null : Pill(cap.label, color: enrolled ? AppColors.teal : AppColors.muted),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ConceptBullets(
            points: [
              'Biometrics are a convenience on top of the PIN, never a replacement',
              'Enabling requires a successful scan',
              "PIN lockout also blocks biometrics, so they can't be used to bypass it",
              'authenticate() returns a bool that Frida can fake — bind secrets to biometrics for high value',
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Unlock with biometrics'),
            subtitle: Text(lock.pinSet ? 'Shown on the lock screen' : 'Set up a PIN first'),
            value: lock.biometricEnabled,
            onChanged: lock.pinSet && enrolled ? controller.setBiometricUnlock : null,
          ),
          BusyButton(
            label: 'Test authentication',
            icon: Icons.fingerprint_rounded,
            outlined: true,
            onPressed: enrolled ? controller.testBiometric : null,
          ),
          if (lab.biometricMessage != null) ...[
            const SizedBox(height: 10),
            StatusBanner(ok: lab.biometricOk, text: lab.biometricMessage!),
          ],
          if (cap != null && !enrolled) ...[
            const SizedBox(height: 10),
            const Text(
              'Simulator tip: iOS → Features › Face ID › Enrolled, then › Matching Face. '
              "Android emulator → Settings › Security › Fingerprint, then use the emulator's fingerprint control.",
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
