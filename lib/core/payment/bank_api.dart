import 'dart:typed_data';

import 'models.dart';

class HandshakeResponse {
  const HandshakeResponse({required this.serverPublicKey, required this.salt, required this.keyId});

  final Uint8List serverPublicKey;
  final Uint8List salt;
  final String keyId;
}

/// What the mobile app may call on the BANK. In production this is an
/// HTTPS client; [MockBankServer] implements it in-process for training.
///
/// Interface segregation: the app's payment SDK depends only on this, not on
/// merchant-side operations.
abstract interface class BankApi {
  Future<HandshakeResponse> handshake(List<int> clientPublicKey);
  Future<void> registerDevice(String deviceId, List<int> publicKey);
  Future<PaymentResult> processPayment(ApiRequest request);
}

/// What the MERCHANT BACKEND does: create orders and verify the gateway's
/// signature. Never implemented inside a real app (it needs the key secret).
abstract interface class MerchantApi {
  PaymentOrder createOrder({required int amountPaise, required String payee});
  bool verifyGatewaySignature(String orderId, String paymentId, String signature);
}
