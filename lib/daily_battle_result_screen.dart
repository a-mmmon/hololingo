import 'package:flutter/material.dart';

import 'app_theme.dart';

class DailyBattleResultScreen extends StatelessWidget {
  final bool won;
  final bool isDraw;
  final int myScore;
  final int theirScore;
  final int wager;
  final List<Map<String, dynamic>> review;

  const DailyBattleResultScreen({
    super.key,
    required this.won,
    required this.isDraw,
    required this.myScore,
    required this.theirScore,
    required this.wager,
    this.review = const [],
  });

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    final headline = isDraw
        ? "It's a draw"
        : won
            ? 'You won!'
            : 'You lost';

    final color = isDraw
        ? AppColors.textSecondary(dark)
        : won
            ? Colors.green
            : AppColors.wrongText(dark);

    final correctCount = review.where((r) => r['isCorrect'] == true).length;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                children: [
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          isDraw
                              ? Icons.handshake_rounded
                              : won
                                  ? Icons.emoji_events_rounded
                                  : Icons.sentiment_dissatisfied_rounded,
                          color: color,
                          size: 72,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          headline,
                          style: TextStyle(
                            color: AppColors.textPrimary(dark),
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _scoreChip(dark, 'You', myScore, won && !isDraw),
                            const SizedBox(width: 16),
                            Text('vs',
                                style: TextStyle(
                                    color: AppColors.textSecondary(dark))),
                            const SizedBox(width: 16),
                            _scoreChip(
                                dark, 'Opponent', theirScore, !won && !isDraw),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (!isDraw)
                          Text(
                            won ? '+$wager tokens' : '-$wager tokens',
                            style: TextStyle(
                              color: color,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (review.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'ANSWERS ($correctCount/${review.length} correct)',
                      style: TextStyle(
                        color: AppColors.textSecondary(dark),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...review.map((r) => _ReviewRow(round: r, dark: dark)),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreChip(bool dark, String label, int score, bool highlight) {
    return Column(
      children: [
        Text(
          '$score',
          style: TextStyle(
            color: highlight ? AppColors.cyan : AppColors.textPrimary(dark),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final Map<String, dynamic> round;
  final bool dark;

  const _ReviewRow({required this.round, required this.dark});

  @override
  Widget build(BuildContext context) {
    final thai = (round['thai'] ?? '').toString();
    final correctAnswer = (round['correctAnswer'] ?? '').toString();
    final myAnswer = round['myAnswer'] as String?;
    final isCorrect = round['isCorrect'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCorrect
              ? Colors.green.withValues(alpha: 0.35)
              : AppColors.wrongText(dark).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: isCorrect ? Colors.green : AppColors.wrongText(dark),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  thai,
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isCorrect
                      ? correctAnswer
                      : 'You: ${myAnswer ?? '—'} · Correct: $correctAnswer',
                  style: TextStyle(
                    color: isCorrect
                        ? AppColors.textSecondary(dark)
                        : AppColors.wrongText(dark),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
