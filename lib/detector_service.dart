import 'package:flutter/foundation.dart';

/// Stub version of DetectorService — ML Kit dependency temporarily
/// removed to unblock iOS Simulator testing (no arm64 simulator
/// support / Firebase version conflicts). Always returns null,
/// meaning "nothing detected." Camera/AR features should be tested
/// on a physical device, where the real ML Kit version will be used.
class DetectorService {
  static bool _isLoaded = false;

  static Future<void> loadModel() async {
    _isLoaded = true;
    debugPrint('DetectorService: stub mode (ML Kit disabled for simulator testing)');
  }

  static Future<String?> detectObject(String imagePath) async {
    if (!_isLoaded) {
      await loadModel();
    }
    debugPrint('DetectorService: stub mode, no detection performed');
    return null;
  }

  static void dispose() {
    _isLoaded = false;
  }
}