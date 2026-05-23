import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class DetectorService {
  static ImageLabeler? _labeler;
  static bool _isLoaded = false;

  static Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      final options = ImageLabelerOptions(confidenceThreshold: 0.55);
      _labeler = ImageLabeler(options: options);
      _isLoaded = true;
      debugPrint('ML Kit Image Labeler ready.');
    } catch (e) {
      debugPrint('Labeler init error: $e');
      _isLoaded = false;
    }
  }

  static Future<String?> detectObject(String imagePath) async {
    if (!_isLoaded || _labeler == null) {
      await loadModel();
      if (!_isLoaded || _labeler == null) return null;
    }
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final labels = await _labeler!.processImage(inputImage);

      if (labels.isEmpty) return null;

      // Sort by confidence descending
      labels.sort((a, b) => b.confidence.compareTo(a.confidence));

      const skipLabels = {
        'still life', 'art', 'fashion', 'gesture', 'event',
        'photography', 'illustration', 'font', 'pattern',
        'organism', 'macro photography', 'close-up', 'sky',
        'light', 'darkness', 'black', 'white', 'color',
        'rectangle', 'circle', 'line', 'shape', 'design',
        'wood', 'metal', 'plastic', 'material', 'texture',
        'indoor', 'outdoor', 'room', 'floor', 'wall', 'ceiling',
      };

      for (final label in labels) {
        // v0.12.x uses .label not .text
        final name = label.label.toLowerCase();
        if (skipLabels.any((skip) => name.contains(skip))) continue;
        if (name.length < 3) continue;
        debugPrint('Detected: ${label.label} (${label.confidence.toStringAsFixed(2)})');
        return _cleanLabel(name);
      }

      // Fallback to top label
      return _cleanLabel(labels.first.label.toLowerCase());
    } catch (e) {
      debugPrint('Detection error: $e');
      return null;
    }
  }

  static String _cleanLabel(String label) {
    final words = label.trim().split(' ');
    if (words.length > 1) return words.last;
    return label;
  }

  static void dispose() {
    _labeler?.close();
    _labeler = null;
    _isLoaded = false;
  }
}