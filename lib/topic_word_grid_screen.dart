import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'topics_data.dart';
import 'topic_complete_screen.dart';

class TopicWordGridScreen extends StatefulWidget {
  final TopicDef topic;
  const TopicWordGridScreen({super.key, required this.topic});

  @override
  State<TopicWordGridScreen> createState() => _TopicWordGridScreenState();
}

class _TopicWordGridScreenState extends State<TopicWordGridScreen> {
  Set<String> _learned = {};
  bool _loading = true;
  bool _changed = false; // tells TopicsScreen to refresh on pop

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final progress = await FirestoreService.getTopicProgress();
      final learned = (progress[widget.topic.id] as List?)?.cast<String>() ?? [];
      if (!mounted) return;
      setState(() {
        _learned = learned.toSet();
        _loading = false;
      });
    } catch (e) {
      debugPrint('TopicWordGridScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tapWord(TopicWord word) async {
    if (_learned.contains(word.word)) return; // already learned
    // Only the next-in-line word is tappable, to keep a linear learning order.
    final nextIndex = _learned.length;
    final wordIndex = widget.topic.words.indexOf(word);
    if (wordIndex != nextIndex) return;

    final learnedNow = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WordCardSheet(word: word, topicColor: widget.topic.color),
    );
    if (learnedNow != true) return;

    try {
      await FirestoreService.markWordLearned(widget.topic.id, word.word);
    } catch (e) {
      debugPrint('markWordLearned error: $e');
    }
    _changed = true;
    setState(() => _learned.add(word.word));

    if (_learned.length >= widget.topic.words.length) {
      await _completeTopic();
    }
  }

  Future<void> _completeTopic() async {
    const tokens = 10;
    const xp = 100;
    try {
      await FirestoreService.addRewards(tokens: tokens, xp: xp);
    } catch (e) {
      debugPrint('addRewards error: $e');
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
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final total = widget.topic.words.length;
    final done = _learned.length;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.arrow_back_rounded,
                                color: AppColors.textPrimary(dark)),
                            onPressed: () => Navigator.pop(context, _changed),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.topic.name,
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary(dark))),
                                Text('$total words · $done done',
                                    style: TextStyle(
                                        color: AppColors.textSecondary(dark), fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : done / total,
                          backgroundColor: AppColors.secondary(dark),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: total,
                        itemBuilder: (context, i) {
                          final word = widget.topic.words[i];
                          final isLearned = _learned.contains(word.word);
                          final isNext = i == _learned.length;
                          final locked = !isLearned && !isNext;
                          return GestureDetector(
                            onTap: locked ? null : () => _tapWord(word),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.card(dark),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isLearned
                                      ? Colors.green
                                      : isNext
                                          ? widget.topic.color
                                          : AppColors.border(dark),
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Center(
                                child: locked
                                    ? Icon(Icons.lock_rounded,
                                        color: AppColors.textTertiary(dark), size: 20)
                                    : Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(word.word,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                  color: isLearned
                                                      ? Colors.green
                                                      : AppColors.textPrimary(dark))),
                                          const SizedBox(height: 3),
                                          Text(word.translation,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textSecondary(dark))),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, _changed),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.cyan),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Back to Topics',
                              style: TextStyle(
                                  color: AppColors.cyan,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// Simple learn-card shown when tapping the next unlearned word.
class _WordCardSheet extends StatelessWidget {
  final TopicWord word;
  final Color topicColor;
  const _WordCardSheet({required this.word, required this.topicColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C22),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Text(word.word,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 6),
          Text(word.translation, style: TextStyle(fontSize: 16, color: topicColor)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: topicColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}