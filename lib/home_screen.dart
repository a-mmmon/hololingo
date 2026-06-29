import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentWords = [];
  bool _loading = true;

  String _name = '';
  int _wordsToday = 0;
  int _wordGoal = 10;
  int _totalXp = 0;
  int _xpThisWeek = 120;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadProfile();
  }

  Future<void> _loadRecent() async {
    try {
      final words = await DatabaseService.getSavedWords();
      if (mounted) {
        setState(() {
          _recentWords = words.take(5).toList();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen recent words load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await DatabaseService.getProfileOrDefault();
      if (!mounted) return;
      setState(() {
        _name = data['name'] ?? 'User';
        _totalXp = data['total_xp'] ?? 0;
        _wordGoal = data['words_goal'] ?? 10;
        _wordsToday = data['words_today'] ?? 0;
      });
    } catch (e) {
      debugPrint('HomeScreen profile load error: $e');
    }
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _fakeTranslation(String word) {
    const map = {
      'book': 'หนังสือ', 'desk': 'โต๊ะ', 'cup': 'ถ้วย',
      'chair': 'เก้าอี้', 'phone': 'โทรศัพท์', 'pen': 'ปากกา',
    };
    return map[word.toLowerCase()] ?? '';
  }

  String _fakeTime(int index) {
    const times = ['2 min ago', '10 min ago', 'Yesterday', '2 days ago', '3 days ago'];
    return times[index % times.length];
  }

  String _fakeStatus(int index) {
    const statuses = ['Saved', 'Saved', 'Review', 'Saved', 'Saved'];
    return statuses[index % statuses.length];
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // ── Header ───────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting,
                          style: TextStyle(
                              color: AppColors.textSecondary(dark), fontSize: 14)),
                      Text(_name.isNotEmpty ? _name : 'User',
                          style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => TabSwitcher.of(context)?.switchTab(4),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.cyan, width: 2),
                        color: AppColors.card(dark),
                      ),
                      child: Center(
                        child: Text(
                          _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.cyan),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // ── Stats cards ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Words today',
                              style: TextStyle(
                                  color: AppColors.textSecondary(dark),
                                  fontSize: 12)),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text('$_wordsToday',
                                  style: TextStyle(
                                      color: AppColors.textPrimary(dark),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800)),
                              Text(' /$_wordGoal',
                                  style: TextStyle(
                                      color: AppColors.textSecondary(dark),
                                      fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: _wordGoal == 0
                                  ? 0
                                  : (_wordsToday / _wordGoal).clamp(0.0, 1.0),
                              backgroundColor: AppColors.bg(dark),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.cyan),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total XP',
                              style: TextStyle(
                                  color: AppColors.textSecondary(dark),
                                  fontSize: 12)),
                          const SizedBox(height: 6),
                          Text('$_totalXp',
                              style: const TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('+$_xpThisWeek this week',
                              style: TextStyle(
                                  color: AppColors.textSecondary(dark),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── AR Scan button ───────────────────────────────────────────
              GestureDetector(
                onTap: () => TabSwitcher.of(context)?.switchTab(1),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Start AR scan',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text('Point camera at any object',
                                style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black38, width: 2),
                        ),
                        child: Center(
                          child: Container(
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.black38, width: 2.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Daily challenge ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF16103A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF9C6FFF).withValues(alpha: 0.3),
                      width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Daily challenge',
                              style: TextStyle(
                                  color: Color(0xFF9C6FFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          SizedBox(height: 4),
                          Text('Quiz: 5 words from this week',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => TabSwitcher.of(context)?.switchTab(2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF9C6FFF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Go',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ── Recently scanned ─────────────────────────────────────────
              Row(
                children: [
                  Text('RECENTLY SCANNED',
                      style: TextStyle(
                          color: AppColors.textSecondary(dark),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => TabSwitcher.of(context)?.switchTab(3),
                    child: const Text('See all',
                        style: TextStyle(
                            color: AppColors.cyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              if (_loading)
                const Center(
                    child: CircularProgressIndicator(color: AppColors.cyan))
              else if (_recentWords.isEmpty)
                _EmptyRecent(dark: dark)
              else
                ..._recentWords.asMap().entries.map((e) {
                  final i = e.key;
                  final word = e.value;
                  final name = word['word'] ?? '';
                  final translation =
                      word['phonetic'] != null &&
                              (word['phonetic'] as String).isNotEmpty
                          ? word['phonetic']
                          : _fakeTranslation(name);
                  return _RecentWordTile(
                    word: name,
                    translation: translation,
                    time: _fakeTime(i),
                    status: _fakeStatus(i),
                    dark: dark,
                  );
                }),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Recent Word Tile ───────────────────────────────────────────────────────────
class _RecentWordTile extends StatelessWidget {
  final String word, translation, time, status;
  final bool dark;

  const _RecentWordTile({
    required this.word,
    required this.translation,
    required this.time,
    required this.status,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final isReview = status == 'Review';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word,
                    style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  '${translation.isNotEmpty ? '$translation · ' : ''}$time',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark), fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isReview
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isReview
                    ? Colors.redAccent.withValues(alpha: 0.5)
                    : AppColors.cyan.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Text(status,
                style: TextStyle(
                    color: isReview ? Colors.redAccent : AppColors.cyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ────────────────────────────────────────────────────────────────
class _EmptyRecent extends StatelessWidget {
  final bool dark;
  const _EmptyRecent({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text('Scan objects to see them here',
            style:
                TextStyle(color: AppColors.textSecondary(dark), fontSize: 14)),
      ),
    );
  }
}