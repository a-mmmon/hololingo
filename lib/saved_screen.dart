import 'package:flutter/material.dart';
import 'database_service.dart';
import 'app_theme.dart';

class SavedScreen extends StatefulWidget {
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
    setState(() {
      _savedWords = words;
      _loading = false;
    });
  }

  Future<void> _deleteWord(int id) async {
    await DatabaseService.deleteWord(id);
    _loadWords();
  }

  int _fakeStreak(int index) {
    final streaks = [3, 5, 0, 1, 7, 2];
    return streaks[index % streaks.length];
  }

  @override
  Widget build(BuildContext context) {
    final wordCount = _savedWords.length;
    const weeklyGoal = 48;
    const reviewed = 35;
    const progress = reviewed / weeklyGoal;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('My Vocab',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5)),
                  Spacer(),
                  Text('$wordCount words',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.cyan)),
                ],
              ),
            ),

            // Weekly progress
            Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: AppColors.card,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.cyan),
                      minHeight: 6,
                    ),
                  ),
                  SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Weekly goal: $reviewed / $weeklyGoal',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12)),
                      Spacer(),
                      Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Word list
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.cyan))
                  : _savedWords.isEmpty
                      ? _emptyState()
                      : ListView(
                          padding:
                              EdgeInsets.fromLTRB(20, 0, 20, 12),
                          children: [
                            _SectionHeader('Recent scans'),
                            SizedBox(height: 10),
                            ..._recentWords()
                                .asMap()
                                .entries
                                .map((e) {
                              final i = e.key;
                              final word = e.value;
                              final streak = _fakeStreak(i);
                              return _WordCard(
                                word: word['word'] ?? '',
                                translation: word['phonetic'] ?? '',
                                streak: streak,
                                isNew: streak == 0,
                                onDelete: () =>
                                    _deleteWord(word['id']),
                              );
                            }).toList(),
                            if (_needsReview().isNotEmpty) ...[
                              SizedBox(height: 20),
                              _SectionHeader('Needs review'),
                              SizedBox(height: 10),
                              ..._needsReview().map((word) =>
                                  _WordCard(
                                    word: word['word'] ?? '',
                                    translation:
                                        word['phonetic'] ?? '',
                                    streak: 0,
                                    needsReview: true,
                                    onDelete: () =>
                                        _deleteWord(word['id']),
                                  )),
                            ],
                          ],
                        ),
            ),

           
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _recentWords() {
    if (_savedWords.length <= 1) return _savedWords;
    return _savedWords.take(_savedWords.length - 1).toList();
  }

  List<Map<String, dynamic>> _needsReview() {
    if (_savedWords.isEmpty) return [];
    return [_savedWords.last];
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_border_rounded,
              size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No saved words yet!\nScan objects to start learning.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white12, thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(title,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
        ),
        Expanded(child: Divider(color: Colors.white12, thickness: 1)),
      ],
    );
  }
}

// ── Word Card ─────────────────────────────────────────────────────────────────
class _WordCard extends StatelessWidget {
  final String word;
  final String translation;
  final int streak;
  final bool isNew;
  final bool needsReview;
  final VoidCallback onDelete;

  const _WordCard({
    required this.word,
    required this.translation,
    required this.streak,
    this.isNew = false,
    this.needsReview = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          builder: (_) => Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(word,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                SizedBox(height: 16),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: Text('Delete word',
                      style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: needsReview
              ? AppColors.card.withOpacity(0.6)
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: needsReview
              ? Border.all(
                  color: Colors.redAccent.withOpacity(0.4), width: 1)
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(word,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  SizedBox(height: 4),
                  Text(
                      translation.isNotEmpty ? translation : '—',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (needsReview)
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.redAccent, width: 1),
                ),
                child: Text('Review now',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              )
            else if (isNew)
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('New',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              )
            else
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.flame.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🔥', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 4),
                    Text('$streak',
                        style: TextStyle(
                            color: AppColors.flame,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}