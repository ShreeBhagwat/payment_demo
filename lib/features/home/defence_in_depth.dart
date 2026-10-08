import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/lab_module.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

class _Layer {
  const _Layer(this.name, this.what, this.stops, this.icon, this.color, this.module);

  final String name;
  final String what;
  final String stops;
  final IconData icon;
  final Color color;
  final LabModule module; // where trainees can try this layer
}

// Outermost (first thing an attacker hits) → innermost.
const _layers = [
  _Layer(
    'Transport',
    'TLS 1.3 + SPKI certificate pinning',
    'Proxy / rogue-CA man-in-the-middle',
    Icons.cable_rounded,
    Color(0xFF4FC3F7),
    LabModule.appSecurity,
  ),
  _Layer(
    'Device',
    'App lock, root detection, screenshot blocking',
    'Stolen, rooted or shoulder-surfed phones',
    Icons.phonelink_lock_rounded,
    Color(0xFF2ED3B7),
    LabModule.appSecurity,
  ),
  _Layer(
    'Request',
    'HMAC-SHA256 over method, path, timestamp, nonce, body',
    'Tampering and replayed requests',
    Icons.fingerprint_rounded,
    Color(0xFF6C8CFF),
    LabModule.hmac,
  ),
  _Layer(
    'Payload',
    'AES-256-GCM with order-bound AAD',
    'Card data leaking into logs and proxies',
    Icons.enhanced_encryption_rounded,
    Color(0xFFB57BFF),
    LabModule.encryption,
  ),
  _Layer(
    'Authorisation',
    'Ed25519 device signature + biometric step-up',
    'Malware holding stolen session keys',
    Icons.draw_rounded,
    Color(0xFFF2B544),
    LabModule.signature,
  ),
  _Layer(
    'At rest',
    'Keychain / Android Keystore, no backups',
    'Key theft from disk or cloud backups',
    Icons.lock_rounded,
    Color(0xFF7BE495),
    LabModule.storage,
  ),
  _Layer(
    'Business rules',
    'Server-side order amount + gateway signature',
    'Amount manipulation by a hooked app',
    Icons.rule_rounded,
    Color(0xFFFF7A59),
    LabModule.payment,
  ),
];

/// Which ring is selected. Kept in Riverpod so it survives navigating into
/// a lab and back.
final selectedDefenceLayerProvider = NotifierProvider<SelectedDefenceLayer, int>(SelectedDefenceLayer.new);

class SelectedDefenceLayer extends Notifier<int> {
  @override
  int build() => 0;

  void select(int i) => state = i.clamp(0, _layers.length - 1);
}

/// Interactive "security onion": each ring is a layer an attacker must
/// break through to reach the customer's money in the centre.
class DefenceInDepth extends ConsumerStatefulWidget {
  const DefenceInDepth({super.key});

  @override
  ConsumerState<DefenceInDepth> createState() => _DefenceInDepthState();
}

// The State only owns the intro animation (a widget-lifecycle concern);
// the selection lives in [selectedDefenceLayerProvider].
class _DefenceInDepthState extends ConsumerState<DefenceInDepth> with SingleTickerProviderStateMixin {
  static const _size = 264.0;
  static const _outer = 124.0;
  static const _step = 13.0;
  static const _stroke = 8.0;

  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();

  static double _radius(int i) => _outer - i * _step;

  // Badges spiral around the rings so they never overlap.
  static Offset _badgeOffset(int i) {
    final a = -pi / 2 + i * (2 * pi / _layers.length);
    return Offset(cos(a), sin(a)) * _radius(i);
  }

  int get _selected => ref.watch(selectedDefenceLayerProvider);

  void _select(int i) => ref.read(selectedDefenceLayerProvider.notifier).select(i);

  void _onTapRings(Offset local) {
    final d = (local - const Offset(_size / 2, _size / 2)).distance;
    for (var i = 0; i < _layers.length; i++) {
      if ((d - _radius(i)).abs() <= _step / 2) return _select(i);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layer = _layers[_selected];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Defence in depth', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${_layers.length} independent layers protect every rupee. '
              'An attacker has to beat all of them; we only need one to hold.',
              style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Center(
              child: GestureDetector(
                onTapUp: (d) => _onTapRings(d.localPosition),
                child: SizedBox(
                  width: _size,
                  height: _size,
                  child: AnimatedBuilder(
                    animation: _intro,
                    builder: (context, _) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _RingsPainter(
                              selected: _selected,
                              progress: Curves.easeOutCubic.transform(_intro.value),
                            ),
                          ),
                        ),
                        _core(),
                        for (var i = 0; i < _layers.length; i++) _badge(i),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('Tap a ring', style: TextStyle(fontSize: 11.5, color: AppColors.muted, letterSpacing: .5)),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: _detail(layer, key: ValueKey(_selected)),
            ),
            const SizedBox(height: 12),
            _stepper(),
          ],
        ),
      ),
    );
  }

  Widget _core() {
    final t = Curves.elasticOut.transform(((_intro.value - .55) / .45).clamp(0.0, 1.0));
    return Center(
      child: Transform.scale(
        scale: t,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFFFFD27A), AppColors.gold]),
            boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: .5), blurRadius: 18)],
          ),
          child: const Center(
            child: Text(
              '₹',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navy),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(int i) {
    final l = _layers[i];
    final sel = i == _selected;
    final appear = ((_intro.value - i * .06) / .5).clamp(0.0, 1.0);
    final size = sel ? 30.0 : 24.0;
    final o = _badgeOffset(i) + const Offset(_size / 2, _size / 2);
    return Positioned(
      left: o.dx - size / 2,
      top: o.dy - size / 2,
      child: Opacity(
        opacity: appear,
        child: GestureDetector(
          onTap: () => _select(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sel ? l.color : AppColors.card,
              border: Border.all(color: l.color, width: 2),
              boxShadow: sel ? [BoxShadow(color: l.color.withValues(alpha: .6), blurRadius: 12)] : null,
            ),
            child: Icon(l.icon, size: sel ? 16 : 13, color: sel ? AppColors.navy : l.color),
          ),
        ),
      ),
    );
  }

  Widget _detail(_Layer l, {required Key key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [l.color.withValues(alpha: .18), AppColors.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: l.color.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(l.icon, color: l.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text(
                'LAYER ${_selected + 1}/${_layers.length}',
                style: TextStyle(fontSize: 10.5, letterSpacing: 1, color: l.color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(l.what, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.block_rounded, size: 16, color: AppColors.red),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Stops  ',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      TextSpan(
                        text: l.stops,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: l.color,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => openModule(context, l.module),
              icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
              label: Text('Try it in Module ${l.module.number}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper() {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: _selected == 0 ? null : () => _select(_selected - 1),
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          tooltip: 'Outer layer',
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _layers.length; i++)
                GestureDetector(
                  onTap: () => _select(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _selected ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _selected ? _layers[i].color : _layers[i].color.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: _selected == _layers.length - 1 ? null : () => _select(_selected + 1),
          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
          tooltip: 'Inner layer',
        ),
      ],
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.selected, required this.progress});

  final int selected;
  final double progress; // 0→1 intro animation

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < _layers.length; i++) {
      final r = _DefenceInDepthState._radius(i);
      final color = _layers[i].color;
      final sel = i == selected;
      // Each ring sweeps in, outer rings first.
      // Staggered so the innermost ring also completes exactly at progress 1.
      final t = ((progress - i * .07) / (1 - (_layers.length - 1) * .07)).clamp(0.0, 1.0);
      if (t == 0) continue;

      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _DefenceInDepthState._stroke
          ..color = color.withValues(alpha: .08),
      );

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = sel ? _DefenceInDepthState._stroke + 3 : _DefenceInDepthState._stroke
        ..color = color.withValues(alpha: sel ? 1 : .42);
      if (sel) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..color = color.withValues(alpha: .18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2 + i * .35, 2 * pi * t, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.selected != selected || old.progress != progress;
}
