import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'database_service.dart';
import 'quiz_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  _ReviewScreenState createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  List<Map<String, dynamic>> _savedWords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final words = await DatabaseService.getSavedWords();
    if (mounted)
      setState(() {
        _savedWords = words;
        _loading = false;
      });
  }

  List<Map<String, dynamic>> get _needsReview {
    if (_savedWords.isEmpty) return [];
    final count =
        (_savedWords.length * 0.2).ceil().clamp(1, _savedWords.length);
    return _savedWords.take(count).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.cyan))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Review',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(dark),
                              letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(
                          '${_savedWords.length} words saved · ${_needsReview.length} need review',
                          style: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 13)),
                      const SizedBox(height: 20),
                      _WeeklyProgressCard(
                          total: _savedWords.length, dark: dark),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: _ActionCard(
                          icon: Icons.quiz_rounded,
                          label: 'Start Quiz',
                          subtitle: '5 questions',
                          color: AppColors.cyan,
                          dark: dark,
                          onTap: _savedWords.isEmpty
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const QuizScreen())),
                        )),
                        const SizedBox(width: 14),
                        Expanded(
                            child: _ActionCard(
                          icon: Icons.style_rounded,
                          label: 'Flashcards',
                          subtitle: '${_savedWords.length} cards',
                          color: AppColors.flame,
                          dark: dark,
                          onTap: _savedWords.isEmpty
                              ? null
                              : () => _showFlashcards(),
                        )),
                      ]),
                      if (_needsReview.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Text('Needs Review',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary(dark))),
                        const SizedBox(height: 12),
                        ..._needsReview.map((w) => _ReviewWordTile(
                            word: w['word'] ?? '',
                            definition: w['definition'] ?? '',
                            phonetic: w['phonetic'] ?? '',
                            dark: dark)),
                      ],
                      if (_savedWords.isEmpty)
                        Center(
                            child: Padding(
                          padding: const EdgeInsets.only(top: 60),
                          child: Column(children: [
                            Icon(Icons.auto_stories_rounded,
                                size: 64, color: AppColors.textTertiary(dark)),
                            const SizedBox(height: 16),
                            Text(
                                'Nothing to review yet.\nScan objects to build your vocab!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.textSecondary(dark),
                                    fontSize: 15)),
                          ]),
                        )),
                    ]),
              ),
      ),
    );
  }

  void _showFlashcards() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FlashcardSheet(
          words: _savedWords, dark: ThemeProvider.isDark(context)));
}

class _WeeklyProgressCard extends StatelessWidget {
  final int total;
  final bool dark;
  const _WeeklyProgressCard({required this.total, required this.dark});

  @override
  Widget build(BuildContext context) {
    const goal = 20;
    final progress = (total / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border(dark)),
        boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 8)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.flag_rounded, color: AppColors.cyan, size: 16),
          const SizedBox(width: 6),
          Text('Weekly Goal',
              style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          const Spacer(),
          Text('$total / $goal words',
              style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.secondary(dark),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
              minHeight: 8),
        ),
        const SizedBox(height: 8),
        Text(
            progress >= 1.0
                ? '🎉 Goal reached this week!'
                : '${((1 - progress) * goal).ceil()} more words to reach your goal',
            style:
                TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
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
  const _ActionCard(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.color,
      required this.dark,
      this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: color.withOpacity(dark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: color.withOpacity(0.3), width: 1.5)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: AppColors.textSecondary(dark), fontSize: 12)),
            ]),
          ),
        ),
      );
}

class _ReviewWordTile extends StatelessWidget {
  final String word, definition, phonetic;
  final bool dark;
  const _ReviewWordTile(
      {required this.word,
      required this.definition,
      required this.phonetic,
      required this.dark});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 4)],
        ),
        child: Row(children: [
          Container(
              width: 6,
              height: 36,
              decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(word,
                    style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                if (phonetic.isNotEmpty)
                  Text(phonetic,
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                if (definition.isNotEmpty)
                  Text(definition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textSecondary(dark), fontSize: 12)),
              ])),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.redAccent, size: 20),
        ]),
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
      setState(() {
        _index++;
        _flipped = false;
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_index > 0)
      setState(() {
        _index--;
        _flipped = false;
      });
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
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border(dark),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Text('${_index + 1} / $total',
              style: TextStyle(
                  color: AppColors.textSecondary(dark), fontSize: 13)),
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
                        color: _flipped
                            ? AppColors.cyan.withOpacity(0.4)
                            : AppColors.border(dark)),
                    boxShadow: [
                      BoxShadow(color: AppColors.shadow(dark), blurRadius: 12)
                    ],
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_flipped) ...[
                          Text(word['word'] ?? '',
                              style: TextStyle(
                                  fontSize: 42,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary(dark),
                                  letterSpacing: -1),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          if ((word['phonetic'] ?? '').isNotEmpty)
                            Text(word['phonetic'],
                                style: const TextStyle(
                                    color: AppColors.cyan,
                                    fontSize: 16,
                                    fontStyle: FontStyle.italic)),
                          const SizedBox(height: 24),
                          Text('Tap to reveal',
                              style: TextStyle(
                                  color: AppColors.textTertiary(dark),
                                  fontSize: 13)),
                        ] else ...[
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              child: Text(word['definition'] ?? '',
                                  style: TextStyle(
                                      color: AppColors.textPrimary(dark),
                                      fontSize: 18,
                                      height: 1.5),
                                  textAlign: TextAlign.center)),
                          if ((word['example'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 28),
                                child: Text('"${word['example']}"',
                                    style: TextStyle(
                                        color: AppColors.textSecondary(dark),
                                        fontSize: 14,
                                        fontStyle: FontStyle.italic,
                                        height: 1.5),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.card(dark),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border(dark))),
                  child: Text('← Back',
                      style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            GestureDetector(
              onTap: _next,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(24)),
                child: Text(_index < total - 1 ? 'Next →' : 'Done ✓',
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
