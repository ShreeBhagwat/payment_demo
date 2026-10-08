import 'package:flutter/material.dart';

import '../features/app_security/app_security_lab_screen.dart';
import '../features/encryption/encryption_lab_screen.dart';
import '../features/hmac/hmac_lab_screen.dart';
import '../features/payment/payment_lab_screen.dart';
import '../features/signature/signature_lab_screen.dart';
import '../features/storage/storage_lab_screen.dart';
import 'lab_module.dart';

/// The one place that maps a module to its screen. The exhaustive switch
/// makes the compiler flag any new [LabModule] that has no screen yet.
Widget screenFor(LabModule module) => switch (module) {
      LabModule.hmac => const HmacLabScreen(),
      LabModule.storage => const StorageLabScreen(),
      LabModule.encryption => const EncryptionLabScreen(),
      LabModule.signature => const SignatureLabScreen(),
      LabModule.payment => const PaymentLabScreen(),
      LabModule.appSecurity => const AppSecurityLabScreen(),
    };

void openModule(BuildContext context, LabModule module) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screenFor(module)));
