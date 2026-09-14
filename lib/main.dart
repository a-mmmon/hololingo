import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'quiz_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'review_screen.dart';
import 'gobot_screen.dart';
import 'topics_screen.dart';
import 'ar_anchor_screen.dart';
import 'auth/auth_gate.dart';
import 'dictionary_service.dart';
import 'firestore_service.dart';
import 'detector_service.dart';
import 'app_theme.dart';
import 'live_scanner_tab.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Firebase App Check for local iOS development/testing.
  // This allows us to test Firebase services on the physical iPhone
  // before setting up production App Check attestation.

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera init error: $e');
    cameras = [];
  }

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? true;

  runApp(
    MyApp(
      initialDark: isDark,
    ),
  );
}

// ============================================================================
// APP
// ============================================================================

class MyApp extends StatefulWidget {
  final bool initialDark;

  const MyApp({
    super.key,
    required this.initialDark,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeNotifier _themeNotifier;

  @override
  void initState() {
    super.initState();

    _themeNotifier = ThemeNotifier()
      ..setDark(widget.initialDark);

    _themeNotifier.addListener(_saveTheme);
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'is_dark_mode',
      _themeNotifier.isDark,
    );
  }

  @override
  void dispose() {
    _themeNotifier.removeListener(_saveTheme);
    _themeNotifier.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeProvider(
      notifier: _themeNotifier,
      child: AnimatedBuilder(
        animation: _themeNotifier,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _themeNotifier.themeData,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

// ============================================================================
// TAB SWITCHER
// ============================================================================

class TabSwitcher extends InheritedWidget {
  final void Function(int) switchTab;

  const TabSwitcher({
    super.key,
    required this.switchTab,
    required super.child,
  });

  static TabSwitcher? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TabSwitcher>();
  }

  @override
  bool updateShouldNotify(TabSwitcher old) {
    return false;
  }
}

// ============================================================================
// TAB INDEX
// ============================================================================

class AppTab {
  static const home = 0;
  static const scan = 1;
  static const review = 2;
  static const topics = 3;
  static const gobot = 4;
  static const profile = 5;
}

// ============================================================================
// APP SHELL
// ============================================================================

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = AppTab.home;

  final Map<int, Widget> _tabCache = {};

  void _switchTab(int index) {
    setState(() {
      // HomeScreen is cached in the IndexedStack. Remove the cached instance
      // when returning Home so profile changes (such as Daily word goal) are
      // loaded again from Firestore immediately.
      if (index == AppTab.home) {
        _tabCache.remove(AppTab.home);
      }

      _currentIndex = index;
    });
  }

  Widget _buildTab(int index) {
    if (index == AppTab.profile) {
      return ProfileScreen();
    }

    if (index == AppTab.scan) {
      return LiveScannerTab(
        onBackToHome: () {
          _switchTab(AppTab.home);
        },
      );
    }

    if (!_tabCache.containsKey(index)) {
      _tabCache[index] = switch (index) {
        AppTab.home => const HomeScreen(),
        AppTab.review => const ReviewScreen(),
        AppTab.topics => const TopicsScreen(),
        AppTab.gobot => const GobotScreen(),
        _ => const SizedBox.shrink(),
      };
    }

    return _tabCache[index]!;
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return TabSwitcher(
      switchTab: _switchTab,
      child: Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(
            6,
            (index) => _buildTab(index),
          ),
        ),
        bottomNavigationBar: _AppBottomNav(
          currentIndex: _currentIndex,
          onTap: _switchTab,
        ),
      ),
    );
  }
}

// ============================================================================
// BOTTOM NAVIGATION
// ============================================================================

class _AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _AppBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    final items = [
      _NavItem(
        icon: Icons.home_rounded,
        label: 'Home',
      ),
      _NavItem(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Scan',
      ),
      _NavItem(
        icon: Icons.auto_stories_rounded,
        label: 'Review',
      ),
      _NavItem(
        icon: Icons.map_rounded,
        label: 'Topics',
      ),
      _NavItem(
        isGobot: true,
        label: 'Gobot',
      ),
      _NavItem(
        icon: Icons.person_rounded,
        label: 'Profile',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        border: Border(
          top: BorderSide(
            color: AppColors.border(dark),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(
              items.length,
              (index) {
                final item = items[index];
                final selected = index == currentIndex;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (item.isGobot)
                          AnimatedContainer(
                            duration: const Duration(
                              milliseconds: 200,
                            ),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.cyan
                                  : AppColors.secondary(
                                      dark,
                                    ),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.cyan
                                    : AppColors.border(
                                        dark,
                                      ),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.smart_toy_rounded,
                              size: 20,
                              color: selected
                                  ? Colors.black
                                  : AppColors.textSecondary(
                                      dark,
                                    ),
                            ),
                          )
                        else
                          AnimatedContainer(
                            duration: const Duration(
                              milliseconds: 200,
                            ),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.cyan.withValues(
                                      alpha: 0.15,
                                    )
                                  : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: Icon(
                              item.icon,
                              size: 22,
                              color: selected
                                  ? AppColors.cyan
                                  : AppColors.textSecondary(
                                      dark,
                                    ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected
                                ? AppColors.cyan
                                : AppColors.textSecondary(
                                    dark,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData? icon;
  final String label;
  final bool isGobot;

  const _NavItem({
    this.icon,
    required this.label,
    this.isGobot = false,
  });
}

// ============================================================================
// CAMERA TAB
// ============================================================================

class CameraTab extends StatefulWidget {
  const CameraTab({
    super.key,
  });

  @override
  State<CameraTab> createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  CameraController? _controller;

  bool _isInitialized = false;
  bool _hasCameraError = false;

  String _cameraError = '';

  String _detectedWord = '';
  String _definition = '';
  String _allDefinitions = '';
  String _phonetic = '';
  String _example = '';
  String _partOfSpeech = 'Noun';

  bool _showOverlay = false;
  bool _isLoadingWord = false;
  bool _isDetecting = false;

  String? _lastImagePath;

  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();

    _initCamera();
    _initTts();

    DetectorService.loadModel();
  }

  // ==========================================================================
  // CAMERA INITIALIZATION
  // ==========================================================================

  Future<void> _initCamera() async {
    if (cameras.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _hasCameraError = true;
        _cameraError = 'No cameras found.';
      });

      return;
    }

    try {
      final controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _hasCameraError = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _hasCameraError = true;
        _cameraError = 'Camera error: $e';
      });
    }
  }

  // ==========================================================================
  // TTS INITIALIZATION
  // ==========================================================================

  Future<void> _initTts() async {
    try {
      await _tts.setSharedInstance(true);

      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );

      await _tts.awaitSpeakCompletion(true);

      await _tts.setQueueMode(0);

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.45);

      _tts.setStartHandler(() {
        debugPrint('TTS: started');
      });

      _tts.setCompletionHandler(() {
        debugPrint('TTS: completed');
      });

      _tts.setErrorHandler((message) {
        debugPrint('TTS error: $message');
      });
    } catch (e) {
      debugPrint('TTS setup error: $e');
    }
  }

  // ==========================================================================
  // SPEAK
  // ==========================================================================

  Future<void> _speak(String word) async {
    final text = word.trim();

    if (text.isEmpty) {
      return;
    }

    try {
      debugPrint(
        'TTS: preparing to speak "$text"',
      );

      await _tts.stop();

      await _tts.setLanguage('en-US');

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.45);

      final result = await _tts.speak(text);

      debugPrint(
        'TTS speak result: $result',
      );
    } catch (e) {
      debugPrint(
        'TTS speak error: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not play pronunciation: $e',
          ),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  // ==========================================================================
  // LOOK UP DICTIONARY
  // ==========================================================================

  Future<void> _lookupWord(
    String word, {
    String? imagePath,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoadingWord = true;
      _showOverlay = true;
      _detectedWord = word;
      _lastImagePath = imagePath;
    });

    final result =
        await DictionaryService.getWordInfo(word);

    if (!mounted) {
      return;
    }

    setState(() {
      _phonetic =
          result['phonetic'] ?? '';

      _definition =
          result['definition'] ?? '';

      _allDefinitions =
          result['allDefinitions'] ?? '';

      _example =
          result['example'] ?? '';

      _partOfSpeech =
          result['partOfSpeech'] ?? 'Noun';

      _isLoadingWord = false;
    });
  }

  // ==========================================================================
  // CLOSE RESULT PANEL
  // ==========================================================================

  Future<void> _closeWordPanel() async {
    if (mounted) {
      setState(() {
        _showOverlay = false;
      });
    }

    try {
      await _controller?.resumePreview();
    } catch (e) {
      debugPrint(
        'Camera resume error: $e',
      );
    }
  }

  // ==========================================================================
  // CAPTURE + DETECT
  // ==========================================================================

  Future<void> _startDetection() async {
    final ctrl = _controller;

    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _isDetecting) {
      return;
    }

    setState(() {
      _isDetecting = true;
    });

    try {
      final image =
          await ctrl.takePicture();

      debugPrint(
        'Camera captured: ${image.path}',
      );

      try {
        await ctrl.pausePreview();

        debugPrint(
          'Camera preview paused.',
        );
      } catch (e) {
        debugPrint(
          'Camera pause error: $e',
        );
      }

      final result =
          await DetectorService.detectObject(
        image.path,
      );

      if (!mounted) {
        return;
      }

      if (result != null &&
          result.isNotEmpty) {
        await _lookupWord(
          result,
          imagePath: image.path,
        );
      } else {
        try {
          await ctrl.resumePreview();
        } catch (e) {
          debugPrint(
            'Camera resume error: $e',
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(
            const SnackBar(
              content: Text(
                'No object detected. Try again!',
              ),
              backgroundColor:
                  Colors.orange,
              duration:
                  Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(
        'Detection error: $e',
      );

      try {
        await ctrl.resumePreview();
      } catch (resumeError) {
        debugPrint(
          'Camera resume error: $resumeError',
        );
      }
    }

    if (mounted) {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  // ==========================================================================
  // DISPOSE
  // ==========================================================================

  @override
  void dispose() {
    _tts.stop();

    _controller?.dispose();

    DetectorService.dispose();

    super.dispose();
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    if (_hasCameraError) {
      return _buildError();
    }

    if (!_isInitialized) {
      return _buildLoading();
    }

    return _buildBody();
  }

  // ==========================================================================
  // CAMERA LOADING
  // ==========================================================================

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: AppColors.cyan,
          ),
          SizedBox(height: 16),
          Text(
            'Starting camera...',
            style: TextStyle(
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CAMERA ERROR
  // ==========================================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(32),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white38,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _cameraError,
              textAlign:
                  TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                setState(() {
                  _hasCameraError = false;
                  _isInitialized = false;
                });

                _initCamera();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration:
                    BoxDecoration(
                  border: Border.all(
                    color: AppColors.cyan,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    24,
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: AppColors.cyan,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // CAMERA BODY
  // ==========================================================================

  Widget _buildBody() {
    final dark =
        ThemeProvider.isDark(context);

    return Stack(
      children: [
        // --------------------------------------------------------------------
        // CAMERA / CAPTURED IMAGE
        // --------------------------------------------------------------------
        SizedBox.expand(
          child: _showOverlay &&
                  _lastImagePath != null &&
                  File(
                    _lastImagePath!,
                  ).existsSync()
              ? Image.file(
                  File(
                    _lastImagePath!,
                  ),
                  fit: BoxFit.cover,
                )
              : CameraPreview(
                  _controller!,
                ),
        ),

        // --------------------------------------------------------------------
        // DARK CAMERA GRADIENT
        // --------------------------------------------------------------------
        Container(
          decoration:
              BoxDecoration(
            gradient:
                RadialGradient(
              center:
                  Alignment.center,
              radius: 1.2,
              colors: [
                Colors.transparent,
                Colors.black.withValues(
                  alpha: 0.35,
                ),
              ],
            ),
          ),
        ),

        // --------------------------------------------------------------------
        // SCANNER CORNERS
        // --------------------------------------------------------------------
        Positioned.fill(
          child: CustomPaint(
            painter:
                _CornerPainter(),
          ),
        ),

        // --------------------------------------------------------------------
        // CAMERA INSTRUCTION
        // --------------------------------------------------------------------
        if (!_showOverlay)
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.black.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    24,
                  ),
                  border: Border.all(
                    color: Colors.white12,
                  ),
                ),
                child: const Text(
                  'Point camera at any object',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

        // --------------------------------------------------------------------
        // DICTIONARY RESULT
        // --------------------------------------------------------------------
        if (_showOverlay)
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: 0.58,
              minChildSize: 0.35,
              maxChildSize: 0.92,
              snap: true,
              snapSizes: const [
                0.58,
                0.92,
              ],
              builder: (
                BuildContext context,
                ScrollController scrollController,
              ) {
                return _WordPanel(
                  scrollController:
                      scrollController,
                  word: _detectedWord,
                  phonetic: _phonetic,
                  partOfSpeech:
                      _partOfSpeech,
                  definition: _definition,
                  allDefinitions:
                      _allDefinitions,
                  example: _example,
                  isLoading:
                      _isLoadingWord,
                  isDark: dark,
                  onClose:
                      _closeWordPanel,
                  onListen: () {
                    _speak(
                      _detectedWord,
                    );
                  },
                  onSave: () async {
                    await FirestoreService
                        .saveWord({
                      'word':
                          _detectedWord,
                      'phonetic':
                          _phonetic,
                      'definition':
                          _definition,
                      'example':
                          _example,
                      'image_path':
                          _lastImagePath ??
                              '',
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            '"$_detectedWord" saved!',
                          ),
                          backgroundColor:
                              Colors.green[700],
                          duration:
                              const Duration(
                            seconds: 2,
                          ),
                        ),
                      );
                    }
                  },
                  onQuiz: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const QuizScreen(),
                      ),
                    );
                  },
                  onPlaceAr: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ARAnchorScreen(
                      word:
                          _detectedWord,
                      phonetic:
                          _phonetic,
                      definition:
                          _definition,
                      example:
                          _example,
                            ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

        // --------------------------------------------------------------------
        // CAMERA CAPTURE BUTTON
        // --------------------------------------------------------------------
        if (!_showOverlay)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isDetecting
                    ? null
                    : _startDetection,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,
                    color:
                        AppColors.cyan
                            .withValues(
                      alpha: 0.15,
                    ),
                    border:
                        Border.all(
                      color:
                          AppColors.cyan,
                      width: 2.5,
                    ),
                  ),
                  child: _isDetecting
                      ? const Padding(
                          padding:
                              EdgeInsets.all(
                            16,
                          ),
                          child:
                              CircularProgressIndicator(
                            color:
                                AppColors
                                    .cyan,
                            strokeWidth:
                                2.5,
                          ),
                        )
                      : const Icon(
                          Icons
                              .camera_alt_rounded,
                          color:
                              AppColors.cyan,
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// SCANNER CORNER PAINTER
// ============================================================================

class _CornerPainter
    extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          AppColors.scannerCorner
      ..strokeWidth = 3
      ..style =
          PaintingStyle.stroke
      ..strokeCap =
          StrokeCap.round;

    const len = 28.0;
    const m = 28.0;

    // Top left
    canvas.drawLine(
      const Offset(
        m,
        m + len,
      ),
      const Offset(
        m,
        m,
      ),
      paint,
    );

    canvas.drawLine(
      const Offset(
        m,
        m,
      ),
      const Offset(
        m + len,
        m,
      ),
      paint,
    );

    // Top right
    canvas.drawLine(
      Offset(
        size.width -
            m -
            len,
        m,
      ),
      Offset(
        size.width - m,
        m,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width - m,
        m,
      ),
      Offset(
        size.width - m,
        m + len,
      ),
      paint,
    );

    // Bottom left
    canvas.drawLine(
      Offset(
        m,
        size.height -
            m -
            len,
      ),
      Offset(
        m,
        size.height - m,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        m,
        size.height - m,
      ),
      Offset(
        m + len,
        size.height - m,
      ),
      paint,
    );

    // Bottom right
    canvas.drawLine(
      Offset(
        size.width -
            m -
            len,
        size.height - m,
      ),
      Offset(
        size.width - m,
        size.height - m,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width - m,
        size.height -
            m -
            len,
      ),
      Offset(
        size.width - m,
        size.height - m,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// ============================================================================
// WORD PANEL
// ============================================================================

class _WordPanel extends StatelessWidget {
  final ScrollController scrollController;

  final String word;
  final String phonetic;
  final String partOfSpeech;
  final String definition;
  final String allDefinitions;
  final String example;

  final bool isLoading;
  final bool isDark;

  final VoidCallback onClose;
  final VoidCallback onListen;
  final VoidCallback onSave;
  final VoidCallback onQuiz;
  final VoidCallback onPlaceAr;

  const _WordPanel({
    required this.scrollController,
    required this.word,
    required this.phonetic,
    required this.partOfSpeech,
    required this.definition,
    required this.allDefinitions,
    required this.example,
    required this.isLoading,
    required this.isDark,
    required this.onClose,
    required this.onListen,
    required this.onSave,
    required this.onQuiz,
    required this.onPlaceAr,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(isDark),
        borderRadius:
            const BorderRadius.vertical(
          top: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: isDark ? 0.45 : 0.12,
            ),
            blurRadius: 24,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.cyan,
              ),
            )
          : Column(
              children: [
                // ------------------------------------------------------------
                // DRAG HANDLE
                // ------------------------------------------------------------
                Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 8,
                  ),
                  child: Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color:
                            AppColors.border(isDark),
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),

                // ------------------------------------------------------------
                // FIXED HEADER
                // ------------------------------------------------------------
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    24,
                    2,
                    18,
                    10,
                  ),
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.center,
                    children: [
                      // Word + POS
                      Expanded(
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                word,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight:
                                      FontWeight.w800,
                                  color: AppColors
                                      .textPrimary(
                                    isDark,
                                  ),
                                  letterSpacing:
                                      -0.8,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Padding(
                                padding:
                                    const EdgeInsets
                                        .only(
                                  bottom: 6,
                                ),
                                child: Text(
                                  '· $partOfSpeech',
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors
                                        .textSecondary(
                                      isDark,
                                    ),
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ------------------------------------------------------
                      // CLOSE BUTTON
                      // ------------------------------------------------------
                      const SizedBox(width: 8),

                      SizedBox(
                        width: 44,
                        height: 44,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          splashRadius: 22,
                          onPressed: onClose,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 30,
                            color: AppColors
                                .textSecondary(
                              isDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ------------------------------------------------------------
                // SCROLLABLE CONTENT
                // ------------------------------------------------------------
                Expanded(
                  child: SingleChildScrollView(
                    controller:
                        scrollController,
                    physics:
                        const ClampingScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(
                      24,
                      0,
                      24,
                      36,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // ----------------------------------------------------
                        // PHONETIC
                        // ----------------------------------------------------
                        if (phonetic.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              bottom: 14,
                            ),
                            child: Text(
                              phonetic,
                              style:
                                  const TextStyle(
                                color:
                                    AppColors.cyan,
                                fontSize: 14,
                                fontStyle:
                                    FontStyle.italic,
                              ),
                            ),
                          ),

                        // ----------------------------------------------------
                        // MAIN DEFINITION
                        // ----------------------------------------------------
                        Text(
                          definition,
                          style: TextStyle(
                            color: AppColors
                                .textPrimary(
                              isDark,
                            ),
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),

                        // ----------------------------------------------------
                        // MORE MEANINGS
                        // ----------------------------------------------------
                        if (allDefinitions
                                .isNotEmpty &&
                            allDefinitions.trim() !=
                                definition.trim())
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              top: 12,
                            ),
                            child: Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(
                                dividerColor:
                                    Colors.transparent,
                              ),
                              child:
                                  ExpansionTile(
                                tilePadding:
                                    EdgeInsets.zero,
                                childrenPadding:
                                    const EdgeInsets
                                        .only(
                                  bottom: 6,
                                ),
                                iconColor:
                                    AppColors.cyan,
                                collapsedIconColor:
                                    AppColors
                                        .textSecondary(
                                  isDark,
                                ),
                                title: Text(
                                  'More meanings',
                                  style: TextStyle(
                                    color: AppColors
                                        .textPrimary(
                                      isDark,
                                    ),
                                    fontSize: 16,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                                children: [
                                  Align(
                                    alignment:
                                        Alignment
                                            .centerLeft,
                                    child: Text(
                                      allDefinitions,
                                      style: TextStyle(
                                        color: AppColors
                                            .textSecondary(
                                          isDark,
                                        ),
                                        fontSize: 14,
                                        height: 1.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // ----------------------------------------------------
                        // EXAMPLE
                        // ----------------------------------------------------
                        if (example.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              top: 14,
                            ),
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets
                                      .only(
                                left: 14,
                                right: 10,
                                top: 4,
                                bottom: 4,
                              ),
                              decoration:
                                  BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color:
                                        AppColors.cyan,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Text(
                                '"$example"',
                                style: TextStyle(
                                  color: AppColors
                                      .textSecondary(
                                    isDark,
                                  ),
                                  fontSize: 14,
                                  fontStyle:
                                      FontStyle.italic,
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 22),

                        // ----------------------------------------------------
                        // ACTION BUTTONS
                        // ----------------------------------------------------
                        Row(
                          children: [
                            Expanded(
                              child: _ActionBtn(
                                icon: Icons
                                    .play_arrow_rounded,
                                label: 'Listen',
                                onTap: onListen,
                                filled: true,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ActionBtn(
                                icon: Icons
                                    .add_rounded,
                                label: 'Save',
                                onTap: onSave,
                                isDark: isDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ActionBtn(
                                icon: Icons
                                    .quiz_rounded,
                                label: 'Quiz me',
                                onTap: onQuiz,
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ----------------------------------------------------
                        // AR BUTTON
                        // ----------------------------------------------------
                        SizedBox(
                          width: double.infinity,
                          child: _ActionBtn(
                            icon: Icons
                                .view_in_ar_rounded,
                            label: 'Place in AR',
                            onTap: onPlaceAr,
                            isDark: isDark,
                          ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ============================================================================
// ACTION BUTTON
// ============================================================================

class _ActionBtn
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  final bool isDark;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    required this.isDark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 48,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
        ),
        decoration:
            BoxDecoration(
          color: filled
              ? AppColors.cyan
              : Colors.transparent,
          border: Border.all(
            color: filled
                ? AppColors.cyan
                : AppColors.border(
                    isDark,
                  ),
            width: 1.5,
          ),
          borderRadius:
              BorderRadius.circular(
            25,
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled
                  ? Colors.black
                  : AppColors
                      .textPrimary(
                    isDark,
                  ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      FontWeight.w600,
                  color: filled
                      ? Colors.black
                      : AppColors
                          .textPrimary(
                        isDark,
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