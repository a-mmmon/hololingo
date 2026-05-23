import 'package:flutter/material.dart';
import 'database_service.dart';
import 'app_theme.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  _SavedScreenState createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  List<Map<String, dynamic>> _savedWords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final words = await DatabaseService.getSavedWords();
    if (mounted) setState(() { _savedWords = words; _loading = false; });
  }

  Future<void> _deleteWord(int id) async {
    await DatabaseService.deleteWord(id);
    _loadWords();
  }

  int _fakeStreak(int index) => [3, 5, 0, 1, 7, 2][index % 6];

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final wordCount = _savedWords.length;
    const weeklyGoal = 48, reviewed = 35;
    const progress = reviewed / weeklyGoal;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('My Vocab', style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary(dark), letterSpacing: -0.5)),
                  const Spacer(),
                  Text('$wordCount words', style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: AppColors.secondary(dark),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Weekly goal: $reviewed / $weeklyGoal',
                    style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
                  const Spacer(),
                  Text('${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.green,
                      fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                : _savedWords.isEmpty
                  ? _emptyState(dark)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      children: [
                        _SectionHeader('Recent scans', dark: dark),
                        const SizedBox(height: 10),
                        ..._recentWords().asMap().entries.map((e) {
                          final streak = _fakeStreak(e.key);
                          return _WordCard(
                            word: e.value['word'] ?? '',
                            translation: e.value['phonetic'] ?? '',
                            streak: streak, isNew: streak == 0, dark: dark,
                            onDelete: () => _deleteWord(e.value['id']));
                        }),
                        if (_needsReview().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _SectionHeader('Needs review', dark: dark),
                          const SizedBox(height: 10),
                          ..._needsReview().map((w) => _WordCard(
                            word: w['word'] ?? '', translation: w['phonetic'] ?? '',
                            streak: 0, needsReview: true, dark: dark,
                            onDelete: () => _deleteWord(w['id']))),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _recentWords() =>
      _savedWords.length <= 1 ? _savedWords : _savedWords.take(_savedWords.length - 1).toList();

  List<Map<String, dynamic>> _needsReview() =>
      _savedWords.isEmpty ? [] : [_savedWords.last];

  Widget _emptyState(bool dark) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.bookmark_border_rounded, size: 64,
        color: AppColors.textTertiary(dark)),
      const SizedBox(height: 16),
      Text('No saved words yet!\nScan objects to start learning.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 15)),
    ]),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool dark;
  const _SectionHeader(this.title, {required this.dark});

  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Divider(color: AppColors.border(dark), thickness: 1)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(title, style: TextStyle(
        color: AppColors.textSecondary(dark), fontSize: 12,
        fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    ),
    Expanded(child: Divider(color: AppColors.border(dark), thickness: 1)),
  ]);
}

class _WordCard extends StatelessWidget {
  final String word, translation;
  final int streak;
  final bool isNew, needsReview, dark;
  final VoidCallback onDelete;

  const _WordCard({
    required this.word, required this.translation, required this.streak,
    this.isNew = false, this.needsReview = false,
    required this.dark, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () => showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card(dark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(word, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(dark))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('Delete word', style: TextStyle(color: Colors.redAccent)),
            onTap: () { Navigator.pop(context); onDelete(); },
          ),
        ]),
      ),
    ),
    child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: needsReview
            ? Colors.redAccent.withOpacity(0.4)
            : AppColors.border(dark)),
        boxShadow: [BoxShadow(color: AppColors.shadow(dark), blurRadius: 4)],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(word, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary(dark))),
          const SizedBox(height: 4),
          Text(translation.isNotEmpty ? translation : '—',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary(dark))),
        ])),
        if (needsReview)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.redAccent)),
            child: const Text('Review now', style: TextStyle(
              color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
          )
        else if (isNew)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondary(dark),
              borderRadius: BorderRadius.circular(20)),
            child: Text('New', style: TextStyle(
              color: AppColors.textSecondary(dark), fontSize: 12, fontWeight: FontWeight.w600)),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.flame.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🔥', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text('$streak', style: TextStyle(
                color: AppColors.flame, fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    ),
  );
}