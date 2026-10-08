/// A gateway order, modelled on Razorpay / Stripe "create order first" flows.
/// The amount is fixed SERVER-side so the app can't change what is charged.
class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.amountPaise,
    required this.currency,
    required this.payee,
    required this.receipt,
  });

  final String id;
  final int amountPaise; // integer minor units: never use double for money
  final String currency;
  final String payee;
  final String receipt;

  String get displayAmount {
    final rupees = amountPaise ~/ 100;
    final paise = (amountPaise % 100).toString().padLeft(2, '0');
    return '₹${_group(rupees)}.$paise';
  }

  static String _group(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final grouped = rest.replaceAllMapped(RegExp(r'\B(?=(\d{2})+(?!\d))'), (_) => ',');
    return '$grouped,$last3'; // Indian numbering: 12,34,567
  }
}

/// What travels over the wire. Body is JSON; headers carry the HMAC.
class ApiRequest {
  const ApiRequest({required this.method, required this.path, required this.headers, required this.body});

  final String method;
  final String path;
  final Map<String, String> headers;
  final String body;

  ApiRequest copyWith({Map<String, String>? headers, String? body}) =>
      ApiRequest(method: method, path: path, headers: headers ?? this.headers, body: body ?? this.body);
}

enum CheckStatus { passed, failed, skipped }

class SecurityCheck {
  const SecurityCheck(this.name, this.status, this.detail);

  final String name;
  final CheckStatus status;
  final String detail;
}

class PaymentResult {
  const PaymentResult({
    required this.success,
    required this.checks,
    this.paymentId,
    this.gatewaySignature,
    this.message,
  });

  final bool success;
  final List<SecurityCheck> checks;
  final String? paymentId;
  final String? gatewaySignature;
  final String? message;
}

/// Simulated attacks for the training "red team" panel.
enum AttackMode {
  none('No attack', 'Legitimate payment from a trusted device.'),
  tamperInTransit('MITM tampering', 'Attacker flips one byte of the encrypted body on the network.'),
  replay('Replay attack', 'Attacker captures a valid request and sends it again.'),
  staleRequest('Delayed request', 'Request is held back and released 10 minutes later.'),
  forgedDevice('Stolen session keys', 'Malware has the session AES + HMAC keys but not the device signing key.'),
  amountManipulation('Amount manipulation', 'Hooked app signs ₹1 against a ₹25,000 order.'),
  hmacTamper(
    'HMAC tampering',
    'Attacker edits the body and recomputes its SHA-256, but cannot re-sign without the HMAC key.',
  ),
  signatureTamper(
    'Amount changed after signing',
    'Malware multiplies the amount ×10 after the device signed it, before encryption.',
  );

  const AttackMode(this.label, this.description);

  final String label;
  final String description;
}
