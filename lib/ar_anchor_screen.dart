import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:arkit_plugin/arkit_plugin.dart';

import 'app_theme.dart';
import 'detector_service.dart';
import 'firestore_service.dart';
import 'quiz_screen.dart';

class ARAnchorScreen extends StatefulWidget {
  final String word;
  final String phonetic;
  final String partOfSpeech;
  final String definition;
  final String example;
  final String? imagePath;

  const ARAnchorScreen({
    super.key,
    required this.word,
    this.phonetic = '',
    this.partOfSpeech = '',
    this.definition = '',
    this.example = '',
    this.imagePath,
  });

  @override
  State<ARAnchorScreen> createState() => _ARAnchorScreenState();
}

class _ARAnchorScreenState extends State<ARAnchorScreen>
    with SingleTickerProviderStateMixin {
  ARKitController? _arkitController;
  late final AnimationController _floatController;

  final FlutterTts _tts = FlutterTts();
  bool _showDetails = false;
  bool _saving = false;
  bool _saved = false;

  String get _displayWord {
    final value = widget.word.trim();

    if (value.isEmpty) {
      return 'Object';
    }

    if (value.length == 1) {
      return value.toUpperCase();
    }

    return value[0].toUpperCase() + value.substring(1);
  }

  // ===========================================================================
  // INIT
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _setupTts();
  }

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
      debugPrint('AR TTS setup error: $e');
    }
  }

  // ===========================================================================
  // AR INITIALIZATION
  // ===========================================================================

  void _onARKitViewCreated(
    ARKitController controller,
  ) {
    // AR is used as the live camera view only. We intentionally do not
    // request a horizontal surface, because this screen is a vocabulary
    // learning overlay rather than a furniture/object placement tool.
    _arkitController = controller;
  }

  // ===========================================================================
  // TOP AR LABEL
  // ===========================================================================

  Widget _buildWordCard() {
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.of(context).size.height * 0.28,
      child: Center(
        child: GestureDetector(
          onTap: () {
            setState(() {
              _showDetails = true;
            });
          },
          child: AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              final offset = Tween<double>(begin: 0, end: -10).evaluate(
                CurvedAnimation(
                  parent: _floatController,
                  curve: Curves.easeInOut,
                ),
              );
              return Transform.translate(
                offset: Offset(0, offset),
                child: child,
              );
            },
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: 300,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 17,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.68),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.75),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: AppColors.cyan,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Flexible(
                        child: Text(
                          _displayWord,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (widget.definition.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.definition.trim(),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  const Text(
                    'Tap to learn more',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DETAILS CARD
  // ===========================================================================

  Widget _buildDetailsCard() {
    final dark = ThemeProvider.isDark(context);

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showDetails = false;
          });
        },
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.65,
              ),
              padding: const EdgeInsets.fromLTRB(
                22,
                12,
                22,
                28,
              ),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.border(dark),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayWord,
                            style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showDetails = false;
                            });
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary(dark),
                          ),
                        ),
                      ],
                    ),
                    if (widget.phonetic.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.phonetic,
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (widget.partOfSpeech.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          widget.partOfSpeech,
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (widget.definition.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Meaning',
                        style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        widget.definition,
                        style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (widget.example.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Example',
                        style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: dark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '"${widget.example}"',
                          style: TextStyle(
                            color: AppColors.textSecondary(dark),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.volume_up_rounded,
                            label: 'Listen',
                            filled: true,
                            onTap: _listen,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: _saved
                                ? Icons.check_rounded
                                : Icons.bookmark_border_rounded,
                            label: _saved ? 'Saved' : 'Save',
                            onTap: _saved ? null : _saveWord,
                            dark: dark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.quiz_rounded,
                            label: 'Quiz',
                            onTap: _openQuiz,
                            dark: dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // LISTEN
  // ===========================================================================

  Future<void> _listen() async {
    final word = widget.word.trim();

    if (word.isEmpty) {
      return;
    }

    try {
      await _tts.stop();
      await _tts.speak(word);
    } catch (e) {
      debugPrint('AR pronunciation error: $e');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not play pronunciation.',
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _saveWord() async {
    if (_saving || _saved) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final persistentImagePath = await DetectorService.persistCutout(
        widget.imagePath,
        word: widget.word,
      );

      await FirestoreService.saveWord({
        'word': widget.word,
        'phonetic': widget.phonetic,
        'partOfSpeech': widget.partOfSpeech,
        'definition': widget.definition,
        'example': widget.example,
        'image_path': persistentImagePath ?? widget.imagePath ?? '',
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _saved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$_displayWord" saved!',
          ),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('AR save error: $e');

      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save this word.',
          ),
        ),
      );
    }
  }

  // ===========================================================================
  // QUIZ
  // ===========================================================================

  void _openQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QuizScreen(),
      ),
    );
  }

  // ===========================================================================
  // ACTION BUTTON
  // ===========================================================================

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required bool dark,
    bool filled = false,
  }) {
    final disabled = onTap == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: filled ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: filled ? AppColors.cyan : AppColors.border(dark),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_saving && label == 'Save')
              const SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            else
              Icon(
                icon,
                size: 18,
                color: filled
                    ? Colors.black
                    : disabled
                        ? AppColors.textSecondary(dark)
                        : AppColors.textPrimary(dark),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled
                    ? Colors.black
                    : disabled
                        ? AppColors.textSecondary(dark)
                        : AppColors.textPrimary(dark),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // -------------------------------------------------------------------
          // REAL AR CAMERA
          // -------------------------------------------------------------------

          ARKitSceneView(
            showFeaturePoints: false,
            showWorldOrigin: false,
            onARKitViewCreated: _onARKitViewCreated,
          ),

          // -------------------------------------------------------------------
          // TOP BAR
          // -------------------------------------------------------------------

          _buildTopBar(),

          // -------------------------------------------------------------------
          // WORD
          // -------------------------------------------------------------------

          if (!_showDetails) ...[
            _buildWordCard(),
          ],

          // -------------------------------------------------------------------
          // DETAILS
          // -------------------------------------------------------------------

          if (_showDetails) _buildDetailsCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // TOP BAR
  // ===========================================================================

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: 8,
            top: 4,
          ),
          child: Row(
            children: [
              Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.view_in_ar,
                      color: Colors.white,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AR $_displayWord',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _floatController.dispose();
    _tts.stop();

    _arkitController?.dispose();
    _arkitController = null;

    super.dispose();
  }
}
