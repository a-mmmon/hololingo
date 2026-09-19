import 'package:flutter/material.dart';

import 'app_theme.dart';

class BattleResultScreen extends StatelessWidget {
  final bool won;
  final bool isDraw;
  final int wager;

  const BattleResultScreen({
    super.key,
    required this.won,
    required this.isDraw,
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

    final subtitle = isDraw
        ? 'Both of you missed it — no coins changed hands.'
        : won
            ? 'You take both wagers.'
            : "Better luck next time.";

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
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              if (!isDraw)
                Text(
                  won ? '+$wager coins' : '-$wager coins',
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
                  onPressed: () => Navigator.of(context).pop(),
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
}
