import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_theme.dart';
import 'ar_anchor_screen.dart';
import 'detector_service.dart';
import 'dictionary_service.dart';
import 'firestore_service.dart';

class LiveScannerTab extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const LiveScannerTab({
    super.key,
    this.onBackToHome,
  });

  @override
  State<LiveScannerTab> createState() => _LiveScannerTabState();
}

class _LiveScannerTabState extends State<LiveScannerTab>
    with WidgetsBindingObserver {
  CameraController? _cameraController;

  List<CameraDescription> _cameras = [];

  bool _cameraReady = false;
  bool _isProcessing = false;
  bool _isScanning = false;
  bool _isOpeningAr = false;

  DateTime _lastDetection = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? _scanStartedAt;

  static const Duration _scanDuration = Duration(seconds: 3);

  static const int _requiredStableDetections = 3;

  final Map<String, int> _detectionCounts = {};

  // Most recent frame seen from the live preview stream. Used to save a
  // still image silently (without the OS camera shutter sound) instead of
  // calling controller.takePicture().
  CameraImage? _lastCameraImage;

  final FlutterTts _tts = FlutterTts();

  String _detectedWord = '';
  String _phonetic = '';
  String _partOfSpeech = '';
  String _definition = '';
  String _example = '';
  String? _lastImagePath;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _setupTts();
    _initializeCamera();
  }

  // ===========================================================================
  // TTS
  // ===========================================================================

  Future<void> _setupTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);

      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  Future<void> _speak(String word) async {
    final cleanWord = word.trim();

    if (cleanWord.isEmpty) {
      return;
    }

    try {
      await _tts.stop();
      await _tts.speak(cleanWord);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  // ===========================================================================
  // CAMERA
  // ===========================================================================

  Future<void> _initializeCamera() async {
    final previousController = _cameraController;
    _cameraController = null;
    _lastCameraImage = null;

    try {
      if (mounted) {
        setState(() {
          _cameraReady = false;
        });
      }

      if (previousController != null) {
        try {
          if (previousController.value.isStreamingImages) {
            await previousController.stopImageStream();
          }
        } catch (e) {
          debugPrint('Could not stop previous image stream: $e');
        } finally {
          await previousController.dispose();
        }
      }

      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        debugPrint('No cameras available.');
        return;
      }

      CameraDescription selectedCamera = _cameras.first;

      for (final camera in _cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      _cameraController = controller;

      await controller.initialize();

      try {
        await controller.lockCaptureOrientation(
          DeviceOrientation.portraitUp,
        );
      } catch (e) {
        debugPrint('Camera orientation lock error: $e');
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraReady = true;
      });

      await _startImageStream();
    } catch (e) {
      debugPrint('Camera initialization error: $e');

      final failedController = _cameraController;
      _cameraController = null;
      if (failedController != null) {
        try {
          await failedController.dispose();
        } catch (disposeError) {
          debugPrint('Camera disposal error: $disposeError');
        }
      }

      if (mounted) {
        setState(() {
          _cameraReady = false;
        });
      }
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isStreamingImages) {
      return;
    }

    try {
      await controller.startImageStream(
        _processCameraFrame,
      );
    } catch (e) {
      debugPrint('Could not start image stream: $e');
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;

    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Could not stop image stream: $e');
    }
  }

  /// ARKit needs exclusive access to the camera. Dispose the scanner camera
  /// before presenting the AR route; it is recreated after that route closes.
  Future<void> _releaseCameraForAr() async {
    final controller = _cameraController;
    _cameraController = null;
    _lastCameraImage = null;

    if (mounted) {
      setState(() {
        _cameraReady = false;
      });
    }

    if (controller == null) {
      return;
    }

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (e) {
      debugPrint('Could not stop scanner camera for AR: $e');
    } finally {
      await controller.dispose();
    }
  }

  // ===========================================================================
  // START SCAN
  // ===========================================================================

  Future<void> _startScan() async {
    if (!_cameraReady ||
        _cameraController == null ||
        _isScanning ||
        _isOpeningAr) {
      return;
    }

    _detectionCounts.clear();

    _lastDetection = DateTime.fromMillisecondsSinceEpoch(0);

    if (mounted) {
      setState(() {
        _isScanning = true;
        _isProcessing = false;

        _detectedWord = '';
        _phonetic = '';
        _partOfSpeech = '';
        _definition = '';
        _example = '';
        _lastImagePath = null;

        _scanStartedAt = DateTime.now();
      });
    }

    await _startImageStream();
  }

  // ===========================================================================
  // DETECTION
  // ===========================================================================

  Future<void> _processCameraFrame(
    CameraImage image,
  ) async {
    if (!_cameraReady ||
        !_isScanning ||
        _isProcessing ||
        _cameraController == null) {
      return;
    }

    _lastCameraImage = image;

    final now = DateTime.now();

    if (now.difference(_lastDetection).inMilliseconds < 450) {
      return;
    }

    _lastDetection = now;

    final startedAt = _scanStartedAt;

    if (startedAt != null && now.difference(startedAt) >= _scanDuration) {
      await _finishScan();
      return;
    }

    _isProcessing = true;

    try {
      final detectedLabel = await DetectorService.detectCameraImage(
        image,
      );

      if (!mounted || !_isScanning || detectedLabel == null) {
        return;
      }

      final word = detectedLabel.trim().toLowerCase();

      if (word.isEmpty) {
        return;
      }

      if (_isIgnoredLabel(word)) {
        return;
      }

      _detectionCounts[word] = (_detectionCounts[word] ?? 0) + 1;

      debugPrint(
        'Scanner: $word '
        'count=${_detectionCounts[word]}',
      );

      final count = _detectionCounts[word] ?? 0;

      if (count >= _requiredStableDetections) {
        await _acceptDetectedWord(word);
      }
    } catch (e) {
      debugPrint(
        'Live detection error: $e',
      );
    } finally {
      _isProcessing = false;
    }
  }

  bool _isIgnoredLabel(String word) {
    const ignored = {
      '',
      'person',
      'people',
      'human',
      'background',
      'unknown',
    };

    return ignored.contains(word);
  }

  // ===========================================================================
  // FINISH SCAN
  // ===========================================================================

  Future<void> _finishScan() async {
    if (!mounted || !_isScanning) {
      return;
    }

    final bestWord = _getMostFrequentWord();

    if (bestWord == null || bestWord.trim().isEmpty) {
      setState(() {
        _isScanning = false;
      });

      await _stopImageStream();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Object not detected. Aim the camera at one supported object and try again.',
          ),
          duration: Duration(seconds: 2),
        ),
      );

      await _startImageStream();

      return;
    }

    await _acceptDetectedWord(bestWord);
  }

  String? _getMostFrequentWord() {
    if (_detectionCounts.isEmpty) {
      return null;
    }

    String? bestWord;
    int bestCount = 0;

    for (final entry in _detectionCounts.entries) {
      if (entry.value > bestCount) {
        bestWord = entry.key;
        bestCount = entry.value;
      }
    }

    return bestWord;
  }

  // ===========================================================================
  // ACCEPT DETECTED WORD
  // ===========================================================================

  Future<void> _acceptDetectedWord(
    String word,
  ) async {
    if (!mounted || !_isScanning || word.trim().isEmpty) {
      return;
    }

    setState(() {
      _isScanning = false;
      _isProcessing = false;
    });

    await _stopImageStream();

    // Save the most recent preview frame and create the transparent cutout.
    // This avoids controller.takePicture(), which triggers the OS camera
    // shutter sound and makes scanning feel like a manual "capture" action.
    await _captureDetectedImage(word);

    await _handleDetectedWord(word);
  }

  Future<void> _captureDetectedImage(String word) async {
    final frame = _lastCameraImage;

    if (frame == null) {
      _lastImagePath = null;
      return;
    }

    try {
      final framePath = await DetectorService.saveCameraImage(frame);

      if (framePath == null) {
        _lastImagePath = null;
        debugPrint('Scanner image: could not save camera frame.');
        return;
      }

      // Re-run detection on the saved frame so Vision can select the
      // foreground instance that corresponds to the detected object.
      final details = await DetectorService.detectObjectDetails(
        framePath,
        targetLabel: word,
      );

      if (details == null) {
        _lastImagePath = null;
        debugPrint(
            'Scanner image: object could not be located in the captured frame.');
        return;
      }

      final cutout = await DetectorService.removeBackground(
        framePath,
        centerX: details.centerX,
        centerY: details.centerY,
      );

      // Do NOT fall back to the raw frame. A full frame would put the
      // bed/wall/background into the AR plane.
      _lastImagePath = await DetectorService.persistCutout(
        cutout,
        word: word,
      );

      debugPrint('Scanner cutout: $_lastImagePath');
    } catch (e) {
      debugPrint('Could not capture/segment detected object: $e');
      _lastImagePath = null;
    }
  }

  // ===========================================================================
  // DICTIONARY + AUTOMATIC AR
  // ===========================================================================

  Future<void> _handleDetectedWord(
    String word,
  ) async {
    try {
      final info = await DictionaryService.getWordInfo(
        word,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _detectedWord = info['word']?.toString() ?? word;

        _phonetic = info['phonetic']?.toString() ?? '';

        _partOfSpeech = info['partOfSpeech']?.toString() ?? 'Word';

        _definition = info['definition']?.toString() ?? '';

        _example = info['example']?.toString() ?? '';
      });

      try {
        await FirestoreService.recordScan(
          word: _detectedWord,
          definition: _definition,
          phonetic: _phonetic,
        );
      } catch (e) {
        debugPrint('Could not record AR scan: $e');
      }

      await _openArAutomatically();
    } catch (e) {
      debugPrint(
        'Dictionary lookup error: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _detectedWord = word;
        _phonetic = '';
        _partOfSpeech = 'Word';
        _definition = 'Definition is not available yet.';
        _example = '';
      });

      try {
        await FirestoreService.recordScan(
          word: word,
          definition: _definition,
        );
      } catch (recordError) {
        debugPrint('Could not record AR scan: $recordError');
      }

      await _openArAutomatically();
    }
  }

  Future<void> _openArAutomatically() async {
    if (!mounted || _detectedWord.trim().isEmpty || _isOpeningAr) {
      return;
    }

    setState(() {
      _isOpeningAr = true;
    });

    try {
      await Future.delayed(
        const Duration(milliseconds: 250),
      );

      if (!mounted) {
        return;
      }

      await _releaseCameraForAr();

      if (!mounted) {
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ARAnchorScreen(
            word: _detectedWord,
            phonetic: _phonetic,
            partOfSpeech: _partOfSpeech,
            definition: _definition,
            example: _example,
            imagePath: _lastImagePath,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'AR navigation error: $e',
      );
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        _isOpeningAr = false;
      });

      _detectionCounts.clear();

      await _initializeCamera();
    }
  }

  // ===========================================================================
  // APP LIFECYCLE
  // ===========================================================================

  @override
  void didChangeAppLifecycleState(
    AppLifecycleState state,
  ) {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _stopImageStream();
    }

    if (state == AppLifecycleState.resumed && mounted) {
      _initializeCamera();
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(
      this,
    );

    _stopImageStream();

    _cameraController?.dispose();

    _tts.stop();

    super.dispose();
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

  Widget _buildCameraLoading() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: CircularProgressIndicator(
              color: AppColors.cyan,
            ),
          ),
          Positioned(
            top: 20,
            left: 18,
            child: SafeArea(
              child: _CircleIconButton(
                icon: Icons.arrow_back_rounded,
                onTap: () {
                  widget.onBackToHome?.call();
                },
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 80,
            child: Center(
              child: Text(
                'Opening camera...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BACK BUTTON
  // ===========================================================================

  Widget _buildBackButton() {
    return Positioned(
      top: 20,
      left: 18,
      child: SafeArea(
        child: _CircleIconButton(
          icon: Icons.arrow_back_rounded,
          onTap: () async {
            if (_isOpeningAr) {
              return;
            }

            await _stopImageStream();

            if (!mounted) {
              return;
            }

            widget.onBackToHome?.call();
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // SCANNING INDICATOR
  // ===========================================================================

  Widget _buildScanningIndicator() {
    if (!_isScanning) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 86,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.65,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Stay Still',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SCAN BUTTON
  // ===========================================================================

  Widget _buildScanButton() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 28,
      child: SafeArea(
        top: false,
        child: Center(
          child: SizedBox(
            width: 190,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isScanning || _isOpeningAr ? null : _startScan,
              icon: _isScanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.camera_alt_rounded,
                    ),
              label: Text(
                _isScanning ? 'Scanning...' : 'Scan',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                disabledBackgroundColor: Colors.white70,
                disabledForegroundColor: Colors.black54,
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final previewSize = controller.value.previewSize;

    if (previewSize == null) {
      return CameraPreview(controller);
    }

    // Camera previewSize is normally reported as landscape (width x height)
    // even while the phone is held vertically. Swap the dimensions for the
    // portrait display, then use BoxFit.cover. This keeps the camera's real
    // aspect ratio, fills the screen, and crops only the excess edges instead
    // of stretching the image.
    final previewWidth = previewSize.height;
    final previewHeight = previewSize.width;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // BODY
  // ===========================================================================

  Widget _buildBody() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.black54,
                    ],
                  ),
                ),
              ),
            ),
          ),
          _buildBackButton(),
          _buildScanningIndicator(),
          _buildScanButton(),
          if (_isOpeningAr)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.35,
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: 0.75,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: AppColors.cyan,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Opening AR...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    if (!_cameraReady || _cameraController == null) {
      return _buildCameraLoading();
    }

    return _buildBody();
  }
}

// =============================================================================
// CIRCLE BUTTON
// =============================================================================

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.55,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white12,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
