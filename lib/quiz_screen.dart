import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'thai_translations.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _QuizDirection { engToThai, thaiToEng }

class _QuizQuestion {
  final _QuizDirection direction;
  final String prompt;
  final String correctAnswer;
  final List<String> options;

  /// Non-null only when this question came from a word the user actually
  /// saved (as opposed to a dictionary word used to pad out a short quiz) —
  /// that's the key recordQuizResult() needs to update the right saved
  /// word's correct/wrong count.
  final String? savedWordKey;

  const _QuizQuestion({
    required this.direction,
    required this.prompt,
    required this.correctAnswer,
    required this.options,
    this.savedWordKey,
  });
}

class _QuizScreenState extends State<QuizScreen> {
  final Random _random = Random();
  List<_QuizQuestion> _questions = [];
  int _index = 0;
  int _score = 0;
  String? _selected;
  bool _loading = true;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _loadQuiz() async {
    try {
      final words = await FirestoreService.getSavedWords();
      final saved = words
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => (e['word'] ?? '').toString().trim().isNotEmpty)
          .toList();

      // A 'learned' word is dormant until its scheduled recheck date, so it
      // doesn't get quizzed prematurely — see
      // FirestoreService.recordQuizResult for the full lifecycle. Fresh
      // ('none') and 'needs_review' words are always eligible.
      final now = DateTime.now();
      final eligible = saved.where((e) {
        final status = (e['review_status'] as String?) ?? 'none';
        if (status != 'learned') return true;
        final nextCheck = (e['next_check_at'] as Timestamp?)?.toDate();
        return nextCheck != null && !nextCheck.isAfter(now);
      }).toList();

      // Saved words that have a known Thai translation. Questions are only
      // ever built from these, never from words the user hasn't saved, so
      // the quiz always reflects the user's own vocabulary rather than
      // random dictionary entries.
      final translatableKeys = eligible
          .map((e) => e['word'].toString().trim().toLowerCase())
          .where((key) => kThaiTranslations.containsKey(key))
          .toSet();

      final pool = translatableKeys.toList()..shuffle(_random);
      final count = min(5, pool.length);
      final questions = <_QuizQuestion>[];

      for (int i = 0; i < count; i++) {
        final key = pool[i];
        final thai = kThaiTranslations[key]!;
        final englishWord = _capitalize(key);

        final direction = _random.nextBool()
            ? _QuizDirection.engToThai
            : _QuizDirection.thaiToEng;

        // Prefer distractors from the user's other saved words first, and
        // only borrow from the wider dictionary if there aren't enough
        // saved words to fill out the answer choices.
        final otherSavedKeys =
            translatableKeys.where((k) => k != key).toList()..shuffle(_random);
        final otherDictionaryKeys =
            kThaiTranslations.keys
                .where((k) => k != key && !translatableKeys.contains(k))
                .toList()
              ..shuffle(_random);
        // Skip synonyms that share this word's Thai (e.g. couch/sofa), and
        // keep each Thai choice unique, so no question shows two identical
        // answers.
        final seenThai = {thai};
        final otherKeys = [...otherSavedKeys, ...otherDictionaryKeys]
            .where((k) => seenThai.add(kThaiTranslations[k]!))
            .toList();

        late final String prompt;
        late final String correctAnswer;
        late final List<String> options;

        if (direction == _QuizDirection.engToThai) {
          prompt = englishWord;
          correctAnswer = thai;
          options = [
            thai,
            ...otherKeys.take(3).map((k) => kThaiTranslations[k]!),
          ];
        } else {
          prompt = thai;
          correctAnswer = englishWord;
          options = [
            englishWord,
            ...otherKeys.take(3).map((k) => _capitalize(k)),
          ];
        }

        options.shuffle(_random);

        questions.add(_QuizQuestion(
          direction: direction,
          prompt: prompt,
          correctAnswer: correctAnswer,
          options: options,
          savedWordKey: key,
        ));
      }

      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Quiz load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _answer(String option) {
    if (_selected != null || _finished || _questions.isEmpty) return;

    final question = _questions[_index];
    final isCorrect = option == question.correctAnswer;

    setState(() {
      _selected = option;
      if (isCorrect) _score++;
    });

    final wordKey = question.savedWordKey;
    if (wordKey != null) {
      FirestoreService.recordQuizResult(wordKey, isCorrect);
    }
  }

  void _next() {
    if (_selected == null) return;

    if (_index + 1 >= _questions.length) {
      setState(() => _finished = true);
      return;
    }

    setState(() {
      _index++;
      _selected = null;
    });
  }

  void _restart() {
    setState(() {
      _loading = true;
      _finished = false;
      _index = 0;
      _score = 0;
      _selected = null;
    });
    _loadQuiz();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.cyan),
        ),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.quiz_rounded, color: AppColors.cyan, size: 60),
                  const SizedBox(height: 18),
                  Text(
                    'No quiz words yet',
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan and save some objects first.',
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_finished) return _buildResult(dark);

    final question = _questions[_index];
    final instruction = question.direction == _QuizDirection.engToThai
        ? 'Choose the correct Thai translation'
        : 'Choose the correct English word';

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary(dark),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1} / ${_questions.length}',
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: (_index + 1) / _questions.length,
                  backgroundColor: AppColors.border(dark),
                  valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.cyan, width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            question.prompt,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            instruction,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...question.options.map(
                      (option) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AnswerButton(
                          text: option,
                          dark: dark,
                          selected: _selected == option,
                          correct: option == question.correctAnswer,
                          answered: _selected != null,
                          onTap: () => _answer(option),
                        ),
                      ),
                    ),
                    if (_selected != null) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _next,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _index + 1 == _questions.length ? 'Finish' : 'Next',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(bool dark) {
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.emoji_events_rounded, color: AppColors.cyan, size: 80),
                const SizedBox(height: 18),
                Text(
                  'Quiz complete!',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_score / ${_questions.length} correct',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _restart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    child: const Text('Quiz again'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  final String text;
  final bool dark;
  final bool selected;
  final bool correct;
  final bool answered;
  final VoidCallback onTap;

  const _AnswerButton({
    required this.text,
    required this.dark,
    required this.selected,
    required this.correct,
    required this.answered,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = AppColors.border(dark);
    Color background = AppColors.card(dark);

    if (answered && correct) {
      border = Colors.greenAccent;
      background = Colors.green.withValues(alpha: 0.16);
    } else if (selected) {
      border = Colors.redAccent;
      background = Colors.red.withValues(alpha: 0.14);
    }

    return GestureDetector(
      onTap: answered ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (answered && correct)
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
            if (selected && !correct)
              const Icon(Icons.cancel_rounded, color: Colors.redAccent),
          ],
        ),
      ),
    );
  }
}