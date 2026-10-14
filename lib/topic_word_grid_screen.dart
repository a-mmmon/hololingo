import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';
import 'dictionary_service.dart';
import 'firestore_service.dart';
import 'topics_data.dart';
import 'topic_complete_screen.dart';
import 'topic_capture_screen.dart';

class TopicWordGridScreen extends StatefulWidget {
  final TopicDef topic;

  // Name of the topic that unlocks after this one, shown on the
  // completion screen. Null when this is the last topic.
  final String? nextTopicName;

  const TopicWordGridScreen({
    super.key,
    required this.topic,
    this.nextTopicName,
  });

  @override
  State<TopicWordGridScreen> createState() => _TopicWordGridScreenState();
}

class _TopicWordGridScreenState extends State<TopicWordGridScreen> {
  Set<String> _learned = {};
  Map<String, String> _imagePaths = {};
  Map<String, String> _imageUrls = {};
  Map<String, String> _imageBase64s = {};

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
      final imageUrls = <String, String>{};
      final imageBase64s = <String, String>{};

      for (final savedWord in savedWords) {
        final word = (savedWord['word'] ?? '').toString().toLowerCase();
        final imageBase64 = (savedWord['image_base64'] ?? '').toString();
        final imageUrl = (savedWord['image_url'] ?? '').toString();
        final imagePath = (savedWord['image_path'] ?? '').toString();

        if (word.isEmpty) continue;

        if (imageBase64.isNotEmpty) {
          imageBase64s[word] = imageBase64;
        }

        if (imageUrl.isNotEmpty) {
          imageUrls[word] = imageUrl;
        }

        // image_base64 is embedded in the document and always durable;
        // image_url would be Cloud Storage (not currently used); image_path
        // is only a same-install local fallback for words saved before
        // embedding existed, or if encoding failed.
        if (imagePath.isNotEmpty) {
          final persistentPath = await _persistImage(imagePath, word);
          final usablePath = persistentPath ?? imagePath;
          imagePaths[word] = usablePath;

          if (persistentPath != null && persistentPath != imagePath) {
            await FirestoreService.updateSavedWord(
              word,
              {'image_path': persistentPath},
            );
          }
        }
      }

      setState(() {
        _learned = learned.toSet();
        _imagePaths = imagePaths;
        _imageUrls = imageUrls;
        _imageBase64s = imageBase64s;
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
    final wasAlreadyLearned = _learned.contains(word.word);

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

    if (!result.success) {
      return;
    }

    final imagePath = await _persistImage(result.imagePath, word.word);

    if (!mounted) return;

    // A capture whose image couldn't be saved must not be marked learned —
    // otherwise the tile ends up green/checked with no cutout to show,
    // which looks broken even though progress was technically recorded.
    if (imagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save the photo. Please try capturing again.',
          ),
        ),
      );
      return;
    }

    // Topic capture is its own feature, separate from the AR scan flow —
    // success is shown by the word tile itself (green border + cutout
    // image once learned), not by opening the AR camera screen.

    // ==========================================================
    // SAVE PROGRESS
    // ==========================================================

    try {
      // Save the same details a Scan save stores, so topic words show
      // their phonetic, example and pronunciation in Review flashcards.
      // The capture screen normally looked them up already; fall back to
      // the dictionary if the learner confirmed before that finished.
      var phonetic = result.phonetic ?? '';
      var definition = result.definition ?? '';
      var example = result.example ?? '';
      var partOfSpeech = result.partOfSpeech ?? '';
      if (phonetic.isEmpty || definition.isEmpty || example.isEmpty) {
        final info = await DictionaryService.getWordInfo(word.word);
        if (phonetic.isEmpty) phonetic = info['phonetic'] ?? '';
        if (definition.isEmpty) definition = info['definition'] ?? '';
        if (example.isEmpty) example = info['example'] ?? '';
        if (partOfSpeech.isEmpty) partOfSpeech = info['partOfSpeech'] ?? '';
      }

      await FirestoreService.saveWord({
        'word': word.word,
        'image_path': imagePath,
        'phonetic': phonetic,
        'partOfSpeech': partOfSpeech,
        'definition': definition,
        'example': example,
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
      _imagePaths[word.word.toLowerCase()] = imagePath;
      _changed = true;
    });

    // ==========================================================
    // TOPIC COMPLETE
    // ==========================================================

    if (!wasAlreadyLearned && _learned.length >= widget.topic.words.length) {
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
      final cutoutDirectoryPath = '${supportDirectory.path}/topic_cutouts';

      if (sourcePath.startsWith('$cutoutDirectoryPath/')) {
        return sourcePath;
      }

      final cutoutDirectory = Directory(
        cutoutDirectoryPath,
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

    final goNext = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TopicCompleteScreen(
          topicName: widget.topic.name,
          wordsLearned: widget.topic.words.length,
          tokensEarned: tokens,
          xpEarned: xp,
          nextTopicName: widget.nextTopicName,
        ),
      ),
    );

    // 'next' tells the Topics screen to open the following topic right
    // away; true just asks it to refresh the map.
    if (mounted) {
      Navigator.pop(
        context,
        goNext == true ? 'next' : true,
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
    final visibleCount = total > 9 ? 9 : total;

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
                                '$visibleCount words · $done done',
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
                            itemCount: visibleCount,
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
                              final imageUrl =
                                  _imageUrls[word.word.toLowerCase()];
                              final imageBase64 =
                                  _imageBase64s[word.word.toLowerCase()];
                              return _WordTile(
                                word: word,
                                learned: learned,
                                imagePath: imagePath,
                                imageUrl: imageUrl,
                                imageBase64: imageBase64,
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
  final String? imagePath;
  final String? imageUrl;
  final String? imageBase64;
  final Color topicColor;
  final bool dark;
  final VoidCallback? onTap;

  const _WordTile({
    required this.word,
    required this.learned,
    required this.imagePath,
    required this.imageUrl,
    required this.imageBase64,
    required this.topicColor,
    required this.dark,
    required this.onTap,
  });

  Widget? _buildImage() {
    final base64 = imageBase64?.trim() ?? '';
    final url = imageUrl?.trim() ?? '';
    final path = imagePath?.trim() ?? '';

    if (base64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(base64),
          fit: BoxFit.contain,
        );
      } catch (_) {
        // Fall through to the other sources below.
      }
    }

    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          if (path.isNotEmpty && File(path).existsSync()) {
            return Image.file(File(path), fit: BoxFit.contain);
          }
          return const SizedBox.shrink();
        },
      );
    }

    if (path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.contain);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = learned ? Colors.green : AppColors.border(dark);
    final image = learned ? _buildImage() : null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: 1.3,
          ),
          boxShadow: null,
        ),
        padding: const EdgeInsets.all(7),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (image != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: image,
                  ),
                ),

              const SizedBox(
                height: 5,
              ),

              // Keep the English object name visible below its image.
              Text(
                word.word,
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

              if (learned && imagePath != null && File(imagePath!).existsSync())
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
