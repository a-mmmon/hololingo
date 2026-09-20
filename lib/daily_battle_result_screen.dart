import 'package:flutter/material.dart';

import 'app_theme.dart';

class DailyBattleResultScreen extends StatelessWidget {
  final bool won;
  final bool isDraw;
  final int myScore;
  final int theirScore;
  final int wager;

  const DailyBattleResultScreen({
    super.key,
    required this.won,
    required this.isDraw,
    required this.myScore,
    required this.theirScore,
    required this.wager,
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

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDraw
                    ? Icons.handshake_rounded
                    : won
                        ? Icons.emoji_events_rounded
                        : Icons.sentiment_dissatisfied_rounded,
                color: color,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                headline,
                style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _scoreChip(dark, 'You', myScore, won && !isDraw),
                  const SizedBox(width: 16),
                  Text('vs', style: TextStyle(color: AppColors.textSecondary(dark))),
                  const SizedBox(width: 16),
                  _scoreChip(dark, 'Opponent', theirScore, !won && !isDraw),
                ],
              ),
              const SizedBox(height: 16),
              if (!isDraw)
                Text(
                  won ? '+$wager tokens' : '-$wager tokens',
                  style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
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
            ],
          ),
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
