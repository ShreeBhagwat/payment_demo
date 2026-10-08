import 'package:safe_device/safe_device.dart';
import 'package:safe_device/safe_device_config.dart';

enum RiskLevel { ok, warn, critical }

/// What the app does when the device looks compromised.
enum IntegrityPolicy {
  allow('Allow', 'Log only'),
  warn('Warn', 'Show a risk banner, allow payments'),
  block('Block', 'Refuse payments on critical risk');

  const IntegrityPolicy(this.label, this.description);

  final String label;
  final String description;
}

class IntegrityCheck {
  const IntegrityCheck(this.name, this.flagged, this.level, this.why);

  final String name;
  final bool flagged;
  final RiskLevel level; // severity if flagged
  final String why;
}

class IntegrityReport {
  const IntegrityReport(this.checks, this.checkedAt);

  final List<IntegrityCheck> checks;
  final DateTime checkedAt;

  RiskLevel get risk {
    final flagged = checks.where((c) => c.flagged).map((c) => c.level);
    if (flagged.contains(RiskLevel.critical)) return RiskLevel.critical;
    if (flagged.contains(RiskLevel.warn)) return RiskLevel.warn;
    return RiskLevel.ok;
  }

  /// Policy decision kept next to the data it judges (single responsibility
  /// for "is this device acceptable"), so every caller decides the same way.
  String? blockReason(IntegrityPolicy policy) => policy == IntegrityPolicy.block && risk == RiskLevel.critical
      ? 'Payments are disabled on rooted / jailbroken devices.'
      : null;
}

/// Raw platform signals. Interface so the report logic is unit-testable and
/// the vendor (safe_device, freeRASP, …) can be swapped.
abstract interface class IntegrityProbe {
  Future<bool> isCompromised(); // rooted / jailbroken
  Future<bool> isRealDevice();
  Future<bool> isDeveloperModeOn();
  Future<bool> isUsbDebuggingOn();
  Future<bool> isOnExternalStorage();
}

class SafeDeviceProbe implements IntegrityProbe {
  SafeDeviceProbe() {
    // Mock-location detection needs the location permission; banks that
    // geo-fence transactions would enable it.
    if (!SafeDevice.isInitiated) SafeDevice.init(const SafeDeviceConfig(mockLocationCheckEnabled: false));
  }

  @override
  Future<bool> isCompromised() => _safe(() => SafeDevice.isJailBroken);
  @override
  Future<bool> isRealDevice() => _safe(() => SafeDevice.isRealDevice, fallback: true);
  @override
  Future<bool> isDeveloperModeOn() => _safe(() => SafeDevice.isDevelopmentModeEnable);
  @override
  Future<bool> isUsbDebuggingOn() => _safe(() => SafeDevice.isUsbDebuggingEnabled);
  @override
  Future<bool> isOnExternalStorage() => _safe(() => SafeDevice.isOnExternalStorage);

  static Future<bool> _safe(Future<bool> Function() f, {bool fallback = false}) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }
}

/// Turns probe signals into a risk report.
///
/// Client-side checks are a speed bump, not a wall: Frida / Magisk DenyList
/// can make them return false. Treat the result as one risk signal, backed
/// by SERVER-verified Play Integrity / App Attest tokens.
class DeviceIntegrityService {
  const DeviceIntegrityService(this._probe, {required this.isAndroid, required this.isDebugBuild});

  final IntegrityProbe _probe;
  final bool isAndroid;
  final bool isDebugBuild;

  Future<IntegrityReport> check() async => IntegrityReport([
        IntegrityCheck(
          isAndroid ? 'Rooted (su, Magisk, test-keys)' : 'Jailbroken (Cydia, Sileo, sandbox escape)',
          await _probe.isCompromised(),
          RiskLevel.critical,
          'Other apps can read Keystore-backed data and hook this app at runtime.',
        ),
        IntegrityCheck(
          'Emulator / simulator',
          !await _probe.isRealDevice(),
          RiskLevel.warn,
          'Bots and automated fraud farms run on emulators.',
        ),
        if (isAndroid) ...[
          IntegrityCheck(
            'Developer options on',
            await _probe.isDeveloperModeOn(),
            RiskLevel.warn,
            'Enables mock locations and debugging tools.',
          ),
          IntegrityCheck(
            'USB debugging on',
            await _probe.isUsbDebuggingOn(),
            RiskLevel.warn,
            'adb can inspect the app and inject input.',
          ),
          IntegrityCheck(
            'Installed on external storage',
            await _probe.isOnExternalStorage(),
            RiskLevel.warn,
            'The APK and data on SD cards are easier to tamper with.',
          ),
        ],
        IntegrityCheck(
          'Debug build',
          isDebugBuild,
          RiskLevel.warn,
          'Release builds should be obfuscated (--obfuscate --split-debug-info).',
        ),
      ], DateTime.now());
}
