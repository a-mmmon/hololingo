import 'package:flutter/material.dart';
import 'app_theme.dart';

class TopicCompleteScreen extends StatelessWidget {
  final String topicName;
  final int wordsLearned;
  final int tokensEarned;
  final int xpEarned;

  const TopicCompleteScreen({
    super.key,
    required this.topicName,
    required this.wordsLearned,
    required this.tokensEarned,
    required this.xpEarned,
  });

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Text('$topicName complete!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(dark))),
              const SizedBox(height: 8),
              Text('You learned all $wordsLearned words',
                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14)),
              const Spacer(flex: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RewardChip(
                    value: '+$tokensEarned',
                    label: 'Tokens',
                    icon: Icons.circle,
                    color: const Color(0xFFFFB300),
                    bg: const Color(0xFF3A2D00),
                  ),
                  const SizedBox(width: 14),
                  _RewardChip(
                    value: '+$xpEarned',
                    label: 'XP',
                    icon: Icons.star_rounded,
                    color: AppColors.cyan,
                    bg: const Color(0xFF0D2E2E),
                  ),
                ],
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Back to Topics',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color, bg;
  const _RewardChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
              const SizedBox(width: 3),
              Icon(icon, size: 12, color: color),
            ],
          ),
        ],
      ),
    );
  }
}