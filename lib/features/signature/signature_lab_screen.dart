import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/theme.dart';
import '../../core/utils/bytes.dart';
import '../../widgets/lab_widgets.dart';
import 'signature_controller.dart';

const _module = LabModule.signature;

class SignatureLabScreen extends ConsumerWidget {
  const SignatureLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = ref.watch(signatureLabProvider.select((s) => s.identity != null));
    final hasSignature = ref.watch(signatureLabProvider.select((s) => s.signature != null));
    return LabScaffold(
      module: _module,
      children: [
        const _HmacVsSignature(),
        const _KeyPairCard(),
        if (hasKey) const _AuthoriseCard(),
        if (hasSignature) const _VerifyCard(),
        const CodeSnippet(code: _code),
      ],
    );
  }
}

class _KeyPairCard extends ConsumerWidget {
  const _KeyPairCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(signatureLabProvider);
    final id = s.identity;
    return SectionCard(
      title: '1 · Device key pair',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (id == null)
            const Text(
              'No signing key yet. Generate one — it is persisted in Secure Storage.',
              style: TextStyle(color: AppColors.muted),
            )
          else ...[
            Row(
              children: [
                Pill(
                  s.fromVault ? 'Restored from Secure Storage' : 'New key · saved to Secure Storage',
                  color: AppColors.teal,
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutputField(label: 'Public key (share with bank)', value: id.publicKeyB64, color: _module.color),
            OutputField(label: 'Fingerprint', value: s.fingerprint),
            const OutputField(label: 'Private key', value: '🔒 stays in Keychain / Keystore'),
          ],
          const SizedBox(height: 4),
          BusyButton(
            outlined: true,
            onPressed: ref.read(signatureLabProvider.notifier).generate,
            icon: Icons.key_rounded,
            label: id == null ? 'Generate Ed25519 key' : 'Rotate key',
          ),
        ],
      ),
    );
  }
}

class _AuthoriseCard extends ConsumerWidget {
  const _AuthoriseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(signatureLabProvider);
    final c = ref.read(signatureLabProvider.notifier);
    return SectionCard(
      title: '2 · Authorise a transfer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SyncedTextField(label: 'Payee', value: s.payee, onChanged: c.setPayee),
          const SizedBox(height: 10),
          SyncedTextField(
            label: 'Amount (₹)',
            value: s.amount,
            onChanged: c.setAmount,
            keyboardType: TextInputType.number,
            prefixText: '₹ ',
          ),
          const SizedBox(height: 12),
          BusyButton(onPressed: c.signTransaction, icon: Icons.draw_rounded, label: 'Sign transaction'),
          if (s.signature != null) ...[
            const SizedBox(height: 14),
            OutputField(label: 'Canonical message', value: s.signedMessage!),
            OutputField(label: 'Signature (64 B, base64)', value: Bytes.toBase64(s.signature!), color: _module.color),
          ],
        ],
      ),
    );
  }
}

class _VerifyCard extends ConsumerWidget {
  const _VerifyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(signatureLabProvider);
    final c = ref.read(signatureLabProvider.notifier);
    final verified = s.verified;
    return SectionCard(
      title: '3 · Bank verifies',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Attacker changes amount ×10'),
            value: s.tamperAmount,
            activeThumbColor: AppColors.red,
            onChanged: c.setTamperAmount,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Verify with a different device key'),
            value: s.otherKey,
            activeThumbColor: AppColors.red,
            onChanged: c.setOtherKey,
          ),
          const SizedBox(height: 6),
          BusyButton(outlined: true, onPressed: c.verify, icon: Icons.verified_user_rounded, label: 'Verify signature'),
          if (verified != null) ...[
            const SizedBox(height: 12),
            StatusBanner(
              ok: verified,
              text: verified
                  ? 'Valid — this exact transaction was authorised by device ${s.fingerprint}'
                  : 'Invalid signature — reject and flag for fraud review',
            ),
          ],
        ],
      ),
    );
  }
}

class _HmacVsSignature extends StatelessWidget {
  const _HmacVsSignature();

  static const _rows = [
    ('Keys', 'One shared secret', 'Private + public pair'),
    ('Who can create', 'Both parties', 'Only the key owner'),
    ('Non-repudiation', '✗', '✓'),
    ('Speed / size', 'Very fast · 32 B', 'Fast · 64 B'),
    ('Use for', 'API request auth', 'Transaction approval'),
  ];

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    const cell = TextStyle(fontSize: 12.5, color: Colors.white70);
    return SectionCard(
      title: 'HMAC vs Digital Signature',
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.3)},
        children: [
          const TableRow(
            children: [
              SizedBox(),
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('HMAC', style: head),
              ),
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Ed25519', style: head),
              ),
            ],
          ),
          for (final r in _rows)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(r.$1, style: head.copyWith(color: AppColors.muted)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(r.$2, style: cell),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(r.$3, style: cell),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

const _code = r'''
final algo = Ed25519();
final keyPair = await algo.newKeyPair();

// Persist ONLY the private seed, in Secure Storage
final seed = await keyPair.extractPrivateKeyBytes();
await storage.write(key: 'device.ed25519.seed', value: base64Encode(seed));

// Register public key with the bank during device binding
final pub = await keyPair.extractPublicKey();
await api.registerDevice(deviceId, base64Encode(pub.bytes));

// Sign a canonical (sorted-keys) JSON message
final sig = await algo.sign(utf8.encode(canonicalJson(tx)), keyPair: keyPair);

// Server side
final ok = await algo.verify(message, signature: Signature(sigBytes,
    publicKey: SimplePublicKey(pubBytes, type: KeyPairType.ed25519)));''';
