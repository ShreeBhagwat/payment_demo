import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/theme.dart';
import '../../core/utils/bytes.dart';
import '../../widgets/lab_widgets.dart';
import 'storage_controller.dart';

const _module = LabModule.storage;

class StorageLabScreen extends StatelessWidget {
  const StorageLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LabScaffold(
      module: _module,
      children: [
        _Comparison(),
        _VaultCard(),
        ConceptCard(
          title: 'Hardening checklist',
          points: [
            (
              'iOS:',
              'KeychainAccessibility.first_unlock_this_device — never synced to iCloud or restored to another phone.',
            ),
            ('Android:', 'AndroidManifest android:allowBackup="false" and dataExtractionRules to exclude secrets.'),
            (
              'Logout / unbind:',
              'deleteAll() and revoke keys server-side. iOS Keychain survives uninstall — clear on first launch.',
            ),
            ('Store keys, not data:', 'Keep a data-encryption key here and encrypt bulky data (SQLite) with it.'),
            (
              'Root / jailbreak:',
              'Keystore raises the bar but is not magic. Pair with RASP / Play Integrity / App Attest.',
            ),
          ],
        ),
        CodeSnippet(code: _code),
      ],
    );
  }
}

class _VaultCard extends ConsumerWidget {
  const _VaultCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(storageLabProvider);
    final c = ref.read(storageLabProvider.notifier);
    return SectionCard(
      title: 'Live vault on this device',
      trailing: IconButton(onPressed: c.refresh, icon: const Icon(Icons.refresh_rounded)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyncedTextField(label: 'Key', value: s.keyName, onChanged: c.setKeyName),
          const SizedBox(height: 10),
          SyncedTextField(label: 'Secret value', value: s.value, onChanged: c.setValue),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BusyButton(onPressed: c.write, icon: Icons.save_rounded, label: 'Write'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BusyButton(
                  outlined: true,
                  onPressed: c.wipe,
                  icon: Icons.delete_sweep_rounded,
                  label: 'Wipe all',
                ),
              ),
            ],
          ),
          if (s.error != null) ...[const SizedBox(height: 12), StatusBanner(ok: false, text: s.error!)],
          const SizedBox(height: 16),
          if (s.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Vault is empty. Tip: run the Payment lab onboarding to see device keys appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          for (final e in s.entries.entries)
            _EntryTile(entryKey: e.key, value: e.value, revealed: s.revealed.contains(e.key)),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entryKey, required this.value, required this.revealed});

  final String entryKey;
  final String value;
  final bool revealed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(storageLabProvider.notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.code, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.key_rounded, size: 18, color: _module.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entryKey, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  revealed ? Bytes.ellipsize(value, keep: 16) : '•' * 18,
                  style: mono.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
            onPressed: () => c.toggleReveal(entryKey),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.red),
            onPressed: () => c.remove(entryKey),
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: 'Where does the token live?',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ComparisonColumn('SharedPreferences', Icons.lock_open_rounded, AppColors.red, [
            'Plain XML / plist on disk',
            'Readable on rooted device',
            'Included in adb / iTunes backups',
          ]),
          SizedBox(width: 10),
          _ComparisonColumn('Secure Storage', Icons.lock_rounded, AppColors.teal, [
            'Keychain / Keystore (TEE)',
            'Encrypted with hardware key',
            'Device-bound, not backed up',
          ]),
        ],
      ),
    );
  }
}

class _ComparisonColumn extends StatelessWidget {
  const _ComparisonColumn(this.title, this.icon, this.color, this.lines);

  final String title;
  final IconData icon;
  final Color color;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          border: Border.all(color: color.withValues(alpha: .4)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l, style: const TextStyle(fontSize: 12.5, color: Colors.white70, height: 1.35)),
              ),
          ],
        ),
      ),
    );
  }
}

const _code = r'''
const storage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
  aOptions: AndroidOptions(), // AES-GCM, key wrapped by Android Keystore
);

await storage.write(key: 'auth.access_token', value: token);
final token = await storage.read(key: 'auth.access_token');
await storage.deleteAll(); // on logout

// Clear stale iOS keychain items after a reinstall
final prefs = await SharedPreferences.getInstance();
if (prefs.getBool('first_run') ?? true) {
  await storage.deleteAll();
  await prefs.setBool('first_run', false);
}''';
