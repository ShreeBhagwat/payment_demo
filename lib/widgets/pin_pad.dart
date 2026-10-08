import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

/// Custom numeric keypad.
///
/// Why not a TextField? The system keyboard can be a third-party IME that
/// logs keystrokes, it may offer autocorrect/suggestions, and it can be
/// captured by accessibility services. Banking PIN entry uses an in-app pad.
/// [shuffle] randomises digit positions to defeat shoulder-surfing and
/// tap-coordinate logging malware.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.onCompleted,
    this.enabled = true,
    this.shuffle = false,
    this.extraAction,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool shuffle;
  final Widget? extraAction; // e.g. biometric button, bottom-left slot

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _value = '';
  late List<int> _digits;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    _digits = _layout();
  }

  List<int> _layout() {
    final d = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    if (widget.shuffle) d.shuffle(Random.secure());
    return d;
  }

  /// Clear input and shake (wrong PIN).
  void reject() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _value = '';
      _digits = _layout();
    });
  }

  void clear() => setState(() => _value = '');

  void _tap(int d) {
    if (!widget.enabled || _value.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _value += '$d');
    if (_value.length == widget.length) {
      final v = _value;
      Future.delayed(const Duration(milliseconds: 120), () => widget.onCompleted(v));
    }
  }

  void _backspace() {
    if (_value.isEmpty) return;
    setState(() => _value = _value.substring(0, _value.length - 1));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(sin(_shake.value * pi * 6) * 12 * (1 - _shake.value), 0),
            child: child,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _value.length ? AppColors.gold : Colors.transparent,
                    border: Border.all(color: i < _value.length ? AppColors.gold : AppColors.muted, width: 1.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        for (var row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (var col = 0; col < 3; col++) _key(_digits[row * 3 + col])],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 84, height: 72, child: Center(child: widget.extraAction)),
            _key(_digits[9]),
            SizedBox(
              width: 84,
              height: 72,
              child: IconButton(
                onPressed: widget.enabled ? _backspace : null,
                icon: const Icon(Icons.backspace_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(int d) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox(
        width: 72,
        height: 60,
        child: Material(
          color: AppColors.card,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.enabled ? () => _tap(d) : null,
            child: Center(
              child: Text('$d', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}
