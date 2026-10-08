import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screen_security_controller.dart';

/// Wrap a sensitive page to block capture only while it is on screen.
class SecureScreen extends ConsumerStatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends ConsumerState<SecureScreen> {
  // Captured up-front: `ref` must not be used in dispose().
  late final ScreenSecurityController _security = ref.read(screenSecurityProvider.notifier);

  // Providers may not be modified while the widget tree is building or
  // unmounting, so the claim/release run just after.
  @override
  void initState() {
    super.initState();
    Future.microtask(_security.claim);
  }

  @override
  void dispose() {
    Future.microtask(_security.release);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
