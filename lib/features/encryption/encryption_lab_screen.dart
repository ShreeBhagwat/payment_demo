import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/theme.dart';
import '../../core/utils/bytes.dart';
import '../../widgets/lab_widgets.dart';
import 'encryption_controller.dart';

const _module = LabModule.encryption;

class EncryptionLabScreen extends ConsumerWidget {
  const EncryptionLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final encrypted = ref.watch(encryptionLabProvider.select((s) => s.payload != null));
    return LabScaffold(
      module: _module,
      children: [
        const ConceptCard(
          points: [
            (
              'Use AEAD (AES-GCM / ChaCha20-Poly1305).',
              'Avoid ECB (leaks patterns) and unauthenticated CBC (padding oracle).',
            ),
            (
              'Nonce must never repeat for a key.',
              'Reuse in GCM leaks the XOR of plaintexts and the auth key. Use 12 random bytes.',
            ),
            ('AAD', 'binds context (customer id, order id) to the ciphertext without encrypting it.'),
            ('Never hard-code keys.', 'Derive from a PIN with PBKDF2/Argon2, or generate and keep in Secure Storage.'),
          ],
        ),
        const _EncryptCard(),
        if (encrypted) const _DecryptCard(),
        const CodeSnippet(code: _code),
      ],
    );
  }
}

class _EncryptCard extends ConsumerWidget {
  const _EncryptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(encryptionLabProvider);
    final c = ref.read(encryptionLabProvider.notifier);
    final p = s.payload;
    return SectionCard(
      title: '1 · Encrypt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyncedTextField(label: 'Sensitive plaintext', value: s.plain, onChanged: c.setPlain, maxLines: 2),
          const SizedBox(height: 10),
          SyncedTextField(label: 'AAD (authenticated, not encrypted)', value: s.aad, onChanged: c.setAad),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('PIN → PBKDF2'), icon: Icon(Icons.pin_rounded)),
              ButtonSegment(value: false, label: Text('Random key'), icon: Icon(Icons.casino_rounded)),
            ],
            selected: {s.usePin},
            onSelectionChanged: (v) => c.setUsePin(v.first),
          ),
          if (s.usePin) ...[
            const SizedBox(height: 10),
            SyncedTextField(
              label: 'PIN (100,000 PBKDF2 iterations)',
              value: s.pin,
              onChanged: c.setPin,
              obscure: true,
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 12),
          BusyButton(
            busy: s.busy,
            onPressed: c.encrypt,
            icon: Icons.lock_rounded,
            label: p == null ? 'Encrypt' : 'Encrypt again (new nonce)',
          ),
          if (p != null) ...[
            const SizedBox(height: 14),
            if (s.salt != null)
              OutputField(label: 'Salt · key derived in ${s.kdfMillis} ms', value: Bytes.toHex(s.salt!)),
            OutputField(label: 'AES-256 key (demo only — never display!)', value: s.keyHex, color: AppColors.red),
            OutputField(label: 'Nonce / IV (12 B)', value: Bytes.toHex(p.nonce)),
            OutputField(label: 'Ciphertext', value: Bytes.toBase64(p.cipherText), color: _module.color),
            OutputField(label: 'GCM tag (16 B)', value: Bytes.toHex(p.mac)),
            OutputField(label: 'Compact (iv ‖ ct ‖ tag)', value: p.toCompact()),
          ],
        ],
      ),
    );
  }
}

class _DecryptCard extends ConsumerWidget {
  const _DecryptCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tamper = ref.watch(encryptionLabProvider.select((s) => s.tamper));
    final decrypted = ref.watch(encryptionLabProvider.select((s) => s.decrypted));
    final error = ref.watch(encryptionLabProvider.select((s) => s.decryptError));
    final c = ref.read(encryptionLabProvider.notifier);
    return SectionCard(
      title: '2 · Decrypt — try to break it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OptionChips<EncryptionTamper>(
            options: EncryptionTamper.values,
            selected: tamper,
            labelOf: (t) => t.label,
            isDanger: (t) => t != EncryptionTamper.none,
            onSelected: c.setTamper,
          ),
          const SizedBox(height: 12),
          BusyButton(outlined: true, onPressed: c.decrypt, icon: Icons.lock_open_rounded, label: 'Decrypt'),
          if (decrypted != null) ...[
            const SizedBox(height: 12),
            const StatusBanner(ok: true, text: 'Tag verified — plaintext recovered'),
            const SizedBox(height: 10),
            OutputField(label: 'Plaintext', value: decrypted, color: AppColors.teal),
          ],
          if (error != null) ...[const SizedBox(height: 12), StatusBanner(ok: false, text: error)],
        ],
      ),
    );
  }
}

const _code = r'''
final algo = AesGcm.with256bits();

// Key from PIN (store the salt with the ciphertext)
final key = await Pbkdf2(
  macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256,
).deriveKeyFromPassword(password: pin, nonce: salt);

final box = await algo.encrypt(
  utf8.encode(cardData),
  secretKey: key,
  nonce: algo.newNonce(),          // fresh 12 bytes every time
  aad: utf8.encode('customer:CIF-00921'),
);

try {
  final clear = await algo.decrypt(box, secretKey: key, aad: aad);
} on SecretBoxAuthenticationError {
  // tampered / wrong key → treat as an attack, log & alert
}''';
