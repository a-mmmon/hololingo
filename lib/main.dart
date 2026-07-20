import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
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
import 'package:flutter_tts/flutter_tts.dart';
import 'firestore_service.dart';
import 'detector_service.dart';
import 'app_theme.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera init error: $e');
    cameras = [];
  }

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? true;

  runApp(MyApp(initialDark: isDark));
}

class MyApp extends StatefulWidget {
  final bool initialDark;
  const MyApp({super.key, required this.initialDark});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ThemeNotifier _themeNotifier;

  @override
  void initState() {
    super.initState();
    _themeNotifier = ThemeNotifier()..setDark(widget.initialDark);
    _themeNotifier.addListener(_saveTheme);
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _themeNotifier.isDark);
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

// ── Tab Switcher ───────────────────────────────────────────────────────────────
class TabSwitcher extends InheritedWidget {
  final void Function(int) switchTab;
  const TabSwitcher({
    super.key,
    required this.switchTab,
    required super.child,
  });
  static TabSwitcher? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabSwitcher>();
  @override
  bool updateShouldNotify(TabSwitcher old) => false;
}

// ── Tab index constants ─────────────────────────────────────────────────────
// Keep these in sync with _AppBottomNav's items list below.
class AppTab {
  static const home = 0;
  static const scan = 1;
  static const review = 2;
  static const topics = 3;
  static const gobot = 4;
  static const profile = 5;
}

// ── App Shell ──────────────────────────────────────────────────────────────────
class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  _AppShellState createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = AppTab.home;

  void _switchTab(int index) => setState(() => _currentIndex = index);

  // Only cache tabs that are safe to keep alive (not camera, not profile)
  final Map<int, Widget> _tabCache = {};

  Widget _buildTab(int index) {
    // Profile: never cache — always rebuild fresh so data reloads
    if (index == AppTab.profile) return ProfileScreen();

    // Camera: never cache — so it doesn't bleed through other tabs
    if (index == AppTab.scan) return const CameraTab();

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
          children: List.generate(6, (i) => _buildTab(i)),
        ),
        bottomNavigationBar: _AppBottomNav(
          currentIndex: _currentIndex,
          onTap: _switchTab,
        ),
      ),
    );
  }
}

// ── Bottom Nav ─────────────────────────────────────────────────────────────────
class _AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  const _AppBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    // Order must match AppTab constants: home, scan, review, topics, gobot, profile
    final items = [
      _NavItem(icon: Icons.home_rounded, label: 'Home'),
      _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Scan'),
      _NavItem(icon: Icons.auto_stories_rounded, label: 'Review'),
      _NavItem(icon: Icons.map_rounded, label: 'Topics'),
      _NavItem(isGobot: true, label: 'Gobot'),
      _NavItem(icon: Icons.person_rounded, label: 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        border:
            Border(top: BorderSide(color: AppColors.border(dark), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.isGobot)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.cyan
                                : AppColors.secondary(dark),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? AppColors.cyan
                                  : AppColors.border(dark),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(Icons.smart_toy_rounded,
                              size: 20,
                              color: selected
                                  ? Colors.black
                                  : AppColors.textSecondary(dark)),
                        )
                      else
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.cyan.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.icon,
                              size: 22,
                              color: selected
                                  ? AppColors.cyan
                                  : AppColors.textSecondary(dark)),
                        ),
                      const SizedBox(height: 4),
                      Text(item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected
                                ? AppColors.cyan
                                : AppColors.textSecondary(dark),
                          )),
                    ],
                  ),
                ),
              );
            }),
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
  const _NavItem({this.icon, required this.label, this.isGobot = false});
}

// ── Camera Tab ─────────────────────────────────────────────────────────────────
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
  String? _lastImagePath;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initCamera();
    DetectorService.loadModel();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) {
      setState(() {
        _hasCameraError = true;
        _cameraError = 'No cameras found.';
      });
      return;
    }
    try {
      final controller = CameraController(
          cameras[0], ResolutionPreset.high,
          enableAudio: false);
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
      if (mounted) {
        setState(() {
          _hasCameraError = true;
          _cameraError = 'Camera error: $e';
        });
      }
    }
  }

  Future<void> _lookupWord(String word, {String? imagePath}) async {
    setState(() {
      _isLoadingWord = true;
      _showOverlay = true;
      _detectedWord = word;
      _lastImagePath = imagePath;
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
        _lookupWord(result, imagePath: image.path);
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: AppColors.cyan),
        SizedBox(height: 16),
        Text('Starting camera...',
            style: TextStyle(color: Colors.white54)),
      ]));

  Widget _buildError() => Center(
          child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(_cameraError,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white60, fontSize: 14)),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      border: Border.all(color: AppColors.cyan),
                      borderRadius: BorderRadius.circular(24)),
                  child: const Text('Retry',
                      style: TextStyle(color: AppColors.cyan))),
            ),
          ])));

  Widget _buildBody() {
    final dark = ThemeProvider.isDark(context);
    return Stack(children: [
      SizedBox.expand(child: CameraPreview(_controller!)),
      Container(
          decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment.center, radius: 1.2, colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.35)
      ]))),
      Positioned.fill(child: CustomPaint(painter: _CornerPainter())),
      Positioned(
          top: 56,
          left: 0,
          right: 0,
          child: Center(
              child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12)),
            child: const Text('Point camera at any object',
                style: TextStyle(color: Colors.white, fontSize: 14)),
          ))),
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
              isDark: dark,
              onClose: () => setState(() => _showOverlay = false),
              onListen: () => _speak(_detectedWord),
              onSave: () async {
                await FirestoreService.saveWord({
                  'word': _detectedWord,
                  'phonetic': _phonetic,
                  'definition': _definition,
                  'example': _example,
                  'image_path': _lastImagePath ?? '',
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('"$_detectedWord" saved!'),
                    backgroundColor: Colors.green[700],
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
              onQuiz: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QuizScreen())),
              onPlaceAr: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ArAnchorScreen(
                        word: _detectedWord,
                        phonetic: _phonetic,
                        definition: _definition,
                        example: _example,
                      ))),
            )),
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
                      color: AppColors.cyan.withValues(alpha: 0.15),
                      border:
                          Border.all(color: AppColors.cyan, width: 2.5)),
                  child: _isDetecting
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              color: AppColors.cyan, strokeWidth: 2.5))
                      : const Icon(Icons.camera_alt_rounded,
                          color: AppColors.cyan, size: 28)),
            ))),
    ]);
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.scannerCorner
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0, m = 28.0;
    canvas.drawLine(
        const Offset(m, m + len), const Offset(m, m), paint);
    canvas.drawLine(
        const Offset(m, m), const Offset(m + len, m), paint);
    canvas.drawLine(Offset(size.width - m - len, m),
        Offset(size.width - m, m), paint);
    canvas.drawLine(Offset(size.width - m, m),
        Offset(size.width - m, m + len), paint);
    canvas.drawLine(Offset(m, size.height - m - len),
        Offset(m, size.height - m), paint);
    canvas.drawLine(Offset(m, size.height - m),
        Offset(m + len, size.height - m), paint);
    canvas.drawLine(Offset(size.width - m - len, size.height - m),
        Offset(size.width - m, size.height - m), paint);
    canvas.drawLine(Offset(size.width - m, size.height - m - len),
        Offset(size.width - m, size.height - m), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WordPanel extends StatelessWidget {
  final String word, phonetic, partOfSpeech, definition, example;
  final bool isLoading, isDark;
  final VoidCallback onClose, onListen, onSave, onQuiz, onPlaceAr;
  const _WordPanel(
      {required this.word,
      required this.phonetic,
      required this.partOfSpeech,
      required this.definition,
      required this.example,
      required this.isLoading,
      required this.isDark,
      required this.onClose,
      required this.onListen,
      required this.onSave,
      required this.onQuiz,
      required this.onPlaceAr});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
          color: AppColors.card(isDark),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDark ? 0.4 : 0.1),
                blurRadius: 20,
                offset: const Offset(0, -4))
          ]),
      child: isLoading
          ? const SizedBox(
              height: 120,
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.cyan)))
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
                              color: AppColors.border(isDark),
                              borderRadius:
                                  BorderRadius.circular(2)))),
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(word,
                            style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(isDark),
                                letterSpacing: -0.5)),
                        const SizedBox(width: 10),
                        Padding(
                            padding:
                                const EdgeInsets.only(bottom: 6),
                            child: Text('· $partOfSpeech',
                                style: TextStyle(
                                    color: AppColors.textSecondary(
                                        isDark),
                                    fontSize: 14))),
                        const Spacer(),
                        GestureDetector(
                            onTap: onClose,
                            child: Icon(Icons.close_rounded,
                                color:
                                    AppColors.textSecondary(isDark))),
                      ]),
                  if (phonetic.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(
                            top: 2, bottom: 10),
                        child: Text(phonetic,
                            style: const TextStyle(
                                color: AppColors.cyan,
                                fontSize: 14,
                                fontStyle: FontStyle.italic))),
                  Text(definition,
                      style: TextStyle(
                          color: AppColors.textPrimary(isDark),
                          fontSize: 15,
                          height: 1.5)),
                  if (example.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Container(
                                  width: 3,
                                  height: 48,
                                  margin: const EdgeInsets.only(
                                      right: 10),
                                  decoration: BoxDecoration(
                                      color: AppColors.cyan,
                                      borderRadius:
                                          BorderRadius.circular(2))),
                              Expanded(
                                  child: Text('"$example"',
                                      style: TextStyle(
                                          color: AppColors
                                              .textSecondary(isDark),
                                          fontSize: 13,
                                          fontStyle: FontStyle.italic,
                                          height: 1.5))),
                            ])),
                  const SizedBox(height: 18),
                  Row(children: [
                    _ActionBtn(
                        icon: Icons.play_arrow_rounded,
                        label: 'Listen',
                        onTap: onListen,
                        filled: true,
                        isDark: isDark),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.add_rounded,
                        label: 'Save',
                        onTap: onSave,
                        isDark: isDark),
                    const SizedBox(width: 10),
                    _ActionBtn(
                        icon: Icons.quiz_rounded,
                        label: 'Quiz me',
                        onTap: onQuiz,
                        isDark: isDark),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: _ActionBtn(
                        icon: Icons.view_in_ar_rounded,
                        label: 'Place in AR',
                        onTap: onPlaceAr,
                        isDark: isDark),
                  ),
                ]),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled, isDark;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.filled = false,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: filled ? AppColors.cyan : Colors.transparent,
              border: Border.all(
                  color: filled
                      ? AppColors.cyan
                      : AppColors.border(isDark),
                  width: 1.5),
              borderRadius: BorderRadius.circular(24)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 16,
                color: filled
                    ? Colors.black
                    : AppColors.textPrimary(isDark)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: filled
                        ? Colors.black
                        : AppColors.textPrimary(isDark))),
          ]),
        ));
  }
}