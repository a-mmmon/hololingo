import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'dictionary_service.dart';
import 'vocab_detail_screen.dart';
import 'quiz_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  _ReviewScreenState createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // Live stream, not a one-time fetch: the bottom nav's IndexedStack keeps
  // this screen's State alive forever after the first build, so a Future
  // fetched once in initState would never notice a word saved afterward.
  Stream<List<Map<String, dynamic>>>? _savedWordsStream;

  String _reviewFrequency = 'weekly';

  @override
  void initState() {
    super.initState();
    _savedWordsStream = DatabaseService.watchSavedWords(limit: null);
    _loadProfile();
    _repairBrokenDefinitionsOnce();
    FirestoreService.migrateLegacyReviewStatus();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await FirestoreService.getProfileOrDefault();
      if (!mounted) return;

      final frequency =
          profile['review_reminder_frequency']?.toString().toLowerCase();

      setState(() {
        _reviewFrequency = frequency == 'monthly' ? 'monthly' : 'weekly';
      });
    } catch (e) {
      debugPrint('ReviewScreen profile error: $e');
    }
  }

  // One-time maintenance pass, not tied to the live stream above — this
  // writes back to Firestore, so running it on every stream tick would
  // redundantly re-check every saved word each time any one of them
  // changes. A single pass per screen visit is enough to backfill entries
  // saved before a definition was available.
  Future<void> _repairBrokenDefinitionsOnce() async {
    try {
      final words = await DatabaseService.getSavedWords();

      for (final word in words) {
        final wordName = (word['word'] ?? '').toString();
        if (wordName.isEmpty) continue;

        final oldDefinition = (word['definition'] ?? '').toString();

        final needsDefinition = oldDefinition.trim().isEmpty ||
            oldDefinition.toLowerCase().contains('could not load definition') ||
            oldDefinition.toLowerCase().contains(
              'vocabulary information has not been added',
            );

        // dictionary_service.dart's curated _fallbackVocabulary is the
        // source of truth for common object words. If a word was saved
        // before a curated entry existed for it (or before one got
        // corrected — e.g. "monitor" briefly resolving to the wrong
        // dictionary sense), it stays stuck with the old text forever
        // unless resynced here.
        final curated = DictionaryService.getLocalWordInfo(wordName);
        final outOfSyncWithCurated =
            curated != null && curated['definition'] != oldDefinition;

        if (!needsDefinition && !outOfSyncWithCurated) continue;

        try {
          final info = curated ?? await DictionaryService.getWordInfo(wordName);

          await DatabaseService.updateSavedWord(wordName, {
            'phonetic': info['phonetic'] ?? word['phonetic'] ?? '',
            'definition': info['definition'] ?? word['definition'] ?? '',
            'example': info['example'] ?? word['example'] ?? '',
          });
        } catch (e) {
          debugPrint('Could not repair $wordName: $e');
        }
      }
    } catch (e) {
      debugPrint('ReviewScreen repair error: $e');
    }
  }

  // A word enters Needs Review once it's been missed twice, and *stays*
  // flagged (review_status == 'needs_review') through its whole recovery
  // climb back to 0 wrong, not just while wrong_count is literally >= 2 —
  // see FirestoreService.recordQuizResult for the full lifecycle (needs
  // review -> learned -> periodic recheck). Qualifying words are still
  // sorted by how wrong-heavy they are, so the worst ones show first.
  List<Map<String, dynamic>> _needsReview(List<Map<String, dynamic>> savedWords) {
    final flagged = savedWords
        .where((w) => (w['review_status'] ?? '') == 'needs_review')
        .toList()
      ..sort((a, b) {
        final scoreA = (a['wrong_count'] ?? 0) - (a['correct_count'] ?? 0);
        final scoreB = (b['wrong_count'] ?? 0) - (b['correct_count'] ?? 0);
        return (scoreB as num).compareTo(scoreA as num);
      });

    return flagged;
  }

  // Needs Review words come first (shuffled among themselves), then
  // everything else (also shuffled), so practice naturally front-loads the
  // words the user actually struggles with instead of flipping through the
  // full saved list in a fixed, unchanging order every time.
  List<Map<String, dynamic>> _buildFlashcardDeck(
    List<Map<String, dynamic>> savedWords,
    List<Map<String, dynamic>> needsReview,
  ) {
    final needsReviewKeys = needsReview.map((w) => w['word']).toSet();
    final rest = savedWords
        .where((w) => !needsReviewKeys.contains(w['word']))
        .toList()
      ..shuffle();
    final priority = [...needsReview]..shuffle();
    return [...priority, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _savedWordsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.cyan),
              );
            }

            final savedWords = snapshot.data ?? [];
            final needsReview = _needsReview(savedWords);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Review', style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary(dark), letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('${savedWords.length} words saved · ${needsReview.length} need review',
                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13)),
                const SizedBox(height: 20),
                _ReviewProgressCard(
                  total: savedWords.length,
                  frequency: _reviewFrequency,
                  dark: dark,
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _ActionCard(
                    icon: Icons.quiz_rounded, label: 'Start Quiz',
                    subtitle: '5 questions', color: AppColors.cyan,
                    dark: dark,
                    onTap: savedWords.isEmpty ? null : () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const QuizScreen())),
                  )),
                  const SizedBox(width: 14),
                  Expanded(child: _ActionCard(
                    icon: Icons.style_rounded, label: 'Flashcards',
                    subtitle: '${savedWords.length} cards', color: AppColors.flame,
                    dark: dark,
                    onTap: savedWords.isEmpty
                        ? null
                        : () => _showFlashcards(
                              _buildFlashcardDeck(savedWords, needsReview),
                            ),
                  )),
                ]),
                if (needsReview.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('Needs Review', style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(dark))),
                  const SizedBox(height: 12),
                  ...needsReview.map((w) => _ReviewWordTile(
                    word: w['word'] ?? '', definition: w['definition'] ?? '',
                    phonetic: w['phonetic'] ?? '', dark: dark,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VocabDetailScreen(
                          word: (w['word'] ?? '').toString(),
                          phonetic: (w['phonetic'] ?? '').toString(),
                          definition: (w['definition'] ?? '').toString(),
                          example: (w['example'] ?? '').toString(),
                          imagePath: (w['image_path'] ?? '').toString().isEmpty
                              ? null
                              : (w['image_path'] ?? '').toString(),
                          initiallySaved: true,
                        ),
                      ),
                    ))),
                ],
                if (savedWords.isEmpty)
                  Center(child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Column(children: [
                      Icon(Icons.auto_stories_rounded, size: 64,
                        color: AppColors.textTertiary(dark)),
                      const SizedBox(height: 16),
                      Text('Nothing to review yet.\nScan objects to build your vocab!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 15)),
                    ]),
                  )),
              ]),
            );
          },
        ),
      ),
    );
  }

  void _showFlashcards(List<Map<String, dynamic>> savedWords) => showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _FlashcardSheet(words: savedWords,
      dark: ThemeProvider.isDark(context)));
}

class _ReviewProgressCard extends StatelessWidget {
  final int total;
  final String frequency;
  final bool dark;

  const _ReviewProgressCard({
    required this.total,
    required this.frequency,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final goal = frequency == 'monthly' ? 50 : 20;
    final progress = (total / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card(dark), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(dark)),
        boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(
            frequency == 'monthly' ? 'Monthly Goal' : 'Weekly Goal',
            style: TextStyle(
            color: AppColors.textPrimary(dark), fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const Spacer(),
          Text('$total / $goal words', style: const TextStyle(
            color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress, backgroundColor: AppColors.secondary(dark),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
            minHeight: 8),
        ),
        const SizedBox(height: 8),
        Text(progress >= 1.0
          ? (frequency == 'monthly'
              ? '🎉 Goal reached this month!'
              : '🎉 Goal reached this week!')
          : '${((1 - progress) * goal).ceil()} more words to reach your goal',
          style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
      ]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final bool dark;
  final VoidCallback? onTap;
  const _ActionCard({required this.icon, required this.label,
    required this.subtitle, required this.color, required this.dark, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
        ]),
      ),
    ),
  );
}

class _ReviewWordTile extends StatelessWidget {
  final String word, definition, phonetic;
  final bool dark;
  final VoidCallback? onTap;
  const _ReviewWordTile({
    required this.word,
    required this.definition,
    required this.phonetic,
    required this.dark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.card(dark), borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 4)],
    ),
    child: Row(children: [
      Container(width: 6, height: 36,
        decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(word, style: TextStyle(color: AppColors.textPrimary(dark),
          fontSize: 16, fontWeight: FontWeight.w700)),
        if (phonetic.isNotEmpty)
          Text(phonetic, style: const TextStyle(
            color: AppColors.cyan, fontSize: 12, fontStyle: FontStyle.italic)),
        if (definition.isNotEmpty)
          Text(definition, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
      ])),
      const Icon(Icons.chevron_right_rounded, color: Colors.redAccent, size: 20),
    ]),
  ),
);
}

class _FlashcardSheet extends StatefulWidget {
  final List<Map<String, dynamic>> words;
  final bool dark;
  const _FlashcardSheet({required this.words, required this.dark});
  @override
  _FlashcardSheetState createState() => _FlashcardSheetState();
}

class _FlashcardSheetState extends State<_FlashcardSheet> {
  int _index = 0;
  bool _flipped = false;

  void _next() {
    if (_index < widget.words.length - 1) {
      setState(() { _index++; _flipped = false; });
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_index > 0) setState(() { _index--; _flipped = false; });
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final word = widget.words[_index];
    final total = widget.words.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppColors.bg(dark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(children: [
          Container(width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.border(dark),
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('${_index + 1} / $total',
            style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13)),
          const SizedBox(height: 20),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _flipped = !_flipped),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(_flipped),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.card(dark),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _flipped ? AppColors.cyan.withValues(alpha: 0.4) : AppColors.border(dark)),
                    boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 12)],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (!_flipped) ...[
                      Text(word['word'] ?? '', style: TextStyle(
                        fontSize: 42, fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary(dark), letterSpacing: -1),
                        textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      if ((word['phonetic'] ?? '').isNotEmpty)
                        Text(word['phonetic'], style: const TextStyle(
                          color: AppColors.cyan, fontSize: 16, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 24),
                      Text('Tap to reveal',
                        style: TextStyle(color: AppColors.textTertiary(dark), fontSize: 13)),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(word['definition'] ?? '', style: TextStyle(
                          color: AppColors.textPrimary(dark), fontSize: 18, height: 1.5),
                          textAlign: TextAlign.center)),
                      if ((word['example'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Text('"${word['example']}"', style: TextStyle(
                            color: AppColors.textSecondary(dark), fontSize: 14,
                            fontStyle: FontStyle.italic, height: 1.5),
                            textAlign: TextAlign.center)),
                      ],
                    ],
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              onTap: _index > 0 ? _prev : null,
              child: Opacity(
                opacity: _index > 0 ? 1.0 : 0.3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card(dark), borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border(dark))),
                  child: Text('← Back', style: TextStyle(
                    color: AppColors.textPrimary(dark), fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            GestureDetector(
              onTap: _next,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cyan, borderRadius: BorderRadius.circular(24)),
                child: Text(_index < total - 1 ? 'Next →' : 'Done ✓',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}