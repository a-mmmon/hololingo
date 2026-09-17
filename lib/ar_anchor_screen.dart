import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:arkit_plugin/arkit_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

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
  // The GLB's height is roughly 4.2 source units. Keep these together so the
  // physical size and follow distance can be tuned on a real iPhone.
  static const double _mascotScale = 0.24;
  // Distance Holo hovers in front of the camera at all times (world units).
  static const double _mascotFollowDistance = 1.35;
  // Constant world-space vertical offset, so Holo sits a bit below eye level
  // and doesn't tilt sideways when the phone rolls.
  static const double _mascotVerticalOffset = -0.28;
  // The GLB's own origin is at its feet (measured bounding box in source
  // units: z from -0.337 to 4.410, i.e. roughly 4.75 units tall), not its
  // center. Left alone, the feet sit almost exactly at the anchor point and
  // the head/antennae end up ~0.57m above eye level — well outside a phone
  // camera's vertical field of view, which is why only the arm/hand region
  // (the only part still low enough) was ever visible. This shifts the
  // model down by half its scaled height so it's vertically centered on the
  // anchor instead of foot-anchored to it.
  static const double _mascotCenteringOffset = -0.489;
  static const double _mascotAnimationAmplitude = 0.04;
  // How often (seconds of ARKit render time) we re-fetch the camera pose to
  // reposition Holo. pointOfViewTransform() is a platform-channel round trip,
  // so this stays well under 60 Hz — still smooth for a slow-drifting
  // companion, without spamming the channel every frame.
  static const double _followUpdateInterval = 0.12;
  static const String _worldAnchorNodeName = 'holo_world_anchor';
  static const String _mascotVisualNodeName = 'holo_mascot_visual';

  ARKitController? _arkitController;
  ARKitNode? _worldAnchorNode;
  ARKitGltfNode? _mascotVisual;
  late final AnimationController _floatController;

  double _lastFollowUpdateTime = -1;
  bool _followUpdateInFlight = false;

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
    )
      ..addListener(_updateMascotLocalAnimation)
      ..repeat(reverse: true);
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

  /// This changes only the GLB child's local transform. The parent stays at
  /// its ARKit world location, so bobbing never turns into screen-fixed motion.
  void _updateMascotLocalAnimation() {
    final mascot = _mascotVisual;
    if (mascot == null) {
      return;
    }

    final bob =
        math.sin(_floatController.value * math.pi) * _mascotAnimationAmplitude;
    mascot.position = vector.Vector3(0, _mascotCenteringOffset + bob, 0);
  }

  // ===========================================================================
  // AR INITIALIZATION
  // ===========================================================================

  Future<void> _onARKitViewCreated(
    ARKitController controller,
  ) async {
    _arkitController = controller;
    controller.updateAtTime = _onFrameUpdate;

    // This parent node is repositioned every frame (see _followCamera) to
    // stay a fixed distance in front of the camera, so Holo reads as a HUD
    // companion that travels with the phone rather than a real-world anchor
    // you can walk away from. Its GLB child is then animated locally for the
    // idle bob without touching that follow position.
    final worldAnchor = ARKitNode(
      name: _worldAnchorNodeName,
      position: vector.Vector3(
        0,
        _mascotVerticalOffset,
        -_mascotFollowDistance,
      ),
    );
    final mascotVisual = ARKitGltfNode(
      name: _mascotVisualNodeName,
      assetType: AssetType.flutterAsset,
      url: 'assets/3D/holo_mascot.glb',
      scale: vector.Vector3.all(_mascotScale),
      // The supplied GLB is Z-up; SceneKit/ARKit uses Y-up.
      eulerAngles: vector.Vector3(-math.pi / 2, 0, 0),
      // Matches the resting position _updateMascotLocalAnimation maintains,
      // so there's no one-frame jump from foot-anchored to centered once the
      // float animation starts ticking.
      position: vector.Vector3(0, _mascotCenteringOffset, 0),
    );
    _mascotVisual = mascotVisual;
    _worldAnchorNode = worldAnchor;

    try {
      await controller.add(worldAnchor);
      await controller.add(
        mascotVisual,
        parentNodeName: worldAnchor.name,
      );
    } catch (error) {
      _mascotVisual = null;
      _worldAnchorNode = null;
      debugPrint('Could not add camera-following Holo model: $error');
    }
  }

  // ===========================================================================
  // CAMERA FOLLOW (keeps Holo pinned in front of the phone, not the world)
  // ===========================================================================

  void _onFrameUpdate(double time) {
    if (_followUpdateInFlight) {
      return;
    }

    if (_lastFollowUpdateTime >= 0 &&
        time - _lastFollowUpdateTime < _followUpdateInterval) {
      return;
    }

    _lastFollowUpdateTime = time;
    _followUpdateInFlight = true;

    _followCamera().whenComplete(() {
      _followUpdateInFlight = false;
    });
  }

  Future<void> _followCamera() async {
    final controller = _arkitController;
    final anchor = _worldAnchorNode;

    if (controller == null || anchor == null) {
      return;
    }

    try {
      final cameraTransform = await controller.pointOfViewTransform();

      if (cameraTransform == null || !mounted) {
        return;
      }

      final cameraPosition = cameraTransform.getTranslation();

      // SceneKit/ARKit cameras look down their local -Z axis, so the world
      // forward direction is the negated 3rd column of the transform.
      final zAxis = cameraTransform.getColumn(2);
      final forward = vector.Vector3(-zAxis.x, -zAxis.y, -zAxis.z);

      if (forward.length2 == 0) {
        return;
      }

      forward.normalize();

      final targetPosition = cameraPosition +
          forward * _mascotFollowDistance +
          vector.Vector3(0, _mascotVerticalOffset, 0);

      // Position-only follow. Rotating Holo to face the camera would need
      // knowing which local axis the GLB was authored to treat as "front",
      // which isn't known — guessing it produced a wrong-facing, contorted
      // look. Leaving rotation untouched keeps the model in its known-good
      // orientation; it still travels with the phone via the position update.
      anchor.position = targetPosition;
    } catch (error) {
      debugPrint('Holo camera-follow update error: $error');
    }
  }

  // ===========================================================================
  // AR CAMERA VIEW
  // ===========================================================================

  Widget _buildArView() {
    return ARKitSceneView(
      // Explicit world tracking and horizontal plane detection improve
      // ARKit's understanding of the room. Holo itself is repositioned every
      // frame in _followCamera to stay pinned in front of the camera.
      configuration: ARKitConfiguration.worldTracking,
      planeDetection: ARPlaneDetection.horizontal,
      showFeaturePoints: false,
      showWorldOrigin: false,
      onARKitViewCreated: _onARKitViewCreated,
    );
  }

  // ===========================================================================
  // TOP AR LABEL
  // ===========================================================================

  Widget _buildWordCard() {
    return GestureDetector(
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
                  if (widget.imagePath != null &&
                      File(widget.imagePath!).existsSync()) ...[
                    SizedBox(
                      width: 120,
                      height: 100,
                      child: Image.file(
                        File(widget.imagePath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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

          _buildArView(),

          // -------------------------------------------------------------------
          // TOP BAR + WORD CARD (one top-anchored column so the card can
          // never overlap the back button, regardless of device/text size)
          // -------------------------------------------------------------------

          _buildTopSection(),

          // -------------------------------------------------------------------
          // DETAILS
          // -------------------------------------------------------------------

          if (_showDetails) _buildDetailsCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // TOP SECTION (back button + word chip, then the card directly beneath —
  // one top-anchored column so the card can never overlap the back button)
  // ===========================================================================

  Widget _buildTopSection() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBarRow(),
            if (!_showDetails) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(child: _buildWordCard()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBarRow() {
    return Padding(
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
    _mascotVisual = null;
    _worldAnchorNode = null;

    super.dispose();
  }
}
