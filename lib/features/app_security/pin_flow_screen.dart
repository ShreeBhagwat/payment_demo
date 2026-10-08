import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../widgets/pin_pad.dart';
import 'pin_flow_controller.dart';
import 'secure_screen.dart';

export 'pin_flow_controller.dart' show PinFlowMode;

/// PIN set-up / change UI. All flow logic lives in [PinFlowController]; this
/// widget only renders state and drives the pad's animations. The page
/// blocks screenshots while visible (SecureScreen).
class PinFlowScreen extends ConsumerStatefulWidget {
  const PinFlowScreen({super.key, required this.mode, this.shuffleKeys = false});

  final PinFlowMode mode;
  final bool shuffleKeys;

  @override
  ConsumerState<PinFlowScreen> createState() => _PinFlowScreenState();
}

class _PinFlowScreenState extends ConsumerState<PinFlowScreen> {
  final _pad = GlobalKey<PinPadState>();

  @override
  Widget build(BuildContext context) {
    final provider = pinFlowProvider(widget.mode);
    ref
      ..listen(provider.select((s) => s.rejections), (_, _) => _pad.currentState?.reject())
      ..listen(provider.select((s) => s.step), (_, _) => _pad.currentState?.clear())
      ..listen(provider.select((s) => s.done), (_, done) {
        if (done) Navigator.of(context).pop(true);
      });

    final state = ref.watch(provider);
    final flow = ref.read(provider.notifier);

    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: Text(widget.mode == PinFlowMode.setup ? 'Set up PIN' : 'Change PIN')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _StepIndicator(count: flow.stepCount, index: flow.stepIndex),
                  const SizedBox(height: 24),
                  Text(flow.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text('Avoid birthdays, repeats and sequences', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: Text(
                      state.error ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                    ),
                  ),
                  PinPad(
                    key: _pad,
                    length: ref.read(pinServiceProvider).pinLength,
                    enabled: !state.busy,
                    shuffle: widget.shuffleKeys,
                    onCompleted: flow.submit,
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.screenshot_monitor_rounded, size: 16, color: AppColors.teal),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Screenshots blocked on this screen',
                          style: TextStyle(color: AppColors.teal, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 28 : 10,
            height: 6,
            decoration: BoxDecoration(
              color: i <= index ? AppColors.gold : AppColors.card,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
