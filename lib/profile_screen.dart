import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'app_theme.dart';
import 'database_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _wordCount = 0;
  bool _autoTts = true;
  bool _reminders = true;
  String _profileName = 'Nattaya K.';
  String _profileCity = 'Bangkok';
  String _profileLanguage = 'English (US)';

  final List<bool> _streakDays = [true, true, true, true, true, true, false];
  final List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _loadWordCount();
    _loadProfile();
  }

  Future<void> _loadWordCount() async {
    final words = await DatabaseService.getSavedWords();
    if (mounted) setState(() => _wordCount = words.length);
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _profileName = prefs.getString('profile_name') ?? 'Nattaya K.';
        _profileCity = prefs.getString('profile_city') ?? 'Bangkok';
        _profileLanguage =
            prefs.getString('profile_language') ?? 'English (US)';
      });
    }
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await DatabaseService.exportToCsv();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/vocabulary.csv');
      await file.writeAsString(csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported $_wordCount words to CSV!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Export failed. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const int dayStreak = 7;
    const int totalXp = 2340;
    const int currentLevelXp = 2340;
    const int nextLevelXp = 3000;
    const int level = 12;
    final double xpProgress = currentLevelXp / nextLevelXp;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar + Name ────────────────────────────────────────────
              const SizedBox(height: 28),
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.cyan, width: 2.5),
                        color: AppColors.card,
                      ),
                      child: Center(
                        child: Text(
                          _profileName.isNotEmpty
                              ? _profileName[0].toUpperCase()
                              : 'N',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: AppColors.cyan),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB300),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Lv $level',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(_profileName,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                    'Learning $_profileLanguage · $_profileCity',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 14),
              Center(
                child: OutlinedButton(
                  onPressed: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EditProfileScreen()),
                    );
                    if (updated == true) _loadProfile();
                  },
                  style: OutlinedButton.styleFrom(
                    side:
                        const BorderSide(color: AppColors.cyan, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 10),
                  ),
                  child: const Text('Edit profile',
                      style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),

              const SizedBox(height: 24),
              // ── Stats Row ────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _StatCell(
                          value: '$_wordCount', label: 'Words saved'),
                      _VertDivider(),
                      _StatCell(
                          value: '$dayStreak', label: 'Day streak'),
                      _VertDivider(),
                      _StatCell(
                          value: _formatXp(totalXp), label: 'Total XP'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              // ── XP Progress ──────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Level $level – Intermediate',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('$currentLevelXp / $nextLevelXp XP',
                            style: const TextStyle(
                                color: Color(0xFFFFB300),
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: xpProgress,
                        backgroundColor: AppColors.bg,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFFFB300)),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                        '${nextLevelXp - currentLevelXp} XP to level ${level + 1}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              // ── Weekly Streak ────────────────────────────────────────────
              _SectionLabel('WEEKLY STREAK'),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final active = _streakDays[i];
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              active ? AppColors.cyan : Colors.white12,
                          width: 2,
                        ),
                        color: active
                            ? AppColors.cyan.withOpacity(0.12)
                            : Colors.transparent,
                      ),
                      child: Center(
                        child: Text(_dayLabels[i],
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: active
                                    ? AppColors.cyan
                                    : AppColors.textSecondary)),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 24),
              // ── Learning Settings ────────────────────────────────────────
              _SectionLabel('LEARNING'),
              const SizedBox(height: 8),
              _SettingsItem(
                icon: Icons.menu_book_rounded,
                iconBg: const Color(0xFF1B4B6B),
                iconColor: const Color(0xFF29B6F6),
                title: 'Target language',
                subtitle: _profileLanguage,
                onTap: () async {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EditProfileScreen()),
                  );
                  if (updated == true) _loadProfile();
                },
              ),
              _SettingsItem(
                icon: Icons.star_rounded,
                iconBg: const Color(0xFF4B3A00),
                iconColor: const Color(0xFFFFB300),
                title: 'Daily word goal',
                subtitle: '10 words / day',
                onTap: () {},
              ),
              _ToggleItem(
                icon: Icons.music_note_rounded,
                iconBg: const Color(0xFF2D1B6B),
                iconColor: const Color(0xFF9C6FFF),
                title: 'Auto text-to-speech',
                subtitle: 'Read words on scan',
                value: _autoTts,
                onChanged: (v) => setState(() => _autoTts = v),
              ),
              _ToggleItem(
                icon: Icons.refresh_rounded,
                iconBg: const Color(0xFF0B3B2A),
                iconColor: const Color(0xFF26A69A),
                title: 'Review reminders',
                subtitle: 'Weekly + monthly',
                value: _reminders,
                onChanged: (v) => setState(() => _reminders = v),
              ),

              const SizedBox(height: 16),
              // ── App Settings ─────────────────────────────────────────────
              _SectionLabel('APP'),
              const SizedBox(height: 8),
              _ToggleItem(
                icon: Icons.dark_mode_rounded,
                iconBg: const Color(0xFF1A1A2E),
                iconColor: const Color(0xFF7986CB),
                title: 'Dark mode',
                subtitle: 'Always on',
                value: true,
                onChanged: (_) {},
              ),
              _SettingsItem(
                icon: Icons.open_in_new_rounded,
                iconBg: const Color(0xFF1B2B4B),
                iconColor: const Color(0xFF5C9BFF),
                title: 'Export vocabulary',
                subtitle: 'Download as CSV',
                onTap: _exportCsv,
              ),
              _SettingsItem(
                icon: Icons.chat_bubble_outline_rounded,
                iconBg: const Color(0xFF1B2B4B),
                iconColor: const Color(0xFF5C9BFF),
                title: 'Help & feedback',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Send feedback to: hololingo@gmail.com'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
              // ── Sign out ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: OutlinedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: AppColors.card,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        title: const Text('Sign out?',
                            style:
                                TextStyle(color: AppColors.textPrimary)),
                        content: const Text(
                            'Your saved words will remain on this device.',
                            style: TextStyle(
                                color: AppColors.textSecondary)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel',
                                style:
                                    TextStyle(color: AppColors.cyan)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Sign out',
                                style:
                                    TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: Colors.redAccent.withOpacity(0.5),
                        width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  child: const Text('Sign out',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 16)),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatXp(int xp) {
    if (xp >= 1000) {
      final k = xp / 1000;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
    }
    return '$xp';
  }
}

class _StatCell extends StatelessWidget {
  final String value, label;
  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      color: Colors.white10,
      margin: const EdgeInsets.symmetric(vertical: 12));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.2)),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: Colors.white.withOpacity(0.06))),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg, iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom:
                BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.cyan,
            activeTrackColor: AppColors.cyan.withOpacity(0.3),
            inactiveThumbColor: Colors.white30,
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    );
  }
}