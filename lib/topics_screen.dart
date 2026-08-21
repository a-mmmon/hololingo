import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'topics_data.dart';
import 'topic_word_screen.dart';

/// Topics map screen — matches the "Topics.png" design:
/// header with level/XP, a progress bar, a map with topic nodes
/// connected by a dotted path, and a "Continue <topic>" CTA button.
class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  // TODO(Person 3): replace with real profile level/XP once wired to Firestore.
  static const int _level = 8;
  static const int _xp = 2340;
  static const int _xpForNextLevel = 3000;

  void _openTopic(TopicNode topic) async {
    final words = topicWords[topic.id] ?? [];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TopicWordScreen(topicName: topic.name, words: words),
      ),
    );
    if (mounted) setState(() {}); // refresh progress after returning
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final next = nextIncompleteTopic();
    final progress = (_xp / _xpForNextLevel).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text('Topics',
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(dark),
                      letterSpacing: -0.5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text('Level $_level · ${_xp.toString()} XP',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark), fontSize: 13)),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
            const SizedBox(height: 18),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: _TopicMap(dark: dark, onTapTopic: _openTopic),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GestureDetector(
                onTap: next == null ? null : () => _openTopic(next),
                child: Opacity(
                  opacity: next == null ? 0.5 : 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          next == null ? 'All topics complete 🎉' : 'Continue ',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                        if (next != null)
                          Text(next.name,
                              style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        if (next != null) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.black, size: 20),
                        ],
                      ],
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

class _TopicMap extends StatelessWidget {
  final bool dark;
  final void Function(TopicNode) onTapTopic;
  const _TopicMap({required this.dark, required this.onTapTopic});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      return Container(
        width: w,
        height: h,
        color: dark ? const Color(0xFFB9C6D6) : const Color(0xFFE3E9F1),
        child: Stack(
          children: [
            // Decorative "streets" background
            CustomPaint(size: Size(w, h), painter: _MapBackgroundPainter()),
            // Dotted path between nodes, in visit order
            CustomPaint(
              size: Size(w, h),
              painter: _PathPainter(
                points: topicNodes
                    .map((t) => Offset(t.mapX * w, t.mapY * h))
                    .toList(),
              ),
            ),
            for (final topic in topicNodes)
              Positioned(
                left: topic.mapX * w - 34,
                top: topic.mapY * h - 34,
                child: _TopicPin(
                  topic: topic,
                  complete: isTopicComplete(topic.id),
                  onTap: () => onTapTopic(topic),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _TopicPin extends StatelessWidget {
  final TopicNode topic;
  final bool complete;
  final VoidCallback onTap;
  const _TopicPin(
      {required this.topic, required this.complete, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = complete ? Colors.green : AppColors.cyan;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14212E),
              border: Border.all(color: color, width: 3),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)
              ],
            ),
            child: Center(
              child: Text(topic.icon, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF14212E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(topic.name,
                style: TextStyle(
                    color: complete ? Colors.greenAccent : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _MapBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blockPaint = Paint()..color = const Color(0xFFCED9E6);
    final greenPaint = Paint()..color = const Color(0xFFC7E0C8);
    final waterPaint = Paint()..color = const Color(0xFFA9CBEA);

    canvas.drawRect(
        Rect.fromLTWH(
            0, size.height * 0.55, size.width * 0.3, size.height * 0.25),
        greenPaint);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.65, size.height * 0.1, size.width * 0.35,
            size.height * 0.2),
        greenPaint);
    canvas.drawOval(
        Rect.fromLTWH(size.width * 0.35, size.height * 0.38, size.width * 0.18,
            size.height * 0.1),
        waterPaint);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.55, size.height * 0.6, size.width * 0.12,
            size.height * 0.35),
        waterPaint);
    canvas.drawRect(
        Rect.fromLTWH(size.width * 0.05, size.height * 0.05, size.width * 0.2,
            size.height * 0.15),
        blockPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PathPainter extends CustomPainter {
  final List<Offset> points;
  _PathPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFF14212E)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < points.length - 1; i++) {
      _drawDashedLine(canvas, points[i], points[i + 1], paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLength = 6.0, gapLength = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    double drawn = 0;
    while (drawn < total) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dashLength).clamp(0, total);
      canvas.drawLine(start, end, paint);
      drawn += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
