import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'detector_service.dart';
import 'dictionary_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'topics_data.dart';

/// Result returned to TopicWordGridScreen after a capture attempt.
class TopicCaptureResult {
  final bool success;
  final String? imagePath;
  final String? detectedWord;

  const TopicCaptureResult({
    required this.success,
    this.imagePath,
    this.detectedWord,
  });
}

class TopicCaptureScreen extends StatefulWidget {
  final TopicWord word;
  final Color topicColor;

  const TopicCaptureScreen({
    super.key,
    required this.word,
    required this.topicColor,
  });

  @override
  State<TopicCaptureScreen> createState() => _TopicCaptureScreenState();
}

class _TopicCaptureScreenState extends State<TopicCaptureScreen> {
  CameraController? _controller;

  bool _initializing = true;
  bool _capturing = false;

  String? _errorMessage;

  /// Original camera photo.
  String? _originalImagePath;

  /// Processed object image. On iOS this should be a transparent cutout.
  String? _capturedImagePath;

  String? _detectedWord;
  double? _detectedConfidence;

  String _phonetic = '';
  String _definition = '';
  String _example = '';
  bool _loadingDefinition = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception(
          'No camera was found on this device.',
        );
      }

      CameraDescription selectedCamera = cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      try {
        await controller.lockCaptureOrientation(
          DeviceOrientation.portraitUp,
        );
      } catch (e) {
        debugPrint(
          'TopicCaptureScreen orientation lock error: $e',
        );
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint(
        'TopicCaptureScreen camera error: $e',
      );

      if (!mounted) return;

      setState(() {
        _initializing = false;
        _errorMessage =
            'Could not open the camera.\n\n$e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _tts.stop();
    super.dispose();
  }

  void _goBack() {
    if (_capturing) return;
    Navigator.of(context).pop();
  }

  Future<void> _capture() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing) {
      return;
    }

    setState(() {
      _capturing = true;
      _errorMessage = null;
    });

    try {
      // ---------------------------------------------------------------
      // 1. Take the photo
      // ---------------------------------------------------------------
      final photo = await controller.takePicture();

      // ---------------------------------------------------------------
      // 2. Detect the object
      // ---------------------------------------------------------------
      final detectedDetails =
          await DetectorService.detectObjectDetails(
        photo.path,
        targetLabel: widget.word.word,
      );

      // A capture is only valid when the detector produces a reliable
      // detection. DetectorService filters low-confidence predictions.
      // Do NOT fall back to the target word when nothing is detected,
      // because that would make an unrelated object look correct.
      if (detectedDetails == null) {
        if (!mounted) return;

        setState(() {
          _capturing = false;
          _errorMessage =
              'No object was detected clearly.\\n\\n'
              'Place the ${widget.word.word} inside the frame, '
              'make sure it is clearly visible, and try again.';
        });
        return;
      }

      final detected = detectedDetails.label;
      final centerX = detectedDetails.centerX;
      final centerY = detectedDetails.centerY;

      debugPrint(
        'Detected object: $detected '
        '(${(detectedDetails.confidence * 100).toStringAsFixed(1)}%)',
      );

      // ---------------------------------------------------------------
      // 3. Remove the background with native iOS Vision
      // ---------------------------------------------------------------
      String? processedPath;

      try {
        processedPath =
            await DetectorService.removeBackground(
          photo.path,
          centerX: centerX,
          centerY: centerY,
        );

        debugPrint(
          'Vision cutout saved at: $processedPath',
        );
      } catch (e) {
        debugPrint(
          'Vision background removal failed: $e',
        );
      }

      // If Vision cannot create a transparent cutout, keep the captured
      // photo so the valid detection can still be reviewed.
      processedPath ??= photo.path;

      if (!mounted) return;

      setState(() {
        _originalImagePath = photo.path;
        _capturedImagePath = processedPath;
        _detectedWord = detected;
        _detectedConfidence = detectedDetails.confidence;
        _capturing = false;
      });

      await _loadDefinition();
    } catch (e) {
      debugPrint(
        'TopicCaptureScreen capture error: $e',
      );

      if (!mounted) return;

      setState(() {
        _capturing = false;
        _errorMessage =
            'Could not capture the photo.\n\n$e';
      });
    }
  }

  Future<void> _loadDefinition() async {
    final detected = _detectedWord;
    if (detected == null || detected.trim().isEmpty) return;

    setState(() => _loadingDefinition = true);

    try {
      final lookupWord = widget.word.word.trim().isEmpty
          ? detected
          : widget.word.word;
      final info = await DictionaryService.getWordInfo(lookupWord);

      if (!mounted) return;
      setState(() {
        _phonetic = info['phonetic'] ?? '';
        _definition = info['definition'] ?? '';
        _example = info['example'] ?? '';
        _loadingDefinition = false;
      });
    } catch (e) {
      debugPrint('TopicCapture definition error: $e');
      if (!mounted) return;
      setState(() => _loadingDefinition = false);
    }
  }

  Future<void> _listen() async {
    final word = widget.word.word.trim();
    if (word.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(word);
    } catch (e) {
      debugPrint('TopicCapture TTS error: $e');
    }
  }

  void _retake() {
    setState(() {
      _originalImagePath = null;
      _capturedImagePath = null;
      _detectedWord = null;
      _detectedConfidence = null;
      _phonetic = '';
      _definition = '';
      _example = '';
      _loadingDefinition = false;
      _errorMessage = null;
    });
  }

  String? _normalize(String? value) {
    if (value == null) return null;

    final result = value
        .toLowerCase()
        .trim()
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    if (result.isEmpty) {
      return null;
    }

    return result.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  bool _isCorrectObject() {
    final detected = _normalize(_detectedWord);
    final expected = _normalize(widget.word.word);

    if (detected == null || expected == null) {
      return false;
    }

    if (detected == expected) {
      return true;
    }

    const aliases = <String, List<String>>{
      'cell phone': [
        'cell phone',
        'cellphone',
        'mobile phone',
        'mobile',
        'phone',
      ],
      'backpack': [
        'backpack',
        'bag',
      ],
      'laptop': [
        'laptop',
        'notebook',
      ],
      'bicycle': [
        'bicycle',
        'bike',
      ],
      'cup': [
        'cup',
      ],
      'scissors': [
        'scissors',
        'scissor',
      ],
      'bottle': [
        'bottle',
      ],
      'chair': [
        'chair',
      ],
      'book': [
        'book',
      ],
      'keyboard': [
        'keyboard',
      ],
    };

    final expectedAliases = aliases[expected];

    if (expectedAliases == null) {
      return false;
    }

    return expectedAliases.contains(detected);
  }

  void _usePhoto() {
    final imagePath = _capturedImagePath;

    if (imagePath == null) {
      return;
    }

    // Use the actual detector result. A wrong detected object must never
    // be marked as correct or saved as a learned topic word.
    final correct = _isCorrectObject();

    if (correct) {
      Navigator.pop(
        context,
        TopicCaptureResult(
          success: true,
          imagePath: imagePath,
          detectedWord: _detectedWord,
        ),
      );
      return;
    }

    _showWrongObjectDialog();
  }

  Future<void> _showWrongObjectDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final detected =
            _detectedWord ?? 'Unknown object';

        return AlertDialog(
          title: const Text(
            'Try Again',
          ),
          content: Text(
            'I detected "$detected".\n\n'
            'Please try to capture '
            '"${widget.word.word}".',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Try Again',
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    _retake();
  }

  Widget _buildCameraError(bool dark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.no_photography_rounded,
              size: 60,
              color: AppColors.textTertiary(dark),
            ),
            const SizedBox(height: 18),
            Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(dark),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ??
                  'Unable to access the camera.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary(dark),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _initializing = true;
                  _errorMessage = null;
                });

                _initializeCamera();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.topicColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Try Again',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(bool dark) {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return _buildCameraError(dark);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),

        Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 150,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black87,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),

        Center(
          child: _TargetFrame(
            color: widget.topicColor,
          ),
        ),

        Positioned(
          top: MediaQuery.of(context).padding.top + 75,
          left: 20,
          right: 20,
          child: _InstructionCard(
            word: widget.word.word,
            translation: widget.word.translation,
            color: widget.topicColor,
          ),
        ),

        Positioned(
          left: 20,
          right: 20,
          bottom: 30,
          child: Column(
            children: [
              const Text(
                'Place the object inside the frame',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _capturing ? null : _capture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: widget.topicColor,
                      width: 5,
                    ),
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        )
                      : Icon(
                          Icons.camera_alt_rounded,
                          color: widget.topicColor,
                          size: 32,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCapturedView(bool dark) {
    final imagePath = _capturedImagePath;

    if (imagePath == null) {
      return const SizedBox.shrink();
    }

    // Show the real result from the detector.
    final correct = _isCorrectObject();

    return Stack(
      fit: StackFit.expand,
      children: [
        // -------------------------------------------------------------
        // Background
        // -------------------------------------------------------------
        Container(
          color: Colors.black,
        ),

        // -------------------------------------------------------------
        // Captured object
        // Keep the object smaller so the result cards have their own space.
        // -------------------------------------------------------------
        Positioned(
          top: 145,
          left: 30,
          right: 30,
          bottom: 355,
          child: Center(
            child: InteractiveViewer(
              minScale: 0.7,
              maxScale: 3,
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),

        // -------------------------------------------------------------
        // Top information
        // Leave enough room for the separate back button in the top-left.
        // -------------------------------------------------------------
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                20,
                58,
                20,
                12,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black87,
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Captured Object',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Target: ${widget.word.word}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // -------------------------------------------------------------
        // Detection + definition
        // These are in ONE Column so they cannot overlap.
        // -------------------------------------------------------------
        Positioned(
          left: 20,
          right: 20,
          bottom: 105,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Detection result
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: correct
                        ? Colors.green
                        : Colors.redAccent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      correct
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      color: correct
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            correct
                                ? 'Correct object!'
                                : 'Object not matched',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _detectedWord == null
                                ? 'Nothing detected'
                                : 'Detected: $_detectedWord',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          if (_detectedConfidence != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Confidence: ${(_detectedConfidence! * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Dictionary definition
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.topicColor.withValues(alpha: 0.7),
                  ),
                ),
                child: _loadingDefinition
                    ? const SizedBox(
                        height: 35,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.word.word,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _listen,
                                visualDensity:
                                    VisualDensity.compact,
                                icon: Icon(
                                  Icons.volume_up_rounded,
                                  color: widget.topicColor,
                                ),
                              ),
                            ],
                          ),
                          if (_phonetic.isNotEmpty)
                            Text(
                              _phonetic,
                              style: TextStyle(
                                color: widget.topicColor,
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          if (_definition.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Text(
                              _definition,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),

        // -------------------------------------------------------------
        // Done button
        // -------------------------------------------------------------
        Positioned(
          left: 20,
          right: 20,
          bottom: 25,
          child: ElevatedButton.icon(
            onPressed: _usePhoto,
            icon: const Icon(
              Icons.check_rounded,
            ),
            label: const Text(
              'Done',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.topicColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: 15,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _initializing
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.cyan,
                    ),
                  )
                : _capturedImagePath != null
                    ? _buildCapturedView(dark)
                    : _buildCameraView(dark),

            // Back to the topic word grid.
            Positioned(
              top: 8,
              left: 8,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.42),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: _capturing ? null : _goBack,
                    tooltip: 'Back',
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// INSTRUCTION CARD
// ================================================================

class _InstructionCard extends StatelessWidget {
  final String word;
  final String translation;
  final Color color;

  const _InstructionCard({
    required this.word,
    required this.translation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(
          alpha: 0.68,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(
            alpha: 0.7,
          ),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.camera_alt_rounded,
            color: color,
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Find this object',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  translation,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// TARGET FRAME
// ================================================================

class _TargetFrame extends StatelessWidget {
  final Color color;

  const _TargetFrame({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 300,
      child: Stack(
        children: [
          _Corner(
            alignment: Alignment.topLeft,
            color: color,
          ),
          _Corner(
            alignment: Alignment.topRight,
            color: color,
          ),
          _Corner(
            alignment: Alignment.bottomLeft,
            color: color,
          ),
          _Corner(
            alignment: Alignment.bottomRight,
            color: color,
          ),
        ],
      ),
    );
  }
}

// ================================================================
// CORNER
// ================================================================

class _Corner extends StatelessWidget {
  final Alignment alignment;
  final Color color;

  const _Corner({
    required this.alignment,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;

    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 42,
        height: 42,
        child: CustomPaint(
          painter: _CornerPainter(
            color: color,
            isLeft: isLeft,
            isTop: isTop,
          ),
        ),
      ),
    );
  }
}

// ================================================================
// CORNER PAINTER
// ================================================================

class _CornerPainter extends CustomPainter {
  final Color color;
  final bool isLeft;
  final bool isTop;

  _CornerPainter({
    required this.color,
    required this.isLeft,
    required this.isTop,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (isLeft && isTop) {
      path.moveTo(2, 18);
      path.lineTo(2, 2);
      path.lineTo(18, 2);
    } else if (!isLeft && isTop) {
      path.moveTo(
        size.width - 18,
        2,
      );
      path.lineTo(
        size.width - 2,
        2,
      );
      path.lineTo(
        size.width - 2,
        18,
      );
    } else if (isLeft && !isTop) {
      path.moveTo(
        2,
        size.height - 18,
      );
      path.lineTo(
        2,
        size.height - 2,
      );
      path.lineTo(
        18,
        size.height - 2,
      );
    } else {
      path.moveTo(
        size.width - 18,
        size.height - 2,
      );
      path.lineTo(
        size.width - 2,
        size.height - 2,
      );
      path.lineTo(
        size.width - 2,
        size.height - 18,
      );
    }

    canvas.drawPath(
      path,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _CornerPainter oldDelegate,
  ) {
    return oldDelegate.color != color ||
        oldDelegate.isLeft != isLeft ||
        oldDelegate.isTop != isTop;
  }
}