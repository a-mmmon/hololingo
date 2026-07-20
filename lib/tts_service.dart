import 'package:flutter/foundation.dart';

/// Stub version of TtsService — flutter_tts temporarily removed to
/// unblock iOS Simulator testing (no arm64 simulator binary support).
/// All methods are no-ops. Test actual speech/pronunciation on a
/// physical device, where the real flutter_tts plugin will be used.
class TtsService {
  Future<void> setLanguage(String language) async {
    debugPrint('TtsService (stub): setLanguage($language)');
  }

  Future<void> setSpeechRate(double rate) async {
    debugPrint('TtsService (stub): setSpeechRate($rate)');
  }

  Future<void> speak(String text) async {
    debugPrint('TtsService (stub): speak("$text")');
  }

  Future<void> stop() async {
    debugPrint('TtsService (stub): stop()');
  }
}