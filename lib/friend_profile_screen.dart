import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Friend profile — matches the "Pim K." profile design:
/// back arrow + name + BFF badge, 3 stat boxes (Friends/Level/Bond),
/// a gold bond progress bar, an events-participated chip row, and a
/// reward items grid.
///
/// TODO(Person 3): pass real data in via constructor once
/// FirestoreService exposes a friend-detail method — this screen is
/// UI-only and expects plain values, no Firestore calls here.
class FriendProfileScreen extends StatelessWidget {
  final String name;
  final int level;
  final bool isBff;
  final int friendsCount;
  final int bondCurrent;
  final int bondGoal;
  final List<String> eventsParticipated;

  const FriendProfileScreen({
    super.key,
    required this.name,
    required this.level,
    required this.isBff,
    this.friendsCount = 12,
    this.bondCurrent = 15,
    this.bondGoal = 20,
    this.eventsParticipated = const [
      'Treasure Hunt',
      'Word Rush',
      'Colors Sprint'
    ],
  });

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final bondProgress = (bondCurrent / bondGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  Expanded(
                    child: Text(name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(dark))),
                  ),
                  if (isBff)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFFB300)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('BFF',
                              style: TextStyle(
                                  color: Color(0xFFFFB300),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(width: 4),
                          Icon(Icons.star_rounded,
                              color: Color(0xFFFFB300), size: 14),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cyan, width: 2.5),
                    color: AppColors.card(dark),
                  ),
                  child: Center(
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AppColors.cyan)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      color: const Color(0xFF9C6FFF),
                      label: 'Friends',
                      value: '$friendsCount',
                      dark: dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      color: AppColors.cyan,
                      label: 'Level',
                      value: '$level',
                      dark: dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      color: Colors.green,
                      label: 'Bond',
                      value: '$bondCurrent/$bondGoal',
                      dark: dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: bondProgress,
                  backgroundColor: AppColors.secondary(dark),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 28),
              Text('EVENTS PARTICIPATED',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: eventsParticipated
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card(dark),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border(dark)),
                          ),
                          child: Text(e,
                              style: TextStyle(
                                  color: AppColors.textPrimary(dark),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 28),
              Text('REWARD ITEMS',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _RewardTile(
                      color: const Color(0xFF9C6FFF),
                      bg: const Color(0xFF16103A),
                      icon: '🎈',
                      label: 'Balloon',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RewardTile(
                      color: const Color(0xFF7C8C3A),
                      bg: const Color(0xFF1F2410),
                      icon: '🖼️',
                      label: 'Profile skin',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final Color color;
  final String label, value;
  final bool dark;
  const _StatBox(
      {required this.color,
      required this.label,
      required this.value,
      required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary(dark), fontSize: 11)),
        ],
      ),
    );
  }
}

class _RewardTile extends StatelessWidget {
  final Color color, bg;
  final String icon, label;
  const _RewardTile(
      {required this.color,
      required this.bg,
      required this.icon,
      required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
