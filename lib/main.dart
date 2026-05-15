import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'saved_screen.dart';
import 'quiz_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'vocal_screen.dart';
import 'dictionary_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'database_service.dart';
import 'detector_service.dart';
import 'app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_profile_screen.dart';
import 'dart:io';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  // FIX 1: Wrap availableCameras() in try/catch — it can throw if
  // permission is denied, hanging or crashing the app before UI shows.
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera init error: $e');
    cameras = [];
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(primary: AppColors.cyan),
      ),
      home: const AppShell(),
    );
  }
}

// ── Tab Switcher ──────────────────────────────────────────────────────────────
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
  bool updateShouldNotify(TabSwitcher old) => false;
}

// ── App Shell ─────────────────────────────────────────────────────────────────
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  void _switchTab(int index) => setState(() => _currentIndex = index);

  // FIX 2: Use PageView-style lazy loading instead of IndexedStack.
  // IndexedStack builds ALL children immediately — including CameraTab —
  // which triggers camera + ML Kit init before the user even taps Scan.
  // This list only builds the tab when it's first visited.
  final Map<int, Widget> _tabCache = {};

  Widget _buildTab(int index) {
    if (!_tabCache.containsKey(index)) {
      _tabCache[index] = switch (index) {
        0 => const HomeScreen(),
        1 => const CameraTab(),
        2 => SavedScreen(),
        3 => const VocalScreen(),
        4 => const ProfileScreen(),
        _ => const SizedBox.shrink(),
      };
    }
    return _tabCache[index]!;
  }

  @override
  Widget build(BuildContext context) {
    return TabSwitcher(
      switchTab: _switchTab,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        // FIX 2 cont: Stack with Offstage keeps state but builds lazily
        body: Stack(
          children: List.generate(5, (i) {
            return Offstage(
              offstage: _currentIndex != i,
              child: TickerMode(
                enabled: _currentIndex == i,
                child: _buildTab(i),
              ),
            );
          }),
        ),
        bottomNavigationBar: AppBottomNav(
          currentIndex: _currentIndex,
          onTap: _switchTab,
        ),
      ),
    );
  }
}

// ── Camera Tab ────────────────────────────────────────────────────────────────
class CameraTab extends StatefulWidget {
  const CameraTab({super.key});

  @override
  _CameraTabState createState() => _CameraTabState();
}

class _CameraTabState extends State<CameraTab> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _hasCameraError = false;
  String _cameraError = '';

  String _detectedWord = '';
  String _definition = '';
  String _phonetic = '';
  String _example = '';
  String _partOfSpeech = 'Noun';
  bool _showOverlay = false;
  bool _isLoadingWord = false;
  bool _isDetecting = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initCamera();
    // FIX 3: Don't await loadModel in initState — run it in background
    DetectorService.loadModel();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) {
      setState(() {
        _hasCameraError = true;
        _cameraError = 'No cameras found. Please check camera permissions in Settings.';
      });
      return;
    }

    // FIX 4: Wrap entire camera init in try/catch with user-visible error
    try {
      final controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false, // saves resources, we don't need audio
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
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _cameraError = 'Camera error: ${e.toString()}\n\nPlease allow camera access in Settings.';
        });
      }
    }
  }

  Future<void> _lookupWord(String word) async {
    setState(() {
      _isLoadingWord = true;
      _showOverlay = true;
      _detectedWord = word;
    });
    final result = await DictionaryService.getWordInfo(word);
    if (!mounted) return;
    setState(() {
      _phonetic = result['phonetic'] ?? '';
      _definition = result['definition'] ?? '';
      _example = result['example'] ?? '';
      _partOfSpeech = result['partOfSpeech'] ?? 'Noun';
      _isLoadingWord = false;
    });
  }

  Future<void> _speak(String word) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  Future<void> _startDetection() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      final image = await ctrl.takePicture();
      final result = await DetectorService.detectObject(image.path);
      if (!mounted) return;
      if (result != null && result.isNotEmpty) {
        _lookupWord(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No object detected. Try again!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('Detection error: $e');
    }
    if (mounted) setState(() => _isDetecting = false);
  }

  @override
  void dispose() {
    _controller?.dispose();
    DetectorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasCameraError) return _buildError();
    if (!_isInitialized) return _buildLoading();
    return _buildBody();
  }

  Widget _buildLoading() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.cyan),
            SizedBox(height: 16),
            Text('Starting camera...', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );

  // FIX 5: Show a helpful error instead of a blank white screen
  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white38, size: 64),
              const SizedBox(height: 16),
              Text(
                _cameraError,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.cyan),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text('Retry', style: TextStyle(color: AppColors.cyan)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildBody() {
    return Stack(
      children: [
        SizedBox.expand(child: CameraPreview(_controller!)),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [Colors.transparent, Colors.black.withOpacity(0.35)],
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _CornerPainter())),

        // Top hint pill
        Positioned(
          top: 56,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
              ),
              child: const Text('Point camera at any object',
                  style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
        ),

        // Word panel
        if (_showOverlay)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _WordPanel(
              word: _detectedWord,
              phonetic: _phonetic,
              partOfSpeech: _partOfSpeech,
              definition: _definition,
              example: _example,
              isLoading: _isLoadingWord,
              onClose: () => setState(() => _showOverlay = false),
              onListen: () => _speak(_detectedWord),
              onSave: () async {
                await DatabaseService.saveWord({
                  'word': _detectedWord,
                  'phonetic': _phonetic,
                  'definition': _definition,
                  'example': _example,
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('"$_detectedWord" saved!'),
                    backgroundColor: Colors.green[700],
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
              onQuiz: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => QuizScreen()),
              ),
            ),
          ),

        // Detect button
        if (!_showOverlay)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _isDetecting ? null : _startDetection,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cyan.withOpacity(0.15),
                    border: Border.all(color: AppColors.cyan, width: 2.5),
                  ),
                  child: _isDetecting
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              color: AppColors.cyan, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.camera_alt_rounded,
                          color: AppColors.cyan, size: 28),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Scanner Corner Painter ────────────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.scannerCorner
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    const m = 28.0;
    canvas.drawLine(const Offset(m, m + len), const Offset(m, m), paint);
    canvas.drawLine(const Offset(m, m), const Offset(m + len, m), paint);
    canvas.drawLine(
        Offset(size.width - m - len, m), Offset(size.width - m, m), paint);
    canvas.drawLine(
        Offset(size.width - m, m), Offset(size.width - m, m + len), paint);
    canvas.drawLine(
        Offset(m, size.height - m - len), Offset(m, size.height - m), paint);
    canvas.drawLine(
        Offset(m, size.height - m), Offset(m + len, size.height - m), paint);
    canvas.drawLine(Offset(size.width - m - len, size.height - m),
        Offset(size.width - m, size.height - m), paint);
    canvas.drawLine(Offset(size.width - m, size.height - m - len),
        Offset(size.width - m, size.height - m), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Word Panel ────────────────────────────────────────────────────────────────
class _WordPanel extends StatelessWidget {
  final String word, phonetic, partOfSpeech, definition, example;
  final bool isLoading;
  final VoidCallback onClose, onListen, onSave, onQuiz;

  const _WordPanel({
    required this.word,
    required this.phonetic,
    required this.partOfSpeech,
    required this.definition,
    required this.example,
    required this.isLoading,
    required this.onClose,
    required this.onListen,
    required this.onSave,
    required this.onQuiz,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: isLoading
          ? const SizedBox(
              height: 120,
              child:
                  Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(word,
                        style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5)),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('· $partOfSpeech',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 14)),
                    ),
                    const Spacer(),
                    GestureDetector(
                        onTap: onClose,
                        child: const Icon(Icons.close_rounded,
                            color: AppColors.textSecondary)),
                  ],
                ),
                if (phonetic.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 10),
                    child: Text(phonetic,
                        style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 14,
                            fontStyle: FontStyle.italic)),
                  ),
                Text(definition,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 15, height: 1.5)),
                if (example.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            width: 3,
                            height: 48,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                                color: AppColors.cyan,
                                borderRadius: BorderRadius.circular(2))),
                        Expanded(
                          child: Text('"$example"',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  height: 1.5)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _ActionBtn(
                        icon: Icons.play_arrow_rounded,
                        label: 'Listen',
                        onTap: onListen,
                        filled: true),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.add_rounded, label: 'Save', onTap: onSave),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.quiz_rounded,
                        label: 'Quiz me',
                        onTap: onQuiz),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.cyan : Colors.transparent,
          border: Border.all(
              color: filled ? AppColors.cyan : Colors.white30, width: 1.5),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: filled ? Colors.black : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: filled ? Colors.black : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}