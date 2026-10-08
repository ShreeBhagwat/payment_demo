import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/aes_gcm_service.dart';
import '../core/crypto/hmac_service.dart';
import '../core/crypto/key_exchange_service.dart';
import '../core/crypto/signature_service.dart';
import '../core/payment/bank_api.dart';
import '../core/payment/mock_bank_server.dart';
import '../core/payment/secure_payment_client.dart';
import '../core/security/biometric_service.dart';
import '../core/security/certificate_pinning.dart';
import '../core/security/device_integrity.dart';
import '../core/security/pin_service.dart';
import '../core/security/screen_protector.dart';
import '../core/storage/secure_vault.dart';
import '../core/utils/clock.dart';

// Composition root: the ONLY place concrete implementations are chosen.
// Everything else depends on these providers (and the interfaces they
// expose), so tests and future backends swap implementations with
// `ProviderScope(overrides: [...])` instead of editing feature code.

// ------------------------------------------------------------ platform

final clockProvider = Provider<Clock>((ref) => DateTime.now);

final keyValueStoreProvider = Provider<KeyValueStore>((ref) => SecureStorageStore());

final secureVaultProvider = Provider<SecureVault>((ref) => SecureVault(ref.watch(keyValueStoreProvider)));

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>((ref) => LocalAuthBiometrics());

final screenProtectorProvider = Provider<ScreenProtector>((ref) => NoScreenshotProtector());

final integrityProbeProvider = Provider<IntegrityProbe>((ref) => SafeDeviceProbe());

final certificateInspectorProvider = Provider<CertificateInspector>((ref) => const TlsCertificateInspector());

// -------------------------------------------------------------- crypto

final hmacServiceProvider = Provider<HmacService>((ref) => const HmacService());

final aesGcmServiceProvider = Provider<AesGcmService>((ref) => AesGcmService());

final signatureServiceProvider = Provider<SignatureService>((ref) => SignatureService());

final keyExchangeServiceProvider = Provider<KeyExchangeService>((ref) => KeyExchangeService());

// ------------------------------------------------------------ security

/// PBKDF2 work factor for the app PIN. Tests override with a small value.
final pinIterationsProvider = Provider<int>((ref) => 100000);

final pinServiceProvider = Provider<PinService>(
  (ref) => PinService(
    ref.watch(keyValueStoreProvider),
    iterations: ref.watch(pinIterationsProvider),
    clock: ref.watch(clockProvider),
  ),
);

final deviceIntegrityServiceProvider = Provider<DeviceIntegrityService>(
  (ref) => DeviceIntegrityService(
    ref.watch(integrityProbeProvider),
    isAndroid: !kIsWeb && Platform.isAndroid,
    isDebugBuild: kDebugMode,
  ),
);

// ------------------------------------------------------------- payment

/// One in-process "bank + merchant backend". Exposed below through two
/// narrow interfaces (interface segregation).
final mockBankServerProvider = Provider<MockBankServer>((ref) => MockBankServer(clock: ref.watch(clockProvider)));

final bankApiProvider = Provider<BankApi>((ref) => ref.watch(mockBankServerProvider));

final merchantApiProvider = Provider<MerchantApi>((ref) => ref.watch(mockBankServerProvider));

final paymentClientProvider = Provider<SecurePaymentClient>(
  (ref) => SecurePaymentClient(
    bank: ref.watch(bankApiProvider),
    merchant: ref.watch(merchantApiProvider),
    vault: ref.watch(secureVaultProvider),
    hmac: ref.watch(hmacServiceProvider),
    aes: ref.watch(aesGcmServiceProvider),
    signatures: ref.watch(signatureServiceProvider),
    keyExchange: ref.watch(keyExchangeServiceProvider),
    clock: ref.watch(clockProvider),
  ),
);

// --------------------------------------------------------- cross-cutting

/// Bumped whenever stored credentials are wiped wholesale (e.g. "Forgot
/// PIN"). Controllers that cache vault-derived state `ref.watch` it and
/// rebuild, without the wiping code knowing who they are.
final vaultGenerationProvider = NotifierProvider<VaultGeneration, int>(VaultGeneration.new);

class VaultGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Emits once per second while someone listens (countdowns, lockout timers).
final secondTickerProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 1), (_) => ref.read(clockProvider)()),
);
