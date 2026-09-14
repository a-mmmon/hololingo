import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// ============================================================================
/// DETECTED OBJECT
/// ============================================================================
///
/// Contains the detected object's label, confidence and normalized bounding box.
///
/// Coordinates are normalized from 0.0 to 1.0:
///
/// left   = x start
/// top    = y start
/// right  = x end
/// bottom = y end
///
class DetectedObject {
  final String label;
  final double confidence;

  final double left;
  final double top;
  final double right;
  final double bottom;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;

  double get height => bottom - top;

  double get centerX => (left + right) / 2;

  double get centerY => (top + bottom) / 2;

  @override
  String toString() {
    return 'DetectedObject('
        'label: $label, '
        'confidence: $confidence, '
        'box: [$left, $top, $right, $bottom]'
        ')';
  }
}

/// ============================================================================
/// HOLO LINGO OBJECT DETECTOR
/// ============================================================================
///
/// Uses a custom-trained Ultralytics YOLO model ("best.tflite") trained on
/// 60 everyday-object classes (Hololingo-2 dataset).
///
/// Model format (confirmed by inspecting the .tflite file directly):
///   input:  [1, 3, 640, 640]  -> NCHW, RGB, float32, normalized 0..1
///   output: [1, 64, 8400]     -> 8400 candidate boxes x (4 box coords + 60 class scores)
///
/// This is NOT the SSD MobileNet 4-output format used previously
/// (locations/classes/scores/numDetections). YOLO packs everything into a
/// single tensor and does not run NMS internally, so we decode it manually
/// below. Since this service only ever needs the single best detection
/// (not a list), we skip full NMS and just take the highest-confidence
/// candidate across all anchors and classes — that's equivalent to NMS
/// when you only want the top-1 result.
///
/// Existing functionality:
///   detectObject()
///       -> returns String?
///
///   detectObjectDetails()
///       -> returns DetectedObject?
///
///   cropDetectedObject()
///       -> saves a cropped PNG around the detected object.
///
/// IMPORTANT:
/// This creates a bounding-box crop, NOT a true transparent background
/// removal. True background removal requires an instance-segmentation model.
///

class DetectorService {
  // Native iOS Vision foreground-segmentation bridge.
  static const MethodChannel _visionChannel = MethodChannel('hololingo/vision');

  static Interpreter? _interpreter;

  static bool _isLoaded = false;
  static bool _loadFailed = false;

  /// Model input is 640x640 (confirmed from the .tflite input shape).
  static const int _inputSize = 640;

  /// Output tensor is [1, 64, 8400]: 4 box values + 60 class scores.
  static const int _numClasses = 60;
  static const int _numAnchors = 8400;

  /// Minimum confidence required before the app accepts a detection.
  ///
  /// Very low-confidence predictions (for example 5% or 15%) are not
  /// reliable enough to be treated as real objects. Keeping this at 0.35
  /// prevents weak predictions from being passed to the capture flow.
  static const double _confidenceThreshold = 0.35;
  static const double _targetConfidenceThreshold = 0.12;

  /// Labels embedded in best.tflite's metadata.json, in class-index order.
  /// (Class index maps directly to this list — no offset, unlike the old
  /// SSD labelMap.txt which needed a +1 offset for a background entry.)
  static const List<String> _labels = [
    'Laptop',
    'USB',
    'apple',
    'backpack',
    'bamboo basket',
    'bench',
    'bicycle',
    'book',
    'boot',
    'bottle',
    'calculator',
    'calendar',
    'camera',
    'car',
    'cartain',
    'chair',
    'charger',
    'clock',
    'coffee mug',
    'control',
    'cup',
    'cushion',
    'desk',
    'dryer',
    'eyeglass',
    'fan',
    'flower',
    'flowerpot',
    'glass',
    'glove',
    'jacket',
    'jean',
    'key',
    'keyboard',
    'lamp',
    'makeup brush',
    'microwave',
    'monitor',
    'mouse',
    'office chair',
    'paper',
    'pen',
    'phone',
    'pillow',
    'plant',
    'rice cooker',
    'scissor',
    'shoe',
    'sock',
    'sofa',
    'spoon',
    'sticky note',
    'sunglass',
    'table',
    'tissue',
    'tissue box',
    'tooth brush',
    'umbrella',
    'washing machine',
    'watch',
  ];

  // ===========================================================================
  // LOAD MODEL
  // ===========================================================================

  static Future<void> loadModel() async {
    if (_isLoaded || _loadFailed) {
      return;
    }

    try {
      debugPrint(
        'DetectorService: loading model...',
      );

      _interpreter = await Interpreter.fromAsset(
        'assets/Models/best.tflite',
      );

      _isLoaded = true;

      debugPrint(
        'DetectorService: model loaded '
        '(${_labels.length} labels)',
      );

      debugPrint(
        'DetectorService: input size '
        '$_inputSize x $_inputSize',
      );
    } catch (e) {
      _loadFailed = true;

      debugPrint(
        'DetectorService: failed to load model: $e',
      );
    }
  }

  // ===========================================================================
  // SIMPLE OBJECT DETECTION
  // ===========================================================================
  //
  // KEEP THIS METHOD.
  //
  // Existing screens can continue doing:
  //
  // final detected = await DetectorService.detectObject(path);
  //
  // and receive:
  //
  // "bottle"
  // "chair"
  // "laptop"
  // etc.
  //

  static Future<String?> detectObject(
    String imagePath,
  ) async {
    final result = await detectObjectDetails(
      imagePath,
    );

    return result?.label;
  }

  // ===========================================================================
  // OBJECT DETECTION WITH BOUNDING BOX
  // ===========================================================================

  static Future<DetectedObject?> detectObjectDetails(
    String imagePath, {
    String? targetLabel,
  }) async {
    if (!_isLoaded && !_loadFailed) {
      await loadModel();
    }

    if (!_isLoaded || _interpreter == null) {
      debugPrint(
        'DetectorService: no model available.',
      );

      return null;
    }

    try {
      final file = File(imagePath);

      if (!await file.exists()) {
        debugPrint(
          'DetectorService: image does not exist: '
          '$imagePath',
        );

        return null;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        debugPrint(
          'DetectorService: image is empty.',
        );

        return null;
      }

      final original = img.decodeImage(bytes);

      if (original == null) {
        debugPrint(
          'DetectorService: could not decode image.',
        );

        return null;
      }

      debugPrint(
        'DetectorService: original image '
        '${original.width} x ${original.height}',
      );

      return _detectFromImage(
        original,
        targetLabel: targetLabel,
      );
    } catch (e) {
      debugPrint(
        'DetectorService: detection error: $e',
      );

      return null;
    }
  }

  // ===========================================================================
  // IOS VISION BACKGROUND REMOVAL
  // ===========================================================================

  /// Uses Apple's Vision foreground segmentation on iOS.
  ///
  /// Returns the path of a transparent PNG when successful.
  /// Returns null when Vision cannot create a cutout.
  static Future<String?> removeBackground(
    String imagePath, {
    double? centerX,
    double? centerY,
  }) async {
    try {
      if (!Platform.isIOS) {
        debugPrint(
          'DetectorService: Vision background removal is only '
          'available on iOS.',
        );
        return null;
      }

      final file = File(imagePath);

      if (!await file.exists()) {
        debugPrint(
          'DetectorService: image does not exist: $imagePath',
        );
        return null;
      }

      final outputPath = await _visionChannel.invokeMethod<String>(
        'removeBackground',
        <String, dynamic>{
          'imagePath': imagePath,
          if (centerX != null) 'centerX': centerX,
          if (centerY != null) 'centerY': centerY,
        },
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        debugPrint(
          'DetectorService: Vision returned no output path.',
        );
        return null;
      }

      final outputFile = File(outputPath);

      if (!await outputFile.exists()) {
        debugPrint(
          'DetectorService: Vision output does not exist: $outputPath',
        );
        return null;
      }

      debugPrint(
        'DetectorService: transparent cutout saved: $outputPath',
      );

      return outputPath;
    } on PlatformException catch (e) {
      debugPrint(
        'DetectorService: Vision error '
        '(${e.code}): ${e.message}',
      );
      return null;
    } catch (e) {
      debugPrint(
        'DetectorService: background removal error: $e',
      );
      return null;
    }
  }

  // ===========================================================================
  // CROP DETECTED OBJECT
  // ===========================================================================
  //
  // This creates a cropped image around the detected object.
  //
  // It does NOT remove the background yet.
  //
  // Later we replace this with segmentation to make the background
  // transparent.
  //

  static Future<String?> cropDetectedObject(
    String imagePath,
  ) async {
    try {
      final detected = await detectObjectDetails(
        imagePath,
      );

      if (detected == null) {
        return null;
      }

      final file = File(imagePath);

      if (!await file.exists()) {
        return null;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        return null;
      }

      final original = img.decodeImage(bytes);

      if (original == null) {
        return null;
      }

      // -----------------------------------------------------------------------
      // Convert normalized coordinates to actual image coordinates
      // -----------------------------------------------------------------------

      int left = (detected.left * original.width).round();

      int top = (detected.top * original.height).round();

      int right = (detected.right * original.width).round();

      int bottom = (detected.bottom * original.height).round();

      // -----------------------------------------------------------------------
      // Add a little padding around the object
      // -----------------------------------------------------------------------

      final paddingX = ((right - left) * 0.08).round();

      final paddingY = ((bottom - top) * 0.08).round();

      left -= paddingX;
      top -= paddingY;
      right += paddingX;
      bottom += paddingY;

      // -----------------------------------------------------------------------
      // Clamp to image boundaries
      // -----------------------------------------------------------------------

      left = left.clamp(
        0,
        original.width - 1,
      );

      top = top.clamp(
        0,
        original.height - 1,
      );

      right = right.clamp(
        left + 1,
        original.width,
      );

      bottom = bottom.clamp(
        top + 1,
        original.height,
      );

      final cropWidth = right - left;

      final cropHeight = bottom - top;

      if (cropWidth <= 1 || cropHeight <= 1) {
        debugPrint(
          'DetectorService: invalid crop size.',
        );

        return null;
      }

      // -----------------------------------------------------------------------
      // Crop
      // -----------------------------------------------------------------------

      final cropped = img.copyCrop(
        original,
        x: left,
        y: top,
        width: cropWidth,
        height: cropHeight,
      );

      // -----------------------------------------------------------------------
      // Save PNG
      // -----------------------------------------------------------------------

      final originalFile = File(imagePath);

      final directory = originalFile.parent.path;

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final outputPath = '$directory/hololingo_crop_$timestamp.png';

      final outputFile = File(
        outputPath,
      );

      await outputFile.writeAsBytes(
        img.encodePng(cropped),
      );

      debugPrint(
        'DetectorService: cropped object saved: '
        '$outputPath',
      );

      return outputPath;
    } catch (e) {
      debugPrint(
        'DetectorService: crop error: $e',
      );

      return null;
    }
  }

  // ===========================================================================
  // LIVE CAMERA DETECTION
  // ===========================================================================

  static Future<String?> detectCameraImage(
    CameraImage cameraImage,
  ) async {
    if (!_isLoaded && !_loadFailed) {
      await loadModel();
    }

    if (!_isLoaded || _interpreter == null) {
      debugPrint(
        'DetectorService: no model available.',
      );

      return null;
    }

    try {
      final converted = _cameraImageToImage(
        cameraImage,
      );

      if (converted == null) {
        return null;
      }

      final result = _detectFromImage(converted);

      return result?.label;
    } catch (e) {
      debugPrint(
        'DetectorService: live detection error: $e',
      );

      return null;
    }
  }

  // ===========================================================================
  // SAVE LIVE FRAME (silent — no shutter sound)
  // ===========================================================================
  //
  // Converts a CameraImage already in the preview stream into a JPEG file.
  // Used instead of controller.takePicture(), which triggers the OS
  // camera shutter sound.

  static Future<String?> saveCameraImage(
    CameraImage cameraImage,
  ) async {
    try {
      final converted = _cameraImageToImage(cameraImage);

      if (converted == null) {
        return null;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          '${Directory.systemTemp.path}/hololingo_frame_$timestamp.jpg';

      final outputFile = File(outputPath);

      await outputFile.writeAsBytes(
        img.encodeJpg(converted, quality: 90),
      );

      return outputPath;
    } catch (e) {
      debugPrint('DetectorService: saveCameraImage error: $e');
      return null;
    }
  }

  // ===========================================================================
  // SHARED DETECTION PIPELINE (letterbox -> inference -> decode)
  // ===========================================================================

  static DetectedObject? _detectFromImage(
    img.Image original, {
    String? targetLabel,
  }) {
    final interpreter = _interpreter;

    if (interpreter == null) {
      return null;
    }

    // -------------------------------------------------------------------------
    // Letterbox: resize preserving aspect ratio, pad the rest with gray.
    // This matches how Ultralytics preprocesses images for YOLO, so the
    // model sees images shaped the way it was trained on.
    // -------------------------------------------------------------------------

    final letterboxed = _letterbox(
      original,
      _inputSize,
    );

    // -------------------------------------------------------------------------
    // Build NCHW float32 input: [1, 3, 640, 640], RGB, normalized 0..1
    // -------------------------------------------------------------------------

    final input = _imageToYoloInput(
      letterboxed.image,
    );

    // -------------------------------------------------------------------------
    // Output buffer: [1, 64, 8400]
    // -------------------------------------------------------------------------

    final output = [
      List.generate(
        4 + _numClasses,
        (_) => List.filled(_numAnchors, 0.0),
      ),
    ];

    interpreter.run(input, output);

    final raw = output[0];

    // -------------------------------------------------------------------------
    // Decode: find the single highest-confidence (box, class) pair across
    // all 8400 anchors. This is equivalent to NMS when only the top-1
    // detection is needed.
    // -------------------------------------------------------------------------

    final normalizedTarget = _normalizeLabel(targetLabel);

    double bestScore = 0.0;
    int bestClass = -1;
    double bestCx = 0, bestCy = 0, bestW = 0, bestH = 0;

    for (int a = 0; a < _numAnchors; a++) {
      // Class scores start at row index 4.
      for (int c = 0; c < _numClasses; c++) {
        final score = raw[4 + c][a];
        final modelLabel = _labels[c];

        if (normalizedTarget != null &&
            !_targetMatchesModelLabel(normalizedTarget, modelLabel)) {
          continue;
        }

        if (score > bestScore) {
          bestScore = score;
          bestClass = c;
          bestCx = raw[0][a];
          bestCy = raw[1][a];
          bestW = raw[2][a];
          bestH = raw[3][a];
        }
      }
    }

    final minimumScore = normalizedTarget == null
        ? _confidenceThreshold
        : _targetConfidenceThreshold;

    if (bestClass < 0 || bestScore < minimumScore) {
      if (normalizedTarget != null) {
        debugPrint(
          'DetectorService: target "$normalizedTarget" was not detected reliably '
          '(best target score=${bestScore.toStringAsFixed(2)}, '
          'threshold=$minimumScore).',
        );
      } else {
        debugPrint(
          'DetectorService: best detection '
          '(score=${bestScore.toStringAsFixed(2)}) is below threshold '
          '$_confidenceThreshold or nothing detected.',
        );
      }

      return null;
    }

    final label = _labels[bestClass];

    // -------------------------------------------------------------------------
    // IMPORTANT: this Ultralytics TFLite export contains the NormalizeCoords
    // layer, so the four box values are NORMALIZED to 0..1, not pixel values.
    // Convert them back to the 640x640 letterboxed pixel space first, then
    // undo the letterbox padding/scale to map them to the original image.
    // Treating these values as pixels makes boxes almost zero-sized, which was
    // the reason the log showed boxes such as [0.000, 0.000, 0.000, 0.001].
    // -------------------------------------------------------------------------

    final cx = bestCx * _inputSize;
    final cy = bestCy * _inputSize;
    final w = bestW * _inputSize;
    final h = bestH * _inputSize;

    double left = cx - w / 2;
    double top = cy - h / 2;
    double right = cx + w / 2;
    double bottom = cy + h / 2;

    left = (left - letterboxed.padLeft) / letterboxed.scale;
    top = (top - letterboxed.padTop) / letterboxed.scale;
    right = (right - letterboxed.padLeft) / letterboxed.scale;
    bottom = (bottom - letterboxed.padTop) / letterboxed.scale;

    left = left.clamp(0.0, original.width.toDouble());
    top = top.clamp(0.0, original.height.toDouble());
    right = right.clamp(0.0, original.width.toDouble());
    bottom = bottom.clamp(0.0, original.height.toDouble());

    final normalizedLeft = left / original.width;
    final normalizedTop = top / original.height;
    final normalizedRight = right / original.width;
    final normalizedBottom = bottom / original.height;

    debugPrint(
      'DetectorService: detected "$label" '
      '(${(bestScore * 100).toStringAsFixed(1)}%) '
      'box=[${normalizedLeft.toStringAsFixed(3)}, '
      '${normalizedTop.toStringAsFixed(3)}, '
      '${normalizedRight.toStringAsFixed(3)}, '
      '${normalizedBottom.toStringAsFixed(3)}]',
    );

    return DetectedObject(
      label: label,
      confidence: bestScore,
      left: normalizedLeft,
      top: normalizedTop,
      right: normalizedRight,
      bottom: normalizedBottom,
    );
  }

  // ===========================================================================
  // LETTERBOX RESIZE
  // ===========================================================================
  //
  // Resizes the image to fit within size x size while preserving aspect
  // ratio, then pads the remaining space with gray (114,114,114) — matching
  // Ultralytics' default preprocessing so boxes decode correctly.
  //

  static _LetterboxResult _letterbox(
    img.Image src,
    int size,
  ) {
    final scale = (size / src.width < size / src.height)
        ? size / src.width
        : size / src.height;

    final newWidth = (src.width * scale).round();
    final newHeight = (src.height * scale).round();

    final resized = img.copyResize(
      src,
      width: newWidth,
      height: newHeight,
    );

    final padLeft = ((size - newWidth) / 2).floor();
    final padTop = ((size - newHeight) / 2).floor();

    final canvas = img.Image(
      width: size,
      height: size,
    );

    img.fill(
      canvas,
      color: img.ColorRgb8(114, 114, 114),
    );

    img.compositeImage(
      canvas,
      resized,
      dstX: padLeft,
      dstY: padTop,
    );

    return _LetterboxResult(
      image: canvas,
      scale: scale.toDouble(),
      padLeft: padLeft.toDouble(),
      padTop: padTop.toDouble(),
    );
  }

  // ===========================================================================
  // IMAGE -> YOLO INPUT (NCHW, RGB, normalized 0..1)
  // ===========================================================================

  static List<List<List<List<double>>>> _imageToYoloInput(
    img.Image image,
  ) {
    // Shape: [1, 3, height, width]
    final input = List.generate(
      1,
      (_) => List.generate(
        3,
        (channel) => List.generate(
          _inputSize,
          (y) => List.generate(
            _inputSize,
            (x) {
              final pixel = image.getPixel(x, y);

              switch (channel) {
                case 0:
                  return pixel.r / 255.0;
                case 1:
                  return pixel.g / 255.0;
                default:
                  return pixel.b / 255.0;
              }
            },
          ),
        ),
      ),
    );

    return input;
  }

  // ===========================================================================
  // CAMERA IMAGE CONVERSION
  // ===========================================================================

  static img.Image? _cameraImageToImage(
    CameraImage cameraImage,
  ) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    if (width <= 0 || height <= 0) {
      return null;
    }

    // -------------------------------------------------------------------------
    // BGRA8888
    // -------------------------------------------------------------------------

    if (cameraImage.planes.length == 1) {
      final plane = cameraImage.planes.first;

      final bytes = plane.bytes;

      if (bytes.isEmpty) {
        return null;
      }

      final bytesPerRow = plane.bytesPerRow > 0 ? plane.bytesPerRow : width * 4;

      final output = img.Image(
        width: width,
        height: height,
      );

      for (int y = 0; y < height; y++) {
        final rowStart = y * bytesPerRow;

        for (int x = 0; x < width; x++) {
          final index = rowStart + (x * 4);

          if (index + 3 >= bytes.length) {
            continue;
          }

          final b = bytes[index];
          final g = bytes[index + 1];
          final r = bytes[index + 2];

          output.setPixelRgb(
            x,
            y,
            r,
            g,
            b,
          );
        }
      }

      return output;
    }

    // -------------------------------------------------------------------------
    // YUV420
    // -------------------------------------------------------------------------

    if (cameraImage.planes.length >= 3) {
      return _convertYuv420ToRgb(
        cameraImage,
      );
    }

    return null;
  }

  // ===========================================================================
  // YUV420 → RGB
  // ===========================================================================

  static img.Image _convertYuv420ToRgb(
    CameraImage cameraImage,
  ) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final output = img.Image(
      width: width,
      height: height,
    );

    final yPlane = cameraImage.planes[0];

    final uPlane = cameraImage.planes[1];

    final vPlane = cameraImage.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;

    final uRowStride = uPlane.bytesPerRow;

    final vRowStride = vPlane.bytesPerRow;

    final uPixelStride = uPlane.bytesPerPixel ?? 1;

    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      final yRow = y * yRowStride;

      final uvRow = y ~/ 2;

      for (int x = 0; x < width; x++) {
        final yIndex = yRow + x;

        if (yIndex >= yBytes.length) {
          continue;
        }

        final uvColumn = x ~/ 2;

        final uIndex = uvRow * uRowStride + uvColumn * uPixelStride;

        final vIndex = uvRow * vRowStride + uvColumn * vPixelStride;

        if (uIndex >= uBytes.length || vIndex >= vBytes.length) {
          continue;
        }

        final yValue = yBytes[yIndex].toDouble();

        final uValue = uBytes[uIndex].toDouble() - 128.0;

        final vValue = vBytes[vIndex].toDouble() - 128.0;

        double r = yValue + 1.402 * vValue;

        double g = yValue - 0.344136 * uValue - 0.714136 * vValue;

        double b = yValue + 1.772 * uValue;

        r = r.clamp(
          0,
          255,
        );

        g = g.clamp(
          0,
          255,
        );

        b = b.clamp(
          0,
          255,
        );

        output.setPixelRgb(
          x,
          y,
          r.round(),
          g.round(),
          b.round(),
        );
      }
    }

    return output;
  }

  static String? _normalizeLabel(String? value) {
    if (value == null) return null;
    final normalized = value
        .toLowerCase()
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalized.isEmpty ? null : normalized;
  }

  static bool _targetMatchesModelLabel(
    String target,
    String modelLabel,
  ) {
    final model = _normalizeLabel(modelLabel);
    if (model == null) return false;
    if (target == model) return true;

    switch (target) {
      case 'laptop':
        return model == 'laptop' || model == 'notebook';
      case 'cell phone':
      case 'phone':
        return model == 'phone' ||
            model == 'cell phone' ||
            model == 'cellphone' ||
            model == 'mobile phone' ||
            model == 'mobile';
      case 'backpack':
        return model == 'backpack' || model == 'bag';
      case 'bicycle':
        return model == 'bicycle' || model == 'bike';
      case 'scissors':
      case 'scissor':
        return model == 'scissor' || model == 'scissors';
      case 'coffee mug':
        return model == 'coffee mug' || model == 'mug';
      case 'toothbrush':
      case 'tooth brush':
        return model == 'tooth brush' || model == 'toothbrush';
      default:
        return false;
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  static void dispose() {
    try {
      _interpreter?.close();
    } catch (e) {
      debugPrint(
        'DetectorService dispose error: $e',
      );
    }

    _interpreter = null;

    _isLoaded = false;
    _loadFailed = false;
  }
}

// ============================================================================
// LETTERBOX RESULT
// ============================================================================

class _LetterboxResult {
  final img.Image image;
  final double scale;
  final double padLeft;
  final double padTop;

  const _LetterboxResult({
    required this.image,
    required this.scale,
    required this.padLeft,
    required this.padTop,
  });
}
