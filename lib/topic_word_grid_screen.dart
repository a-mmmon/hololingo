import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'topics_data.dart';
import 'topic_complete_screen.dart';
import 'topic_capture_screen.dart';

class TopicWordGridScreen extends StatefulWidget {
  final TopicDef topic;

  const TopicWordGridScreen({
    super.key,
    required this.topic,
  });

  @override
  State<TopicWordGridScreen> createState() => _TopicWordGridScreenState();
}

class _TopicWordGridScreenState extends State<TopicWordGridScreen> {
  Set<String> _learned = {};
  Map<String, String> _imagePaths = {};

  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        FirestoreService.getTopicProgress(),
        FirestoreService.getSavedWords(),
      ]);

      final progress = results[0] as Map<String, dynamic>;
      final savedWords = results[1] as List<Map<String, dynamic>>;

      final learned = (progress[widget.topic.id] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      if (!mounted) return;

      final imagePaths = <String, String>{};
      for (final savedWord in savedWords) {
        final word = (savedWord['word'] ?? '').toString().toLowerCase();
        final imagePath = (savedWord['image_path'] ?? '').toString();
        if (word.isNotEmpty && imagePath.isNotEmpty) {
          imagePaths[word] = imagePath;
        }
      }

      setState(() {
        _learned = learned.toSet();
        _imagePaths = imagePaths;
        _loading = false;
      });
    } catch (e) {
      debugPrint(
        'TopicWordGridScreen load error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  // ============================================================
  // TAP WORD
  // ============================================================

  Future<void> _tapWord(TopicWord word) async {
    if (_learned.contains(word.word)) {
      return;
    }

    // ==========================================================
    // OPEN CAMERA CAPTURE SCREEN
    // ==========================================================

    final result = await Navigator.push<TopicCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TopicCaptureScreen(
          word: word,
          topicColor: widget.topic.color,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    // The word was successfully scanned.
    if (!result.success) {
      return;
    }

    final imagePath = await _persistImage(result.imagePath, word.word);

    // ==========================================================
    // SAVE PROGRESS
    // ==========================================================

    try {
      await FirestoreService.saveWord({
        'word': word.word,
        'image_path': imagePath ?? '',
      });

      await FirestoreService.markWordLearned(
        widget.topic.id,
        word.word,
      );
    } catch (e) {
      debugPrint(
        'markWordLearned error: $e',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save your progress.',
          ),
        ),
      );

      return;
    }

    if (!mounted) return;

    setState(() {
      _learned.add(word.word);
      if (imagePath != null) {
        _imagePaths[word.word.toLowerCase()] = imagePath;
      }
      _changed = true;
    });

    // ==========================================================
    // TOPIC COMPLETE
    // ==========================================================

    if (_learned.length >= widget.topic.words.length) {
      await _completeTopic();
    }
  }

  Future<String?> _persistImage(String? sourcePath, String word) async {
    if (sourcePath == null || sourcePath.isEmpty) {
      return null;
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      return null;
    }

    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final cutoutDirectory = Directory(
        '${supportDirectory.path}/topic_cutouts',
      );
      await cutoutDirectory.create(recursive: true);

      final safeWord =
          word.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final destination = File(
        '${cutoutDirectory.path}/${safeWord}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await source.copy(destination.path);
      return destination.path;
    } catch (e) {
      debugPrint('Could not persist topic cutout: $e');
      return null;
    }
  }

  // ============================================================
  // COMPLETE TOPIC
  // ============================================================

  Future<void> _completeTopic() async {
    const tokens = 10;
    const xp = 100;

    try {
      await FirestoreService.addRewards(
        tokens: tokens,
        xp: xp,
      );
    } catch (e) {
      debugPrint(
        'addRewards error: $e',
      );
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicCompleteScreen(
          topicName: widget.topic.name,
          wordsLearned: widget.topic.words.length,
          tokensEarned: tokens,
          xpEarned: xp,
        ),
      ),
    );

    if (mounted) {
      Navigator.pop(
        context,
        true,
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    final total = widget.topic.words.length;

    final done = _learned.length;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.cyan,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // HEADER
                  // ==================================================

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      0,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.textPrimary(
                              dark,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(
                              context,
                              _changed,
                            );
                          },
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.topic.name,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary(
                                    dark,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                height: 3,
                              ),
                              Text(
                                '$total words · $done done',
                                style: TextStyle(
                                  color: AppColors.textSecondary(
                                    dark,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ==================================================
                  // PROGRESS
                  // ==================================================

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : done / total,
                        backgroundColor: AppColors.secondary(
                          dark,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.cyan,
                        ),
                        minHeight: 7,
                      ),
                    ),
                  ),

                  // ==================================================
                  // 9 WORDS / 3 x 3 GRID
                  // ==================================================

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        4,
                        20,
                        16,
                      ),
                      child: LayoutBuilder(
                        builder: (
                          context,
                          constraints,
                        ) {
                          const columns = 3;
                          const rows = 3;
                          const spacing = 12.0;

                          final tileHeight =
                              (constraints.maxHeight - spacing * (rows - 1)) /
                                  rows;

                          return GridView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              mainAxisExtent: tileHeight,
                            ),
                            itemCount: total > 9 ? 9 : total,
                            itemBuilder: (
                              context,
                              index,
                            ) {
                              final word = widget.topic.words[index];

                              final learned = _learned.contains(
                                word.word,
                              );

                              final imagePath =
                                  _imagePaths[word.word.toLowerCase()];

                              final isNext = index == _learned.length;

                              return _WordTile(
                                word: word,
                                learned: learned,
                                isNext: isNext,
                                imagePath: imagePath,
                                topicColor: widget.topic.color,
                                dark: dark,
                                onTap: () => _tapWord(
                                  word,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  // ==================================================
                  // BACK BUTTON
                  // ==================================================

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _changed,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: AppColors.cyan,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              14,
                            ),
                          ),
                        ),
                        child: const Text(
                          'Back to Topics',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
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
// WORD TILE
// ================================================================

class _WordTile extends StatelessWidget {
  final TopicWord word;
  final bool learned;
  final bool isNext;
  final String? imagePath;
  final Color topicColor;
  final bool dark;
  final VoidCallback? onTap;

  const _WordTile({
    required this.word,
    required this.learned,
    required this.isNext,
    required this.imagePath,
    required this.topicColor,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = learned
        ? Colors.green
        : isNext
            ? topicColor
            : AppColors.border(dark);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: isNext ? 2 : 1.3,
          ),
          boxShadow: isNext
              ? [
                  BoxShadow(
                    color: topicColor.withValues(
                      alpha: 0.15,
                    ),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(7),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (learned && imagePath != null && File(imagePath!).existsSync())
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Image.file(
                      File(imagePath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Text(
                  word.word,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: learned
                        ? Colors.green
                        : AppColors.textPrimary(
                            dark,
                          ),
                  ),
                ),

              const SizedBox(
                height: 5,
              ),

              // Translation
              Text(
                word.translation,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(
                    dark,
                  ),
                ),
              ),

              const SizedBox(
                height: 8,
              ),

              if (learned)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 21,
                )
              else
                Icon(
                  Icons.photo_camera_rounded,
                  color: topicColor,
                  size: 21,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
