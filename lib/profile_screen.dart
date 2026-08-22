import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '', _city = '', _language = 'English (US)';
  int _tokens = 0, _wordsSaved = 0, _totalXp = 0, _level = 1, _xpToNext = 3000, _friends = 0;
  bool _autoTts = true, _dailyReminder = true, _reviewReminder = true, _loading = true;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    try {
      final data = await FirestoreService.getProfileOrDefault();
      final friends = await FirestoreService.getFriends();
      if (!mounted) return;
      setState(() {
        _name           = data['name'] ?? 'User';
        _city           = data['city'] ?? '';
        _language       = data['language'] ?? 'English (US)';
        _tokens         = data['tokens'] ?? 0;
        _wordsSaved     = data['words_saved'] ?? 0;
        _totalXp        = data['total_xp'] ?? 0;
        _level          = data['level'] ?? 1;
        _autoTts        = data['auto_tts'] ?? true;
        _dailyReminder  = data['daily_reminder'] ?? true;
        _reviewReminder = data['review_reminder'] ?? true;
        _friends        = friends.length;
        _loading        = false;
      });
    } catch (e) {
      debugPrint('ProfileScreen load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
    if (result == true) _loadProfile();
  }

  // Tapping "X Friends" — shows just the friends list (+ pending requests),
  // no search bar.
  Future<void> _openFriendsList() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const FriendsScreen(mode: FriendsScreenMode.friendsOnly),
    ));
    _loadProfile();
  }

  // Tapping the search icon — shows just the search bar, no friends list.
  Future<void> _openSearch() async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => const FriendsScreen(mode: FriendsScreenMode.searchOnly),
    ));
    _loadProfile();
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) await FirebaseAuth.instance.signOut();
  }

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete all data', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently erase everything. This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirestoreService.deleteAllData();
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All data deleted.'))); _loadProfile(); }
      } catch (e) { debugPrint('Delete all data error: $e'); }
    }
  }

  String get _levelLabel {
    if (_level < 5) return 'Beginner';
    if (_level < 10) return 'Elementary';
    if (_level < 15) return 'Intermediate';
    if (_level < 20) return 'Advanced';
    return 'Expert';
  }

  int get _wordGoal => 10;

  // Level milestone circles — show up to 7 milestones, highlight current
  List<int> get _levelCircles {
    final start = ((_level - 1) ~/ 7) * 7 + 1;
    return List.generate(7, (i) => start + i);
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: const Center(child: CircularProgressIndicator(color: AppColors.cyan)));
    }

    final xpProgress = _xpToNext == 0 ? 0.0 : _totalXp / _xpToNext;
    final xpLeft = _xpToNext - _totalXp;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Top bar — search + edit icons ─────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _openSearch,
                  icon: Icon(Icons.search_rounded, color: AppColors.textPrimary(dark)),
                ),
                IconButton(
                  onPressed: _openEdit,
                  icon: Icon(Icons.edit_outlined, color: AppColors.textPrimary(dark)),
                ),
              ],
            ),

            // Avatar + name
            Center(
              child: Column(children: [
                Stack(clipBehavior: Clip.none, children: [
                  Container(
                    width: 88, height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.cyan.withValues(alpha: 0.2),
                      border: Border.all(color: AppColors.cyan, width: 2.5)),
                    child: Center(child: Text(
                      _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: AppColors.cyan)))),
                  Positioned(
                    bottom: -4, left: 0, right: 0,
                    child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFFFB300), borderRadius: BorderRadius.circular(20)),
                      child: Text('Lv $_level', style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800))))),
                ]),
                const SizedBox(height: 18),
                Text(_name.isNotEmpty ? _name : 'User',
                  style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: _openFriendsList,
                  child: Text('$_friends Friends',
                    style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),

            const SizedBox(height: 28),

            // ── Stats row — Tokens / Level / Total XP ────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border(dark)),
                  bottom: BorderSide(color: AppColors.border(dark)))),
              child: Row(children: [
                _StatItem(value: '$_tokens', label: 'Tokens', dark: dark),
                _Divider(dark: dark),
                _StatItem(value: '$_level', label: 'Level', dark: dark),
                _Divider(dark: dark),
                _StatItem(value: '$_totalXp', label: 'Total XP', dark: dark),
              ]),
            ),

            const SizedBox(height: 20),

            // XP Progress
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Level $_level – $_levelLabel', style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13)),
              Text('$_totalXp / $_xpToNext XP', style: const TextStyle(color: Color(0xFFFFB300), fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: xpProgress.clamp(0.0, 1.0), minHeight: 8,
                backgroundColor: AppColors.secondary(dark),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)))),
            const SizedBox(height: 6),
            Text('${xpLeft < 0 ? 0 : xpLeft} XP to level ${_level + 1}',
              style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),

            const SizedBox(height: 24),

            // ── Level milestone circles ───────────────────────────────────────
            Text('Level', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _levelCircles.map((lvl) {
                final isCurrent = lvl == _level;
                final isPast = lvl < _level;
                return Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent
                      ? AppColors.cyan
                      : isPast
                        ? AppColors.cyan.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(
                      color: isCurrent || isPast ? AppColors.cyan : AppColors.border(dark),
                      width: 1.5)),
                  child: Center(child: Text('$lvl',
                    style: TextStyle(
                      color: isCurrent ? Colors.black : isPast ? AppColors.cyan : AppColors.textSecondary(dark),
                      fontSize: 13, fontWeight: FontWeight.w700))));
              }).toList(),
            ),

            const SizedBox(height: 28),
            Divider(color: AppColors.border(dark)),
            const SizedBox(height: 8),

            // LEARNING
            Text('LEARNING', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            _SettingsRow(iconBg: const Color(0xFF0D3B4A), iconColor: AppColors.cyan, icon: Icons.menu_book_rounded, title: 'Language manager', subtitle: 'Manage your languages', dark: dark),
            _SettingsRow(iconBg: const Color(0xFF3A1A0D), iconColor: const Color(0xFFFF6B2B), icon: Icons.description_rounded, title: 'My language', subtitle: _language, dark: dark),
            _SettingsRow(iconBg: const Color(0xFF0D3A1A), iconColor: const Color(0xFF4CAF50), icon: Icons.save_rounded, title: 'Saved words', subtitle: '$_wordsSaved words', dark: dark),
            _SettingsRow(iconBg: const Color(0xFF3A2D00), iconColor: const Color(0xFFFFB300), icon: Icons.star_rounded, title: 'Daily word goal', subtitle: '$_wordGoal words / day', dark: dark),
            _SettingsRow(
              iconBg: const Color(0xFF1A0D3A), iconColor: const Color(0xFF9C6FFF),
              icon: Icons.music_note_rounded, title: 'Auto text-to-speech', subtitle: 'Read words on scan', dark: dark,
              trailing: Switch(value: _autoTts, activeThumbColor: AppColors.cyan, onChanged: (v) async {
                setState(() => _autoTts = v);
                try { await FirestoreService.updateProfile({'auto_tts': v}); } catch (e) { debugPrint('auto_tts: $e'); }
              })),

            const SizedBox(height: 8),
            Divider(color: AppColors.border(dark)),
            const SizedBox(height: 8),

            // APP
            Text('APP', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            _SettingsRow(
              iconBg: AppColors.secondary(dark), iconColor: AppColors.textSecondary(dark),
              icon: Icons.dark_mode_rounded, title: 'Dark mode', subtitle: 'Always on', dark: dark,
              trailing: Switch(value: dark, activeThumbColor: AppColors.cyan, onChanged: (_) => ThemeProvider.of(context).toggle())),
            _SettingsRow(iconBg: AppColors.secondary(dark), iconColor: AppColors.textSecondary(dark), icon: Icons.upload_rounded, title: 'Export vocabulary', subtitle: 'Download as CSV', dark: dark),
            _SettingsRow(iconBg: AppColors.secondary(dark), iconColor: AppColors.textSecondary(dark), icon: Icons.chat_bubble_outline_rounded, title: 'Help & feedback', subtitle: '', dark: dark),
            _SettingsRow(
              iconBg: AppColors.secondary(dark), iconColor: AppColors.textSecondary(dark),
              icon: Icons.info_outline_rounded, title: 'App version', subtitle: 'Hololingo v1.0.0', dark: dark,
              trailing: Text('Latest', style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12))),

            const SizedBox(height: 8),
            Divider(color: AppColors.border(dark)),
            const SizedBox(height: 8),

            // NOTIFICATIONS
            Text('NOTIFICATIONS', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const SizedBox(height: 8),
            _SettingsRow(
              iconBg: const Color(0xFF3A2D00), iconColor: const Color(0xFFFFB300),
              icon: Icons.notifications_rounded, title: 'Daily reminder', subtitle: '8:00 PM every day', dark: dark,
              trailing: Switch(value: _dailyReminder, activeThumbColor: AppColors.cyan, onChanged: (v) async {
                setState(() => _dailyReminder = v);
                try { await FirestoreService.updateProfile({'daily_reminder': v}); } catch (e) { debugPrint('$e'); }
              })),
            _SettingsRow(
              iconBg: const Color(0xFF0D3A1A), iconColor: const Color(0xFF4CAF50),
              icon: Icons.refresh_rounded, title: 'Review reminders', subtitle: 'Weekly · monthly', dark: dark,
              trailing: Switch(value: _reviewReminder, activeThumbColor: AppColors.cyan, onChanged: (v) async {
                setState(() => _reviewReminder = v);
                try { await FirestoreService.updateProfile({'review_reminder': v}); } catch (e) { debugPrint('$e'); }
              })),

            const SizedBox(height: 24),

            // Delete all data
            GestureDetector(
              onTap: _deleteAllData,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Delete all data', style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Permanently erase everything', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ]))),

            const SizedBox(height: 20),

            // Sign out
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Sign out', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.w600)))),

            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }
}

// ── Stat Item ──────────────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final String value, label;
  final bool dark;
  final VoidCallback? onTap;
  const _StatItem({required this.value, required this.label, required this.dark, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(children: [
        Text(value, style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11), textAlign: TextAlign.center),
      ])));
}

class _Divider extends StatelessWidget {
  final bool dark;
  const _Divider({required this.dark});
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 40, color: AppColors.border(dark));
}

// ── Settings Row ───────────────────────────────────────────────────────────────
class _SettingsRow extends StatelessWidget {
  final Color iconBg, iconColor;
  final IconData icon;
  final String title, subtitle;
  final bool dark;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({required this.iconBg, required this.iconColor, required this.icon,
    required this.title, required this.subtitle, required this.dark, this.trailing}) : onTap = null;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 15, fontWeight: FontWeight.w500)),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
        ])),
        if (trailing != null) trailing!
        else Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary(dark), size: 20),
      ])));
}