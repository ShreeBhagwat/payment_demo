import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../utils/bytes.dart';

/// Summary of a server certificate for the pinning lab.
class CertInfo {
  const CertInfo({
    required this.subject,
    required this.issuer,
    required this.validUntil,
    required this.spkiPin,
    required this.certSha256,
  });

  final String subject;
  final String issuer;
  final DateTime validUntil;
  final String spkiPin; // base64(SHA-256(SubjectPublicKeyInfo))
  final String certSha256; // hex SHA-256 of the whole DER cert
}

class PinningException implements Exception {
  const PinningException(this.host, this.presentedPin);

  final String host;
  final String presentedPin;

  @override
  String toString() => 'Certificate pin mismatch for $host (presented $presentedPin)';
}

/// Certificate pinning: trust only specific server keys, not "any cert any
/// CA signs". Defeats MITM through a rogue/compromised CA or a proxy CA
/// (Burp, Charles) installed on the device.
///
/// We pin the SPKI (public key) hash, not the whole certificate:
/// certificates are re-issued every few months, but the key can be kept.
/// Always ship at least one BACKUP pin (a spare key held offline) or a key
/// rotation will lock every installed app out of the API.
abstract final class CertificatePinning {
  /// SHA-256 of the DER-encoded SubjectPublicKeyInfo, base64. Same value as:
  ///   openssl s_client -connect host:443 </dev/null | openssl x509 -pubkey -noout \
  ///     | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
  static String spkiPin(List<int> certDer) =>
      Bytes.toBase64(c.sha256.convert(extractSpki(Uint8List.fromList(certDer))).bytes);

  /// Minimal DER walk: Certificate → tbsCertificate → subjectPublicKeyInfo.
  ///
  ///   Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signature }
  ///   TBSCertificate ::= SEQUENCE { [0] version OPTIONAL, serialNumber,
  ///       signature, issuer, validity, subject, subjectPublicKeyInfo, … }
  static Uint8List extractSpki(Uint8List der) {
    final cert = _readTlv(der, 0);
    final tbs = _readTlv(der, cert.contentStart);
    var pos = tbs.contentStart;
    var field = _readTlv(der, pos);
    if (field.tag == 0xA0) {
      pos = field.end; // skip explicit [0] version
      field = _readTlv(der, pos);
    }
    // serial, signatureAlg, issuer, validity, subject → then SPKI
    for (var i = 0; i < 5; i++) {
      pos = _readTlv(der, pos).end;
    }
    final spki = _readTlv(der, pos);
    if (spki.tag != 0x30) throw const FormatException('SubjectPublicKeyInfo not found');
    return Uint8List.sublistView(der, spki.start, spki.end);
  }
}

/// Reads a server's leaf certificate. Interface so the pinning lab can be
/// tested without the network.
abstract interface class CertificateInspector {
  Future<CertInfo> inspect(String host, {int port});
}

/// Opens a TLS connection and reports the leaf certificate, used to
/// discover pins in the lab. In production, pins come from your security
/// team, never from a live connection (that is "trust on first use").
class TlsCertificateInspector implements CertificateInspector {
  const TlsCertificateInspector();

  @override
  Future<CertInfo> inspect(String host, {int port = 443}) async {
    final socket = await SecureSocket.connect(host, port, timeout: const Duration(seconds: 8));
    try {
      final cert = socket.peerCertificate!;
      return CertInfo(
        subject: cert.subject,
        issuer: cert.issuer,
        validUntil: cert.endValidity,
        spkiPin: CertificatePinning.spkiPin(cert.der),
        certSha256: Bytes.toHex(c.sha256.convert(cert.der).bytes),
      );
    } finally {
      socket.destroy();
    }
  }
}

/// Builds Dio clients that reject any connection whose leaf SPKI isn't pinned.
abstract final class PinnedDio {
  /// `validateCertificate` runs AFTER normal chain validation succeeds, so
  /// the certificate must be valid AND match a pin.
  static Dio create({
    required Map<String, Set<String>> pinsByHost,
    void Function(String host, String presentedPin)? onMismatch,
  }) {
    final dio = Dio(
      BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        // Never let invalid certs through, even in debug.
        ..badCertificateCallback = (cert, host, port) => false,
      validateCertificate: (cert, host, port) {
        if (cert == null) return false;
        final presented = CertificatePinning.spkiPin(cert.der);
        final ok = pinsByHost[host]?.contains(presented) ?? false;
        if (!ok) onMismatch?.call(host, presented);
        return ok;
      },
    );
    return dio;
  }
}

class _Tlv {
  const _Tlv(this.tag, this.start, this.contentStart, this.end);

  final int tag;
  final int start;
  final int contentStart;
  final int end;
}

_Tlv _readTlv(Uint8List b, int pos) {
  final tag = b[pos];
  final lenByte = b[pos + 1];
  var p = pos + 2;
  var len = 0;
  if (lenByte < 0x80) {
    len = lenByte;
  } else {
    final n = lenByte & 0x7F;
    if (n == 0 || n > 4) throw const FormatException('Unsupported DER length');
    for (var i = 0; i < n; i++) {
      len = (len << 8) | b[p++];
    }
  }
  final end = p + len;
  if (end > b.length) throw const FormatException('Truncated DER');
  return _Tlv(tag, pos, p, end);
}
