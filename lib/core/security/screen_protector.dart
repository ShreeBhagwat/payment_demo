import 'package:no_screenshot/no_screenshot.dart';

enum CaptureEvent { screenshot, recording }

/// Platform capture protection, behind an interface so state management and
/// tests don't depend on the plugin.
///
///  * Android: FLAG_SECURE → screenshots, recordings and the app-switcher
///    thumbnail come out black.
///  * iOS: there is no public "block screenshot" API. The plugin renders the
///    app inside a secure layer so captures are blank, and DETECTS
///    screenshots and recordings (UIScreen.isCaptured).
abstract interface class ScreenProtector {
  Future<void> setProtected(bool on);
  Stream<CaptureEvent> events();
}

class NoScreenshotProtector implements ScreenProtector {
  final NoScreenshot _plugin = NoScreenshot.instance;

  @override
  Future<void> setProtected(bool on) async {
    try {
      on ? await _plugin.screenshotOff() : await _plugin.screenshotOn();
    } catch (_) {
      // Unsupported platform: protection is best-effort.
    }
  }

  @override
  Stream<CaptureEvent> events() async* {
    try {
      await _plugin.startScreenshotListening();
      await _plugin.startScreenRecordingListening();
    } catch (_) {
      return;
    }
    await for (final s in _plugin.screenshotStream) {
      if (s.wasScreenshotTaken) yield CaptureEvent.screenshot;
      if (s.isScreenRecording) yield CaptureEvent.recording;
    }
  }
}
