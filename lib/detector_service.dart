import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class DetectorService {
  static ObjectDetector? _detector;
  static bool _isLoaded = false;

  static Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      final options = ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: false,
      );
      _detector = ObjectDetector(options: options);
      _isLoaded = true;
      print('ML Kit detector loaded!');
    } catch (e) {
      // FIX: Print full error so it shows in flutter logs
      print('Error loading detector: $e');
      _isLoaded = false;
    }
  }

  static Future<String?> detectObject(String imagePath) async {
    // FIX: Auto-reload if somehow not loaded
    if (!_isLoaded || _detector == null) {
      await loadModel();
      if (!_isLoaded || _detector == null) return null;
    }
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final objects = await _detector!.processImage(inputImage);
      if (objects.isEmpty) return null;
      final best = objects.first;
      if (best.labels.isEmpty) return null;
      best.labels.sort((a, b) => b.confidence.compareTo(a.confidence));
      final label = best.labels.first;
      if (label.confidence > 0.5) {
        return label.text.toLowerCase();
      }
      return null;
    } catch (e) {
      print('Detection error: $e');
      return null;
    }
  }

  static void dispose() {
    _detector?.close();
    _detector = null;
    // FIX: Reset flag so loadModel() works again if CameraTab is recreated
    _isLoaded = false;
  }
}