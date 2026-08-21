import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'topics_data.dart';
import 'topic_word_grid_screen.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  int _level = 1;
  int _xp = 0;
  int _xpToNextLevel = 3000;
  bool _loading = true;
  Map<String, dynamic> _progress = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final profile = await FirestoreService.getProfileOrDefault();
      final progress = await FirestoreService.getTopicProgress();
      if (!mounted) return;
      setState(() {
        _level = profile['level'] ?? 1;
        _xp = profile['total_xp'] ?? 0;
        _progress = progress;
        _loading = false;
      });
    } catch (e) {
      debugPrint('TopicsScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int _learnedCount(TopicDef topic) {
    final learned = (_progress[topic.id] as List?)?.cast<String>() ?? [];
    return learned.length;
  }

  bool _isComplete(TopicDef topic) => _learnedCount(topic) >= topic.words.length;

  // First topic that isn't complete; falls back to the last topic.
  TopicDef get _activeTopic => kTopics.firstWhere(
        (t) => !_isComplete(t),
        orElse: () => kTopics.last,
      );

  bool _isLocked(TopicDef topic) {
    final index = kTopics.indexOf(topic);
    if (index == 0) return false;
    // A topic unlocks once the previous one is complete.
    return !_isComplete(kTopics[index - 1]);
  }

  Future<void> _openTopic(TopicDef topic) async {
    if (_isLocked(topic)) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TopicWordGridScreen(topic: topic)),
    );
    if (result == true) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final progress =
        _xpToNextLevel == 0 ? 0.0 : (_xp / _xpToNextLevel).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.cyan))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Topics',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(dark),
                                letterSpacing: -0.5)),
                        const SizedBox(height: 6),
                        Text('Level $_level · $_xp XP',
                            style: TextStyle(
                                color: AppColors.textSecondary(dark),
                                fontSize: 14)),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppColors.secondary(dark),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.cyan),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _TopicMap(
                        activeTopic: _activeTopic,
                        learnedCount: _learnedCount,
                        isComplete: _isComplete,
                        isLocked: _isLocked,
                        onTapTopic: _openTopic,
                        dark: dark,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openTopic(_activeTopic),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          _learnedCount(_activeTopic) == 0
                              ? 'Start ${_activeTopic.name}'
                              : 'Continue ${_activeTopic.name}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
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

// ── Illustrated map ───────────────────────────────────────────────────────
class _TopicMap extends StatelessWidget {
  final TopicDef activeTopic;
  final int Function(TopicDef) learnedCount;
  final bool Function(TopicDef) isComplete;
  final bool Function(TopicDef) isLocked;
  final void Function(TopicDef) onTapTopic;
  final bool dark;

  const _TopicMap({
    required this.activeTopic,
    required this.learnedCount,
    required this.isComplete,
    required this.isLocked,
    required this.onTapTopic,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final points = kTopics
            .map((t) => Offset(t.pos.dx * size.width, t.pos.dy * size.height))
            .toList();
        final activeIndex = kTopics.indexOf(activeTopic);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border(dark)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _MapBackdropPainter(dark: dark))),
              Positioned.fill(
                  child: CustomPaint(painter: _PathPainter(points: points, dark: dark))),
              // Walking figure sits at the active topic's node
              if (activeIndex >= 0 && activeIndex < points.length)
                Positioned(
                  left: points[activeIndex].dx - 12,
                  top: points[activeIndex].dy - 66,
                  child: const Icon(Icons.directions_walk_rounded,
                      color: AppColors.flame, size: 26),
                ),
              for (int i = 0; i < kTopics.length; i++)
                _buildNode(kTopics[i], points[i]),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNode(TopicDef topic, Offset center) {
    const nodeSize = 56.0;
    final complete = isComplete(topic);
    final locked = isLocked(topic);
    final isActive = topic.id == activeTopic.id;

    return Positioned(
      left: center.dx - nodeSize / 2,
      top: center.dy - nodeSize / 2 - 18,
      child: GestureDetector(
        onTap: () => onTapTopic(topic),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (isActive)
                  Container(
                    width: nodeSize + 16,
                    height: nodeSize + 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.5), width: 2),
                    ),
                  ),
                Container(
                  width: nodeSize,
                  height: nodeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: locked
                        ? AppColors.secondary(dark)
                        : topic.color.withValues(alpha: 0.18),
                    border: Border.all(
                      color: locked ? AppColors.border(dark) : topic.color,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.shadow(dark),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Icon(
                    locked ? Icons.lock_rounded : topic.icon,
                    color: locked ? AppColors.textTertiary(dark) : topic.color,
                    size: 24,
                  ),
                ),
                if (complete)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        border: Border.all(color: AppColors.card(dark), width: 2),
                      ),
                      child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.bg(dark).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                topic.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: locked ? AppColors.textTertiary(dark) : AppColors.textPrimary(dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dashed winding path ──────────────────────────────────────────────────
class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final bool dark;
  const _PathPainter({required this.points, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final length = math.sqrt(dx * dx + dy * dy);
      final perp = length == 0 ? const Offset(0, 0) : Offset(-dy / length, dx / length);
      final wiggle = (i.isEven ? 1 : -1) * length * 0.16;
      final control = mid + perp * wiggle;
      path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    final dashed = _dashPath(path, dashLength: 8, gapLength: 6);
    final paint = Paint()
      ..color = const Color(0xFF2D2D2D).withValues(alpha: 0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(dashed, paint);
  }

  Path _dashPath(Path source, {required double dashLength, required double gapLength}) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      bool draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        final next = (distance + len).clamp(0.0, metric.length);
        if (draw) dest.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _PathPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.dark != dark;
}

// ── Stylized map illustration backdrop ───────────────────────────────────
class _MapBackdropPainter extends CustomPainter {
  final bool dark;
  const _MapBackdropPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = const Color(0xFFE4E9F0);
    canvas.drawRect(Offset.zero & size, base);

    final green = Paint()..color = const Color(0xFFB9DCC0);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.30),
        width: size.width * 0.4, height: size.height * 0.22), green);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(size.width * 0.85, size.height * 0.5),
        width: size.width * 0.28, height: size.height * 0.16), green);

    final water = Paint()..color = const Color(0xFFAFCBE8);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(size.width * 0.75, size.height * 0.85),
        width: size.width * 0.5, height: size.height * 0.22), water);
    canvas.drawOval(Rect.fromCenter(
        center: Offset(size.width * 0.15, size.height * 0.75),
        width: size.width * 0.22, height: size.height * 0.14), water);

    final street = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += size.width / 6) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), street);
    }
    for (double y = 0; y < size.height; y += size.height / 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), street);
    }
  }

  @override
  bool shouldRepaint(covariant _MapBackdropPainter oldDelegate) => oldDelegate.dark != dark;
}