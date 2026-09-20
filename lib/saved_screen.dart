import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'dictionary_service.dart';
import 'firestore_service.dart';
import 'vocab_detail_screen.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    try {
      final words = await FirestoreService.getSavedWords();
      final fixedWords = <Map<String, dynamic>>[];

      for (final item in words) {
        final word = Map<String, dynamic>.from(item);
        final wordName = (word['word'] ?? '').toString();
        final definition = (word['definition'] ?? '').toString();

        // Repair old saved words that were stored with an empty/broken
        // definition, such as the earlier "Could not load definition" data.
        if (wordName.isNotEmpty &&
            (definition.trim().isEmpty ||
                definition.toLowerCase().contains('could not load definition') ||
                definition.toLowerCase().contains(
                  'vocabulary information has not been added',
                ))) {
          try {
            final info = await DictionaryService.getWordInfo(wordName);
            word['phonetic'] = info['phonetic'] ?? word['phonetic'] ?? '';
            word['definition'] = info['definition'] ?? word['definition'] ?? '';
            word['example'] = info['example'] ?? word['example'] ?? '';

            await FirestoreService.updateSavedWord(wordName, {
              'phonetic': word['phonetic'],
              'definition': word['definition'],
              'example': word['example'],
            });
          } catch (e) {
            debugPrint('Could not repair saved word $wordName: $e');
          }
        }

        fixedWords.add(word);
      }

      if (!mounted) return;
      setState(() {
        _words = fixedWords;
        _loading = false;
      });
    } catch (e) {
      debugPrint('SavedScreen load error: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load saved words: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredWords {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _words;
    return _words.where((word) {
      final name = (word['word'] ?? '').toString().toLowerCase();
      final definition = (word['definition'] ?? '').toString().toLowerCase();
      return name.contains(q) || definition.contains(q);
    }).toList();
  }

  Future<void> _openWord(Map<String, dynamic> word) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VocabDetailScreen(
          word: (word['word'] ?? '').toString(),
          phonetic: (word['phonetic'] ?? '').toString(),
          definition: (word['definition'] ?? '').toString(),
          example: (word['example'] ?? '').toString(),
          imagePath: (word['image_path'] ?? '').toString().isEmpty
              ? null
              : (word['image_path'] ?? '').toString(),
          imageUrl: (word['image_url'] ?? '').toString().isEmpty
              ? null
              : (word['image_url'] ?? '').toString(),
          imageBase64: (word['image_base64'] ?? '').toString().isEmpty
              ? null
              : (word['image_base64'] ?? '').toString(),
          initiallySaved: true,
        ),
      ),
    );
    _loadWords();
  }

  Future<void> _deleteWord(String word) async {
    try {
      await FirestoreService.deleteWord(word);
      if (!mounted) return;
      setState(() {
        _words.removeWhere(
          (item) =>
              (item['word'] ?? '').toString().toLowerCase() ==
              word.toLowerCase(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$word" removed from saved words.')),
      );
    } catch (e) {
      debugPrint('Delete saved word error: $e');
    }
  }

  Future<void> _confirmDelete(String word) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          'Remove word?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Remove "$word" from your saved vocabulary?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteWord(word);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final visibleWords = _filteredWords;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(dark)),
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary(dark),
                        size: 18,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Saved words',
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() => _loading = true);
                      _loadWords();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(dark)),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        color: AppColors.cyan,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                onChanged: (value) => setState(() => _search = value),
                style: TextStyle(color: AppColors.textPrimary(dark)),
                decoration: InputDecoration(
                  hintText: 'Search saved words',
                  hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondary(dark),
                  ),
                  filled: true,
                  fillColor: AppColors.card(dark),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.cyan),
                    )
                  : visibleWords.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bookmark_border_rounded,
                                  size: 64,
                                  color: AppColors.textTertiary(dark),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _search.trim().isEmpty
                                      ? 'No saved words yet.\nScan an object and save its word!'
                                      : 'No matching words.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.textSecondary(dark),
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                          itemCount: visibleWords.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final word = visibleWords[index];
                            return _SavedWordCard(
                              word: word,
                              dark: dark,
                              onTap: () => _openWord(word),
                              onDelete: () => _confirmDelete(
                                (word['word'] ?? '').toString(),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedWordCard extends StatelessWidget {
  final Map<String, dynamic> word;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SavedWordCard({
    required this.word,
    required this.dark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (word['word'] ?? '').toString();
    final phonetic = (word['phonetic'] ?? '').toString();
    final definition = (word['definition'] ?? '').toString();
    final imagePath = (word['image_path'] ?? '').toString();
    final imageUrl = (word['image_url'] ?? '').toString();
    final imageBase64 = (word['image_base64'] ?? '').toString();

    Widget leading;
    Uint8List? decodedImage;

    if (imageBase64.isNotEmpty) {
      try {
        decodedImage = base64Decode(imageBase64);
      } catch (_) {
        decodedImage = null;
      }
    }

    if (decodedImage != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          decodedImage,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      );
    } else if (imageUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
              return Image.file(
                File(imagePath),
                width: 52,
                height: 52,
                fit: BoxFit.cover,
              );
            }
            return Container(
              width: 52,
              height: 52,
              color: AppColors.cyan.withValues(alpha: 0.12),
              child: const Icon(
                Icons.bookmark_rounded,
                color: AppColors.cyan,
                size: 24,
              ),
            );
          },
        ),
      );
    } else if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(imagePath),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
        ),
      );
    } else {
      leading = Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.bookmark_rounded,
          color: AppColors.cyan,
          size: 24,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border(dark)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow(dark),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (phonetic.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      phonetic,
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (definition.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      definition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary(dark),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.textSecondary(dark),
                  size: 20,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary(dark),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
