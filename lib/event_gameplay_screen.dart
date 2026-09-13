import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'detector_service.dart';
import 'firestore_service.dart';

class EventGameplayScreen extends StatefulWidget {
  final String eventId;
  final String eventName;
  final Map<String, dynamic> group;

  const EventGameplayScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.group,
  });

  @override
  State<EventGameplayScreen> createState() =>
      _EventGameplayScreenState();
}

class _EventGameplayScreenState
    extends State<EventGameplayScreen> {
  CameraController? _camera;

  List<Map<String, dynamic>> _targets = [];

  Map<String, dynamic> _event =
      {};

  Map<String, dynamic> _group =
      {};

  bool _loading = true;
  bool _cameraReady = false;
  bool _scanning = false;
  bool _finished = false;

  String? _detected;

  Timer? _pollTimer;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    _group = {
      ...widget.group,
    };

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await DetectorService.loadModel();

      await _loadEventData();

      await _initializeCamera();

      _startPolling();
    } catch (e) {
      debugPrint(
        'Event gameplay init error: $e',
      );
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  // ============================================================
  // EVENT DATA
  // ============================================================

  Future<void> _loadEventData() async {
    final definition =
        await FirestoreService
            .getEventDefinition(
      widget.eventId,
    );

    final targets =
        await FirestoreService
            .getEventTargets(
      widget.eventId,
    );

    if (!mounted) return;

    setState(() {
      _event =
          definition ?? {};

      _targets = targets;
    });
  }

  // ============================================================
  // CAMERA
  // ============================================================

  Future<void> _initializeCamera() async {
    final cameras =
        await availableCameras();

    if (cameras.isEmpty) {
      return;
    }

    CameraDescription selected =
        cameras.first;

    for (final camera
        in cameras) {
      if (camera.lensDirection ==
          CameraLensDirection.back) {
        selected = camera;
        break;
      }
    }

    final controller =
        CameraController(
      selected,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _camera = controller;

    await controller.initialize();

    if (!mounted) return;

    setState(() {
      _cameraReady = true;
    });
  }

  // ============================================================
  // POLLING
  // ============================================================

  void _startPolling() {
    _pollTimer =
        Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshGroup(),
    );
  }

  Future<void> _refreshGroup() async {
    if (!mounted ||
        _finished) {
      return;
    }

    try {
      final group =
          await FirestoreService
              .getEventGroup(
        widget.eventId,
        widget.group['id']
            .toString(),
      );

      if (!mounted ||
          group == null) {
        return;
      }

      setState(() {
        _group = group;
      });

      _checkFinished();
    } catch (e) {
      debugPrint(
        'Gameplay group refresh error: $e',
      );
    }
  }

  // ============================================================
  // CURRENT TARGET
  // ============================================================

  Map<String, dynamic>?
      get _currentTarget {
    if (_targets.isEmpty) {
      return null;
    }

    final completed =
        _completedTargetIds;

    for (int i = 0;
        i < _targets.length;
        i++) {
      final id =
          _targets[i]['id']
              ?.toString();

      if (id == null ||
          !completed.contains(id)) {
        _currentIndex = i;
        return _targets[i];
      }
    }

    return null;
  }

  List<String> get _completedTargetIds {
    final raw =
        _group[
            'completed_target_ids'];

    if (raw is! List) {
      return [];
    }

    return raw
        .map(
          (e) => e.toString(),
        )
        .toList();
  }

  int get _score {
    final value =
        _group['score'];

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ??
              '',
        ) ??
        0;
  }

  // ============================================================
  // SCAN
  // ============================================================

  Future<void> _scan() async {
    if (_scanning ||
        !_cameraReady ||
        _finished) {
      return;
    }

    final target =
        _currentTarget;

    if (target == null) {
      _finishGame();

      return;
    }

    final controller =
        _camera;

    if (controller == null ||
        !controller.value
            .isInitialized) {
      return;
    }

    setState(() {
      _scanning = true;
      _detected = null;
    });

    try {
      final image =
          await controller.takePicture();

      final result =
          await DetectorService
              .detectObject(
        image.path,
      );

      if (!mounted) return;

      if (result == null ||
          result.trim().isEmpty) {
        setState(() {
          _scanning = false;
        });

        _showMessage(
          'No object detected. Try again.',
          false,
        );

        return;
      }

      final detected =
          result.trim();

      setState(() {
        _detected = detected;
        _scanning = false;
      });

      await _checkDetectedObject(
        detected,
        target,
      );
    } catch (e) {
      debugPrint(
        'Event scan error: $e',
      );

      if (!mounted) return;

      setState(() {
        _scanning = false;
      });

      _showMessage(
        'Could not scan the object.',
        false,
      );
    }
  }

  // ============================================================
  // CHECK DETECTION
  // ============================================================

  Future<void>
      _checkDetectedObject(
    String detected,
    Map<String, dynamic> target,
  ) async {
    final normalized =
        detected.trim().toLowerCase();

    final label =
        target['label']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    final word =
        target['word']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

    final matches =
        normalized == label ||
            normalized == word;

    if (!matches) {
      _showMessage(
        'Detected "$detected". Find ${target['word']}.',
        false,
      );

      return;
    }

    final targetId =
        target['id']?.toString();

    if (targetId == null) {
      return;
    }

    final points =
        (target['points'] as num?)
                ?.toInt() ??
            100;

    final completed =
        await FirestoreService
            .completeEventTarget(
      eventId:
          widget.eventId,
      groupId:
          widget.group['id']
              .toString(),
      targetId:
          targetId,
      points:
          points,
    );

    if (!mounted) return;

    if (completed) {
      _showCorrect(
        target['word']
                ?.toString() ??
            detected,
      );
    } else {
      _showMessage(
        'Your team already found this target.',
        true,
      );
    }

    await _refreshGroup();
  }

  // ============================================================
  // CORRECT
  // ============================================================

  Future<void> _showCorrect(
    String word,
  ) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              22,
            ),
          ),
          content:
              Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons
                    .check_circle_rounded,
                color:
                    Colors.green,
                size: 64,
              ),
              const SizedBox(
                height: 12,
              ),
              const Text(
                'Found!',
                style:
                    TextStyle(
                  fontSize: 25,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              Text(
                word,
                style:
                    const TextStyle(
                  color:
                      AppColors.cyan,
                  fontSize: 21,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width:
                  double.infinity,
              child:
                  ElevatedButton(
                onPressed: () =>
                    Navigator.pop(
                  dialogContext,
                ),
                child:
                    const Text(
                  'Continue',
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    _checkFinished();
  }

  // ============================================================
  // FINISHED
  // ============================================================

  void _checkFinished() {
    if (_targets.isEmpty) {
      return;
    }

    final completed =
        _completedTargetIds;

    if (completed.length >=
        _targets.length) {
      _finishGame();
    }
  }

  Future<void> _finishGame() async {
    if (_finished) return;

    _finished = true;

    _pollTimer?.cancel();

    final score =
        _score;

    final tokens =
        _targets.length * 5;

    try {
      await FirestoreService
          .addRewards(
        tokens: tokens,
        xp: score,
      );
    } catch (e) {
      debugPrint(
        'Event reward error: $e',
      );
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dark =
            ThemeProvider.isDark(
          dialogContext,
        );

        return AlertDialog(
          backgroundColor:
              AppColors.card(dark),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              22,
            ),
          ),
          content:
              Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons
                    .emoji_events_rounded,
                color:
                    Color(0xFFFFD54F),
                size: 72,
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                'Event Complete!',
                style:
                    TextStyle(
                  color: AppColors
                      .textPrimary(
                    dark,
                  ),
                  fontSize: 24,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),

              const SizedBox(
                height: 18,
              ),

              Text(
                'Team Score: $score',
                style:
                    TextStyle(
                  color: AppColors
                      .textPrimary(
                    dark,
                  ),
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(
                height: 6,
              ),

              Text(
                '+$tokens Tokens',
                style:
                    const TextStyle(
                  color:
                      AppColors.cyan,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width:
                  double.infinity,
              child:
                  ElevatedButton(
                onPressed: () =>
                    Navigator.pop(
                  dialogContext,
                ),
                child:
                    const Text(
                  'Done',
                ),
              ),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    Navigator.pop(context);
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
    bool success,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content:
            Text(message),
        backgroundColor:
            success
                ? Colors.green
                : Colors.orange,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final dark =
        ThemeProvider.isDark(
      context,
    );

    if (_loading) {
      return Scaffold(
        backgroundColor:
            AppColors.bg(dark),
        body: const Center(
          child:
              CircularProgressIndicator(
            color:
                AppColors.cyan,
          ),
        ),
      );
    }

    final eventType =
        _event['type']
                ?.toString() ??
            'unknown';

    if (eventType ==
        'treasure_hunt') {
      return _buildTreasureHunt(
        dark,
      );
    }

    return _buildUnsupportedEvent(
      dark,
      eventType,
    );
  }

  // ============================================================
  // TREASURE HUNT UI
  // ============================================================

  Widget _buildTreasureHunt(
    bool dark,
  ) {
    final target =
        _currentTarget;

    if (target == null) {
      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) => _finishGame(),
      );

      return Scaffold(
        backgroundColor:
            Colors.black,
        body: const Center(
          child:
              CircularProgressIndicator(
            color:
                AppColors.cyan,
          ),
        ),
      );
    }

    final targetWord =
        target['word']
                ?.toString() ??
            'Object';

    final completedCount =
        _completedTargetIds
            .length;

    return Scaffold(
      backgroundColor:
          Colors.black,

      body: SafeArea(
        child: Stack(
          children: [
            // CAMERA
            Positioned.fill(
              child:
                  _cameraReady &&
                          _camera != null
                      ? CameraPreview(
                          _camera!,
                        )
                      : Container(
                          color:
                              Colors.black,
                          child:
                              const Center(
                            child:
                                CircularProgressIndicator(
                              color:
                                  AppColors.cyan,
                            ),
                          ),
                        ),
            ),

            // GRADIENT
            Positioned.fill(
              child:
                  IgnorePointer(
                child:
                    DecoratedBox(
                  decoration:
                      BoxDecoration(
                    gradient:
                        LinearGradient(
                      begin: Alignment
                          .topCenter,
                      end: Alignment
                          .bottomCenter,
                      colors: [
                        Colors.black
                            .withOpacity(
                          0.65,
                        ),
                        Colors.transparent,
                        Colors.black
                            .withOpacity(
                          0.82,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // TOP BAR
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _circleButton(
                    Icons
                        .arrow_back_rounded,
                    () {
                      _pollTimer
                          ?.cancel();

                      Navigator.pop(
                        context,
                      );
                    },
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          widget.eventName
                              .toUpperCase(),
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            color:
                                Colors.white,
                            fontSize: 13,
                            fontWeight:
                                FontWeight
                                    .w900,
                            letterSpacing:
                                1.3,
                          ),
                        ),
                        Text(
                          _event['type']
                                  ?.toString() ??
                              '',
                          style:
                              const TextStyle(
                            color:
                                Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _scoreChip(
                    Icons
                        .star_rounded,
                    '$_score',
                  ),
                ],
              ),
            ),

            // TARGET
            Positioned(
              top: 92,
              left: 20,
              right: 20,
              child:
                  Container(
                padding:
                    const EdgeInsets
                        .all(
                  17,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.black
                      .withOpacity(
                    0.70,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                  border:
                      Border.all(
                    color: AppColors.cyan
                        .withOpacity(
                      0.35,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration:
                          BoxDecoration(
                        color: AppColors
                            .cyan
                            .withOpacity(
                          0.13,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          15,
                        ),
                      ),
                      child:
                          const Icon(
                        Icons
                            .search_rounded,
                        color:
                            AppColors.cyan,
                        size: 28,
                      ),
                    ),

                    const SizedBox(
                      width: 13,
                    ),

                    Expanded(
                      child:
                          Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const Text(
                            'FIND THIS OBJECT',
                            style:
                                TextStyle(
                              color:
                                  Colors.white54,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight
                                      .w800,
                              letterSpacing:
                                  1.2,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            targetWord,
                            style:
                                const TextStyle(
                              color:
                                  Colors.white,
                              fontSize: 22,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),
                        ],
                      ),
                    ),

                    Text(
                      '${completedCount + 1}/${_targets.length}',
                      style:
                          const TextStyle(
                        color:
                            Colors.white70,
                        fontWeight:
                            FontWeight
                                .w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // SCAN FRAME
            Positioned(
              left: 32,
              right: 32,
              top: MediaQuery.of(
                        context,
                      )
                          .size
                          .height *
                      0.34,
              bottom: MediaQuery.of(
                        context,
                      )
                          .size
                          .height *
                      0.32,
              child:
                  IgnorePointer(
                child:
                    CustomPaint(
                  painter:
                      _ScanFramePainter(),
                ),
              ),
            ),

            // BOTTOM
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child:
                  Container(
                padding:
                    const EdgeInsets
                        .fromLTRB(
                  16,
                  14,
                  16,
                  16,
                ),
                decoration:
                    BoxDecoration(
                  color: Colors.black
                      .withOpacity(
                    0.76,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    22,
                  ),
                ),
                child:
                    Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons
                              .groups_rounded,
                          color:
                              AppColors.cyan,
                          size: 18,
                        ),
                        const SizedBox(
                          width: 7,
                        ),
                        const Text(
                          'Team',
                          style:
                              TextStyle(
                            color:
                                Colors.white,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_members.length}/4 players',
                          style:
                              const TextStyle(
                            color:
                                Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Row(
                      children: [
                        const Icon(
                          Icons
                              .check_circle_outline_rounded,
                          color:
                              Colors.greenAccent,
                          size: 17,
                        ),
                        const SizedBox(
                          width: 6,
                        ),
                        Text(
                          '$completedCount / ${_targets.length} targets found',
                          style:
                              const TextStyle(
                            color:
                                Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(
                      height: 14,
                    ),

                    SizedBox(
                      width:
                          double.infinity,
                      height: 54,
                      child:
                          ElevatedButton.icon(
                        onPressed:
                            _scanning ||
                                    !_cameraReady
                                ? null
                                : _scan,
                        icon:
                            _scanning
                                ? const SizedBox(
                                    width:
                                        20,
                                    height:
                                        20,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth:
                                          2.5,
                                      color:
                                          Colors.black,
                                    ),
                                  )
                                : const Icon(
                                    Icons
                                        .center_focus_strong_rounded,
                                  ),
                        label: Text(
                          _scanning
                              ? 'Scanning...'
                              : 'Scan $targetWord',
                          style:
                              const TextStyle(
                            fontSize:
                                16,
                            fontWeight:
                                FontWeight
                                    .w800,
                          ),
                        ),
                        style:
                            ElevatedButton
                                .styleFrom(
                          backgroundColor:
                              AppColors
                                  .cyan,
                          foregroundColor:
                              Colors.black,
                          disabledBackgroundColor:
                              Colors.white24,
                          disabledForegroundColor:
                              Colors.white54,
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 7,
                    ),

                    const Text(
                      'Point the camera at the target object and scan.',
                      style:
                          TextStyle(
                        color:
                            Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UNSUPPORTED EVENT TYPE
  // ============================================================

  Widget _buildUnsupportedEvent(
    bool dark,
    String type,
  ) {
    return Scaffold(
      backgroundColor:
          AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor:
            AppColors.bg(dark),
        title: Text(
          widget.eventName,
        ),
      ),
      body: Center(
        child: Padding(
          padding:
              const EdgeInsets.all(
            30,
          ),
          child:
              Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons
                    .construction_rounded,
                color:
                    AppColors.cyan,
                size: 60,
              ),
              const SizedBox(
                height: 18,
              ),
              Text(
                'Event type: $type',
                style:
                    TextStyle(
                  color:
                      AppColors.textPrimary(
                    dark,
                  ),
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                'This event type does not have a gameplay module yet.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  color:
                      AppColors.textSecondary(
                    dark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MEMBERS
  // ============================================================

  List<Map<String, dynamic>>
      get _members {
    final raw =
        _group['members'];

    if (raw is! List) {
      return [];
    }

    return raw
        .whereType<Map>()
        .map(
          (item) =>
              Map<String,
                  dynamic>.from(
            item,
          ),
        )
        .toList();
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget _circleButton(
    IconData icon,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.black
          .withOpacity(
        0.55,
      ),
      shape:
          const CircleBorder(),
      child: InkWell(
        customBorder:
            const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            icon,
            color:
                Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _scoreChip(
    IconData icon,
    String text,
  ) {
    return Container(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration:
          BoxDecoration(
        color: Colors.black
            .withOpacity(
          0.60,
        ),
        borderRadius:
            BorderRadius.circular(
          13,
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                Colors.white,
            size: 15,
          ),
          const SizedBox(
            width: 5,
          ),
          Text(
            text,
            style:
                const TextStyle(
              color:
                  Colors.white,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }
}

// ================================================================
// SCAN FRAME
// ================================================================

class _ScanFramePainter
    extends CustomPainter {
  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          AppColors.cyan
      ..strokeWidth = 3
      ..style =
          PaintingStyle.stroke
      ..strokeCap =
          StrokeCap.round;

    const corner = 28.0;

    canvas.drawLine(
      const Offset(
        0,
        corner,
      ),
      Offset.zero,
      paint,
    );

    canvas.drawLine(
      Offset.zero,
      const Offset(
        corner,
        0,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width -
            corner,
        0,
      ),
      Offset(
        size.width,
        0,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width,
        0,
      ),
      Offset(
        size.width,
        corner,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        0,
        size.height -
            corner,
      ),
      Offset(
        0,
        size.height,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        0,
        size.height,
      ),
      Offset(
        corner,
        size.height,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width -
            corner,
        size.height,
      ),
      Offset(
        size.width,
        size.height,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width,
        size.height,
      ),
      Offset(
        size.width,
        size.height -
            corner,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}