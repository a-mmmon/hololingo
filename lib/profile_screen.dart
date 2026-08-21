import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = 'Nattaya K.';
  String _city = 'Bangkok';
  String _language = 'English (US)';
  int _wordsSaved = 48;
  int _totalXp = 2340;
  int _level = 12;
  int _xpToNext = 3000;
  bool _autoTts = true;

  // Weekly streak: which days are completed (Mon=0 … Sun=6)
  final List<bool> _streak = [true, true, true, true, true, true, false];
  final List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _name = prefs.getString('profile_name') ?? 'Nattaya K.';
      _city = prefs.getString('profile_city') ?? 'Bangkok';
      _language = prefs.getString('profile_language') ?? 'English (US)';
      _wordsSaved = prefs.getInt('words_saved') ?? 48;
      _totalXp = prefs.getInt('total_xp') ?? 2340;
      _level = prefs.getInt('level') ?? 12;
      _autoTts = prefs.getBool('auto_tts') ?? true;
    });
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    if (result == true) _loadProfile();
  }

  String get _levelLabel {
    if (_level < 5) return 'Beginner';
    if (_level < 10) return 'Elementary';
    if (_level < 15) return 'Intermediate';
    if (_level < 20) return 'Advanced';
    return 'Expert';
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final xpProgress = _totalXp / _xpToNext;
    final xpLeft = _xpToNext - _totalXp;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar + name ────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.cyan.withOpacity(0.2),
                            border:
                                Border.all(color: AppColors.cyan, width: 2.5),
                          ),
                          child: Center(
                            child: Text(
                              _name.isNotEmpty ? _name[0].toUpperCase() : 'N',
                              style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.cyan),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: -4,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB300),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('Lv $_level',
                                  style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(_name,
                        style: TextStyle(
                            color: AppColors.textPrimary(dark),
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Learning $_language  ·  $_city',
                        style: TextStyle(
                            color: AppColors.textSecondary(dark),
                            fontSize: 13)),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _openEdit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: AppColors.border(dark), width: 1.5),
                        ),
                        child: Text('Edit profile',
                            style: TextStyle(
                                color: AppColors.textPrimary(dark),
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Stats row ────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.border(dark)),
                    bottom: BorderSide(color: AppColors.border(dark)),
                  ),
                ),
                child: Row(
                  children: [
                    _StatItem(
                        value: '$_wordsSaved',
                        label: 'Words saved',
                        dark: dark),
                    _Divider(dark: dark),
                    _StatItem(value: '$_level', label: 'Level', dark: dark),
                    _Divider(dark: dark),
                    _StatItem(
                        value: '$_totalXp', label: 'Total XP', dark: dark),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── XP Progress ──────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Level $_level – $_levelLabel',
                      style: TextStyle(
                          color: AppColors.textSecondary(dark), fontSize: 13)),
                  Text('$_totalXp / $_xpToNext XP',
                      style: const TextStyle(
                          color: Color(0xFFFFB300),
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: xpProgress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.secondary(dark),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)),
                ),
              ),
              const SizedBox(height: 6),
              Text('$xpLeft XP to level ${_level + 1}',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark), fontSize: 12)),

              const SizedBox(height: 24),

              // ── Weekly Streak ────────────────────────────────────────────
              Text('WEEKLY STREAK',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) {
                  final done = _streak[i];
                  return Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done
                              ? AppColors.cyan.withOpacity(0.15)
                              : Colors.transparent,
                          border: Border.all(
                            color:
                                done ? AppColors.cyan : AppColors.border(dark),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(_dayLabels[i],
                              style: TextStyle(
                                  color: done
                                      ? AppColors.cyan
                                      : AppColors.textSecondary(dark),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  );
                }),
              ),

              const SizedBox(height: 28),
              Divider(color: AppColors.border(dark)),
              const SizedBox(height: 8),

              // ── LEARNING section ─────────────────────────────────────────
              Text('LEARNING',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),

              _SettingsRow(
                iconBg: const Color(0xFF0D3B4A),
                iconColor: AppColors.cyan,
                icon: Icons.menu_book_rounded,
                title: 'Language manager',
                subtitle: 'Manage your languages',
                dark: dark,
              ),
              _SettingsRow(
                iconBg: const Color(0xFF3A1A0D),
                iconColor: const Color(0xFFFF6B2B),
                icon: Icons.description_rounded,
                title: 'My language',
                subtitle: _language,
                dark: dark,
              ),
              _SettingsRow(
                iconBg: const Color(0xFF0D3A1A),
                iconColor: const Color(0xFF4CAF50),
                icon: Icons.save_rounded,
                title: 'Saved words',
                subtitle: '3 days ago',
                dark: dark,
              ),
              _SettingsRow(
                iconBg: const Color(0xFF3A2D00),
                iconColor: const Color(0xFFFFB300),
                icon: Icons.star_rounded,
                title: 'Daily word goal',
                subtitle: '10 words / day',
                dark: dark,
              ),
              _SettingsRow(
                iconBg: const Color(0xFF1A0D3A),
                iconColor: const Color(0xFF9C6FFF),
                icon: Icons.music_note_rounded,
                title: 'Auto text-to-speech',
                subtitle: 'Read words on scan',
                dark: dark,
                trailing: Switch(
                  value: _autoTts,
                  activeColor: AppColors.cyan,
                  onChanged: (v) async {
                    setState(() => _autoTts = v);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('auto_tts', v);
                  },
                ),
              ),

              const SizedBox(height: 8),
              Divider(color: AppColors.border(dark)),
              const SizedBox(height: 8),

              // ── APP section ──────────────────────────────────────────────
              Text('APP',
                  style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),

              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.dark_mode_rounded,
                title: 'Dark mode',
                subtitle: 'Always on',
                dark: dark,
                trailing: Switch(
                  value: dark,
                  activeColor: AppColors.cyan,
                  onChanged: (_) => ThemeProvider.of(context).toggle(),
                ),
              ),
              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.upload_rounded,
                title: 'Export vocabulary',
                subtitle: 'Download as CSV',
                dark: dark,
              ),
              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Help & feedback',
                subtitle: '',
                dark: dark,
              ),
              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.info_outline_rounded,
                title: 'App version',
                subtitle: 'Hololingo v1.0.0',
                dark: dark,
                trailing: Text('Latest',
                    style: TextStyle(
                        color: AppColors.textSecondary(dark), fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Stat Item ─────────────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String value, label;
  final bool dark;
  const _StatItem(
      {required this.value, required this.label, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary(dark), fontSize: 12)),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool dark;
  const _Divider({required this.dark});
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 40, color: AppColors.border(dark));
  }
}

// ── Settings Row ──────────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  final Color iconBg, iconColor;
  final IconData icon;
  final String title, subtitle;
  final bool dark;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dark,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                      style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: TextStyle(
                            color: AppColors.textSecondary(dark),
                            fontSize: 12)),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondary(dark), size: 20),
          ],
        ),
      ),
    );
  }
}
