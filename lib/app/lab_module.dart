import 'package:flutter/material.dart';

/// Single source of truth for every training module's identity: used by the
/// home tiles, each lab's header and the defence-in-depth rings (DRY).
enum LabModule {
  hmac(
    title: 'HMAC Request Signing',
    shortTitle: 'HMAC Signing',
    tagline: 'Integrity & authenticity for every API call',
    intro: 'Prove a request came from someone holding the secret and was not modified on the way.',
    icon: Icons.fingerprint_rounded,
    color: Color(0xFF6C8CFF),
    tags: ['SHA-256', 'Anti-replay', 'Timing-safe'],
  ),
  storage(
    title: 'Flutter Secure Storage',
    shortTitle: 'Secure Storage',
    tagline: 'Keychain & Android Keystore backed vault',
    intro: 'Store tokens and keys in the OS keystore, never in SharedPreferences, files or SQLite.',
    icon: Icons.lock_rounded,
    color: Color(0xFF2ED3B7),
    tags: ['Keychain', 'Keystore', 'MASVS-STORAGE'],
  ),
  encryption(
    title: 'Encryption & Decryption',
    shortTitle: 'Encryption',
    tagline: 'AES-256-GCM, PBKDF2 and tamper detection',
    intro: 'AES-256-GCM authenticated encryption — confidentiality and tamper detection in one primitive.',
    icon: Icons.enhanced_encryption_rounded,
    color: Color(0xFFB57BFF),
    tags: ['AES-GCM', 'AAD', 'PBKDF2'],
  ),
  signature(
    title: 'Digital Signatures',
    shortTitle: 'Digital Signatures',
    tagline: 'Ed25519 transaction signing & non-repudiation',
    intro: 'The device signs each transaction with a private key that never leaves Secure Storage.',
    icon: Icons.draw_rounded,
    color: Color(0xFFF2B544),
    tags: ['Ed25519', 'Device binding'],
  ),
  payment(
    title: 'Secure Payment Integration',
    shortTitle: 'Secure Payment',
    tagline: 'Everything together + live attack simulator',
    intro: 'Capstone: device binding, encrypted & signed payment, HMAC transport — then try to break it.',
    icon: Icons.account_balance_rounded,
    color: Color(0xFFFF7A59),
    tags: ['Capstone', 'Gateway', 'Red team'],
  ),
  appSecurity(
    title: 'App Security & Secure Storage',
    shortTitle: 'App Security',
    tagline: 'PIN, biometrics, app lock, root detection, pinning',
    intro: 'Protect the app itself: who can open it, what leaks from the screen, '
        'whether the device and the network can be trusted.',
    icon: Icons.security_rounded,
    color: Color(0xFF4FC3F7),
    tags: ['local_auth', 'Pinning', 'RASP'],
  );

  const LabModule({
    required this.title,
    required this.shortTitle,
    required this.tagline,
    required this.intro,
    required this.icon,
    required this.color,
    required this.tags,
  });

  final String title;
  final String shortTitle;
  final String tagline;
  final String intro;
  final IconData icon;
  final Color color;
  final List<String> tags;

  int get number => index + 1;
}
