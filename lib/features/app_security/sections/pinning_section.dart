import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/lab_module.dart';
import '../../../widgets/lab_widgets.dart';
import '../pinning_lab_controller.dart';

class PinningSection extends ConsumerWidget {
  const PinningSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(pinningLabProvider);
    final controller = ref.read(pinningLabProvider.notifier);
    final c = s.cert;
    return SectionCard(
      title: '7 · Certificate pinning with Dio',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TLS trusts ~150 root CAs plus any CA the user installs. Pinning trusts only YOUR '
            "server's public key, so Burp/Charles proxies and rogue CAs get nothing.",
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SyncedTextField(
                  label: 'Host',
                  prefixText: 'https://',
                  value: s.host,
                  onChanged: controller.setHost,
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(onPressed: s.busy ? null : controller.inspect, child: const Text('Inspect')),
            ],
          ),
          if (c != null) ...[
            const SizedBox(height: 14),
            OutputField(label: 'Subject', value: c.subject),
            OutputField(label: 'Issuer', value: c.issuer),
            OutputField(label: 'Valid until', value: c.validUntil.toIso8601String().substring(0, 10)),
            OutputField(label: 'SPKI pin  sha256/base64', value: c.spkiPin, color: LabModule.appSecurity.color),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: BusyButton(
                    label: 'Pinned call',
                    icon: Icons.verified_user_rounded,
                    onPressed: s.busy ? null : () => controller.pinnedRequest(correctPin: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BusyButton(
                    label: 'Simulate MITM',
                    icon: Icons.bug_report_rounded,
                    danger: true,
                    onPressed: s.busy ? null : () => controller.pinnedRequest(correctPin: false),
                  ),
                ),
              ],
            ),
          ],
          if (s.busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (s.status != null) ...[const SizedBox(height: 12), StatusBanner(ok: s.ok ?? false, text: s.status!)],
          const SizedBox(height: 12),
          const ConceptBullets(
            points: [
              'Pin the public key (SPKI), not the certificate: certs renew, keys can stay',
              'Always ship a BACKUP pin, or a key rotation bricks every installed app',
              'Live demo: route the phone through Charles/Burp; the pinned call fails',
              'Pins are discovered here for teaching (trust-on-first-use). In production they are hard-coded or delivered by signed config',
            ],
          ),
        ],
      ),
    );
  }
}
