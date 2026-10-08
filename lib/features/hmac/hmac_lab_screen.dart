import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/theme.dart';
import '../../widgets/lab_widgets.dart';
import 'hmac_controller.dart';

const _module = LabModule.hmac;

class HmacLabScreen extends StatelessWidget {
  const HmacLabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LabScaffold(
      module: _module,
      children: [
        ConceptCard(
          points: [
            (
              'HMAC = H(key ⊕ opad ‖ H(key ⊕ ipad ‖ msg)).',
              'Plain SHA-256(key ‖ msg) is vulnerable to length-extension; HMAC is not.',
            ),
            ('Integrity + authenticity.', 'Any change to the message or wrong key gives a totally different MAC.'),
            ('Not encryption.', 'The message is still readable. Combine with TLS / AES for confidentiality.'),
            ('Constant-time compare.', 'Never use == on MACs; early exit leaks timing information.'),
          ],
        ),
        _SenderCard(),
        _ReceiverCard(),
        _RequestSigningCard(),
        CodeSnippet(code: _code),
      ],
    );
  }
}

class _SenderCard extends ConsumerWidget {
  const _SenderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(hmacLabProvider);
    final c = ref.read(hmacLabProvider.notifier);
    return SectionCard(
      title: '1 · Sender computes the MAC',
      child: Column(
        children: [
          SyncedTextField(label: 'Shared secret key', value: s.key, onChanged: c.setKey),
          const SizedBox(height: 10),
          SyncedTextField(label: 'Message', value: s.message, onChanged: c.setMessage, maxLines: 2),
          const SizedBox(height: 12),
          OutputField(label: 'HMAC-SHA256 (hex)', value: s.mac, color: _module.color),
        ],
      ),
    );
  }
}

class _ReceiverCard extends ConsumerWidget {
  const _ReceiverCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = ref.watch(hmacLabProvider.select((s) => s.received));
    final valid = ref.watch(hmacLabProvider.select((s) => s.valid));
    final c = ref.read(hmacLabProvider.notifier);
    return SectionCard(
      title: '2 · Receiver verifies',
      trailing: TextButton.icon(
        onPressed: c.tamper,
        icon: const Icon(Icons.bug_report_rounded, size: 18, color: AppColors.red),
        label: const Text('Tamper', style: TextStyle(color: AppColors.red)),
      ),
      child: Column(
        children: [
          SyncedTextField(label: 'Message as received', value: received, onChanged: c.setReceived, maxLines: 2),
          const SizedBox(height: 12),
          StatusBanner(
            ok: valid,
            text: valid ? 'MAC valid — message is authentic' : 'MAC mismatch — reject request (HTTP 401)',
          ),
          if (!valid) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: c.restore, child: const Text('Restore original')),
          ],
        ],
      ),
    );
  }
}

class _RequestSigningCard extends ConsumerWidget {
  const _RequestSigningCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(hmacLabProvider.select((s) => s.headers));
    final canonical = ref.watch(hmacLabProvider.select((s) => s.canonical));
    return SectionCard(
      title: '3 · Production request signing',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sign method, path, timestamp, nonce and body hash together so the '
            'signature cannot be replayed or moved to another endpoint.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          BusyButton(
            onPressed: ref.read(hmacLabProvider.notifier).signRequest,
            icon: Icons.draw_rounded,
            label: 'Sign POST /v1/transfers',
          ),
          if (headers != null) ...[
            const SizedBox(height: 14),
            OutputField(label: 'String-to-sign', value: canonical),
            for (final e in headers.toMap().entries)
              OutputField(label: e.key, value: e.value, color: e.key == 'X-Signature' ? _module.color : null),
          ],
        ],
      ),
    );
  }
}

const _code = r'''
import 'package:crypto/crypto.dart';

String hmacSha256(List<int> key, String msg) =>
    Hmac(sha256, key).convert(utf8.encode(msg)).toString();

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff == 0;
}

// Dio interceptor
onRequest: (o, h) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final nonce = hex(randomBytes(16));
  final bodyHash = sha256.convert(utf8.encode(o.data)).toString();
  final toSign = [o.method, o.path, ts, nonce, bodyHash].join('\n');
  o.headers.addAll({
    'X-Timestamp': '$ts', 'X-Nonce': nonce,
    'X-Content-SHA256': bodyHash,
    'X-Signature': hmacSha256(sessionKey, toSign),
  });
  h.next(o);
}''';
