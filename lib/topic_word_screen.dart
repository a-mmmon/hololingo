import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'topics_complete_screen.dart';

/// Word cards grid for a single topic — matches the "Animals" screen design:
/// header (topic name, word count, progress bar), 3-column grid of word
/// cards, and a bottom "Continue Topic ->" button.
///
/// `words` entries look like: {"en": "Cat", "th": "แมว", "status": "done"}
/// status is one of: "done" | "locked" | "normal".
class TopicWordScreen extends StatefulWidget {
  final String topicName;
  final List<Map<String, String>> words;

  const TopicWordScreen({
    super.key,
    required this.topicName,
    required this.words,
  });

  @override
  State<TopicWordScreen> createState() => _TopicWordScreenState();
}

class _TopicWordScreenState extends State<TopicWordScreen> {
  late List<Map<String, String>> _words;

  @override
  void initState() {
    super.initState();
    _words = widget.words.map((w) => Map<String, String>.from(w)).toList();
  }

  int get _doneCount => _words.where((w) => w['status'] == 'done').length;

  void _tapCard(int index) {
    final status = _words[index]['status'];
    if (status == 'locked') return;
    setState(() {
      _words[index]['status'] = 'done';
      // Unlock the next locked card so learners progress in order.
      final nextLocked = _words.indexWhere((w) => w['status'] == 'locked');
      if (nextLocked != -1) _words[nextLocked]['status'] = 'normal';
    });
  }

  void _continue() {
    if (_doneCount == _words.length) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TopicCompleteScreen(
            topicName: widget.topicName,
            tokensEarned: _words.length,
            xpEarned: _words.length * 10,
          ),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final total = _words.length;
    final progress = total == 0 ? 0.0 : _doneCount / total;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
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
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary(dark), size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.topicName,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(dark),
                                letterSpacing: -0.5)),
                        Text('$_doneCount / $total words',
                            style: TextStyle(
                                color: AppColors.textSecondary(dark),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.secondary(dark),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                itemCount: _words.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemBuilder: (_, i) => _WordCard(
                  word: _words[i],
                  dark: dark,
                  onTap: () => _tapCard(i),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GestureDetector(
                onTap: _continue,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Continue ${widget.topicName}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.black, size: 20),
                    ],
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

class _WordCard extends StatelessWidget {
  final Map<String, String> word;
  final bool dark;
  final VoidCallback onTap;

  const _WordCard(
      {required this.word, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = word['status'] ?? 'normal';
    final isDone = status == 'done';
    final isLocked = status == 'locked';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(16),
          border: isDone
              ? Border.all(color: Colors.green, width: 2)
              : isLocked
                  ? Border.all(color: AppColors.border(dark), width: 1.5)
                  : Border.all(color: AppColors.cyan, width: 1.5),
          boxShadow: isDone
              ? [
                  BoxShadow(
                      color: Colors.green.withOpacity(0.35), blurRadius: 10)
                ]
              : [BoxShadow(color: AppColors.shadow(dark), blurRadius: 4)],
        ),
        child: isLocked
            ? _DashedBorderOverlay(
                dark: dark,
                child: _cardContent(context, status),
              )
            : _cardContent(context, status),
      ),
    );
  }

  Widget _cardContent(BuildContext context, String status) {
    final isDone = status == 'done';
    final isLocked = status == 'locked';
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLocked)
            Icon(Icons.lock_rounded,
                color: AppColors.textTertiary(dark), size: 22)
          else
            Text(_emojiFor(word['en'] ?? ''),
                style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 8),
          Text(
            isLocked ? 'Locked' : (word['en'] ?? ''),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isLocked
                  ? AppColors.textTertiary(dark)
                  : isDone
                      ? Colors.greenAccent
                      : AppColors.textPrimary(dark),
            ),
          ),
          if (!isLocked && (word['th'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(word['th']!,
                style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 11,
                    fontStyle: FontStyle.italic)),
          ],
          if (isDone) ...[
            const SizedBox(height: 4),
            const Icon(Icons.check_circle_rounded,
                color: Colors.greenAccent, size: 16),
          ],
        ],
      ),
    );
  }

  String _emojiFor(String word) {
    const map = {
      'cat': '🐱',
      'dog': '🐶',
      'bird': '🐦',
      'fish': '🐟',
      'horse': '🐴',
      'cow': '🐮',
      'sheep': '🐑',
      'rabbit': '🐰',
      'duck': '🦆',
      'frog': '🐸',
      'red': '🔴',
      'blue': '🔵',
      'green': '🟢',
      'yellow': '🟡',
      'purple': '🟣',
      'orange': '🟠',
      'black': '⚫',
      'white': '⚪',
      'chair': '🪑',
      'table': '🪵',
      'sofa': '🛋️',
      'bed': '🛏️',
      'lamp': '💡',
      'shelf': '📚',
      'mirror': '🪞',
      'desk': '🖥️',
      'rug': '🟫',
      'curtain': '🪟',
      'closet': '🚪',
      'stool': '🪑',
      'rice': '🍚',
      'bread': '🍞',
      'egg': '🥚',
      'apple': '🍎',
      'banana': '🍌',
      'milk': '🥛',
      'water': '💧',
      'noodle': '🍜',
      'soup': '🍲',
      'cake': '🍰',
    };
    return map[word.toLowerCase()] ?? '📦';
  }
}

/// Dashed-border overlay used for locked cards, drawn on top of the
/// rounded rect so the underlying card still shows its solid border.
class _DashedBorderOverlay extends StatelessWidget {
  final Widget child;
  final bool dark;
  const _DashedBorderOverlay({required this.child, required this.dark});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter:
          _DashedRRectPainter(color: AppColors.textTertiary(dark)),
      child: Opacity(opacity: 0.6, child: child),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  _DashedRRectPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(15));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dashLength = 5.0, gapLength = 4.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate.color != color;
}
