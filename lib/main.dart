import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'features/app_lock/app_lock_gate.dart';
import 'features/home/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: SecurePayAcademy()));
}

class SecurePayAcademy extends StatelessWidget {
  const SecurePayAcademy({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SecurePay Academy',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // The lock gate wraps the Navigator, so every route is behind it.
      builder: (context, child) => AppLockGate(child: child!),
      home: const HomeScreen(),
    );
  }
}
