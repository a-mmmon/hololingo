import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'edit_profile_screen.dart';
import 'friends_screen.dart';
import 'premium_paywall.dart';
import 'premium_status.dart';
import 'saved_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _city = '';

  int _tokens = 0;
  int _wordsSaved = 0;
  int _totalXp = 0;
  int _level = 1;
  int _xpToNext = 3000;
  int _friends = 0;

  bool _autoTts = true;
  bool _dailyReminder = true;
  bool _reviewReminder = true;
  bool _loading = true;

  bool _isPremium = false;
  DateTime? _premiumExpiresAt;

  // User-selectable learning and reminder settings.
  int _wordGoal = 10;
  TimeOfDay _dailyReminderTime = const TimeOfDay(hour: 20, minute: 0);
  String _reviewReminderFrequency = 'weekly';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await FirestoreService.getProfileOrDefault();
      final friends = await FirestoreService.getFriends();

      // IMPORTANT:
      // Get the real number of saved-word documents.
      // Do not rely on the old words_saved counter.
      final savedWords = await FirestoreService.getSavedWords();

      if (!mounted) return;

      setState(() {
        _name = data['name'] ?? 'User';
        _city = data['city'] ?? '';

        _tokens = data['tokens'] ?? 0;

        // Real count from saved_words collection.
        _wordsSaved = savedWords.length;

        _totalXp = data['total_xp'] ?? 0;
        _level = data['level'] ?? 1;

        _autoTts = data['auto_tts'] ?? true;
        _dailyReminder = data['daily_reminder'] ?? true;
        _reviewReminder = data['review_reminder'] ?? true;
        // Use the same Firestore field as HomeScreen/createUserProfile.
        // Keep daily_word_goal as a fallback for older data.
        _wordGoal = _parseInt(
          data['words_goal'] ?? data['daily_word_goal'],
          10,
        );
        _dailyReminderTime = _parseTimeOfDay(
          data['daily_reminder_time'],
          const TimeOfDay(hour: 20, minute: 0),
        );
        _reviewReminderFrequency =
            _parseFrequency(data['review_reminder_frequency']);

        _friends = friends.length;
        _isPremium = isSubscriptionActive(data);
        _premiumExpiresAt = subscriptionExpiryDate(data);
        _loading = false;
      });

      // Synchronize the profile counter with the real count.
      try {
        await FirestoreService.updateProfile({
          'words_saved': savedWords.length,
        });
      } catch (e) {
        debugPrint('Could not sync words_saved: $e');
      }
    } catch (e) {
      debugPrint('ProfileScreen load error: $e');

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const EditProfileScreen(),
      ),
    );

    if (result == true) {
      _loadProfile();
    }
  }

  Future<void> _openFriendsList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FriendsScreen(
          mode: FriendsScreenMode.friendsOnly,
        ),
      ),
    );

    _loadProfile();
  }

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FriendsScreen(
          mode: FriendsScreenMode.searchOnly,
        ),
      ),
    );

    _loadProfile();
  }

  // NEW:
  // Open Saved Words from the Profile screen.
  Future<void> _openSavedWords() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SavedScreen(),
      ),
    );

    // Refresh the count after coming back.
    _loadProfile();
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Sign out',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _deleteAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Delete all data',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This will permanently erase everything. This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirestoreService.deleteAllData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All data deleted.'),
            ),
          );

          _loadProfile();
        }
      } catch (e) {
        debugPrint('Delete all data error: $e');
      }
    }
  }

  String get _levelLabel {
    if (_level < 5) return 'Beginner';
    if (_level < 10) return 'Elementary';
    if (_level < 15) return 'Intermediate';
    if (_level < 20) return 'Advanced';
    return 'Expert';
  }

  int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  TimeOfDay _parseTimeOfDay(dynamic value, TimeOfDay fallback) {
    final text = value?.toString() ?? '';
    final parts = text.split(':');
    if (parts.length != 2) return fallback;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return fallback;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _parseFrequency(dynamic value) {
    final text = value?.toString().toLowerCase();
    if (text == 'monthly') return 'monthly';
    return 'weekly';
  }

  String _timeString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  Future<void> _selectWordGoal() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: ThemeProvider.isDark(context)
          ? const Color(0xFF1A1A2E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final dark = ThemeProvider.isDark(ctx);
        const goals = [5, 10, 15, 20, 30];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Daily word goal',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how many new words you want to learn each day.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textSecondary(dark), fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...goals.map(
                  (goal) => ListTile(
                    title: Text(
                      '$goal words / day',
                      style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: _wordGoal == goal
                        ? const Icon(Icons.check_rounded, color: AppColors.cyan)
                        : null,
                    onTap: () => Navigator.pop(ctx, goal),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    setState(() => _wordGoal = selected);
    try {
      // words_goal is the canonical field used by HomeScreen.
      // daily_word_goal is also written for compatibility with older data.
      await FirestoreService.updateProfile({
        'words_goal': selected,
        'daily_word_goal': selected,
      });
    } catch (e) {
      debugPrint('daily_word_goal: $e');
    }
  }

  Future<void> _selectDailyReminder() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _dailyReminderTime,
      helpText: 'Select daily reminder time',
    );

    if (selected == null || !mounted) return;

    setState(() => _dailyReminderTime = selected);
    try {
      await FirestoreService.updateProfile({
        'daily_reminder_time': _timeString(selected),
      });
    } catch (e) {
      debugPrint('daily_reminder_time: $e');
    }
  }

  Future<void> _selectReviewReminder() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: ThemeProvider.isDark(context)
          ? const Color(0xFF1A1A2E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final dark = ThemeProvider.isDark(ctx);
        const frequencies = <String, String>{
          'weekly': 'Weekly',
          'monthly': 'Monthly',
        };

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Review reminders',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                ...frequencies.entries.map(
                  (entry) => ListTile(
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: _reviewReminderFrequency == entry.key
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.cyan,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, entry.key),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    setState(() {
      _reviewReminderFrequency = selected;
    });

    try {
      await FirestoreService.updateProfile({
        'review_reminder_frequency': selected,
      });
    } catch (e) {
      debugPrint('review reminder settings: $e');
    }
  }

  List<int> get _levelCircles {
    final start = ((_level - 1) ~/ 7) * 7 + 1;

    return List.generate(
      7,
      (i) => start + i,
    );
  }

  void _openFeedback() {
    final dark = ThemeProvider.isDark(context);
    final messageCtrl = TextEditingController();
    String type = 'feedback';
    bool submitting = false;
    String? error;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card(dark),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> submit() async {
              if (messageCtrl.text.trim().isEmpty) {
                setSheetState(() => error = 'Please write a message first.');
                return;
              }

              setSheetState(() {
                submitting = true;
                error = null;
              });

              try {
                await FirestoreService.submitFeedback(
                  message: messageCtrl.text,
                  type: type,
                );

                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext);
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Thanks! Your message was sent.'),
                    ),
                  );
                }
              } catch (e) {
                setSheetState(() {
                  submitting = false;
                  error = 'Could not send this right now. Try again.';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                22,
                18,
                22,
                24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border(dark),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Help & feedback',
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Feedback'),
                          selected: type == 'feedback',
                          onSelected: (_) =>
                              setSheetState(() => type = 'feedback'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Report a problem'),
                          selected: type == 'bug',
                          onSelected: (_) => setSheetState(() => type = 'bug'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: messageCtrl,
                    maxLines: 5,
                    style: TextStyle(color: AppColors.textPrimary(dark)),
                    decoration: InputDecoration(
                      hintText: type == 'bug'
                          ? 'What went wrong?'
                          : 'What can we do better?',
                      hintStyle:
                          TextStyle(color: AppColors.textSecondary(dark)),
                      filled: true,
                      fillColor: AppColors.secondary(dark),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: submitting ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Send',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSubscription() async {
    await showPremiumPaywall(context);
    await _loadProfile();
  }

  String get _subscriptionSubtitle {
    final expiresAt = _premiumExpiresAt;

    if (!_isPremium || expiresAt == null) {
      return 'Free plan · Upgrade to Premium';
    }

    return 'Premium · renews ${expiresAt.month}/${expiresAt.day}/${expiresAt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg(dark),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.cyan,
          ),
        ),
      );
    }

    final xpProgress = _xpToNext == 0 ? 0.0 : _totalXp / _xpToNext;

    final xpLeft = _xpToNext - _totalXp;

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _openSearch,
                    icon: Icon(
                      Icons.search_rounded,
                      color: AppColors.textPrimary(dark),
                    ),
                  ),
                  IconButton(
                    onPressed: _openEdit,
                    icon: Icon(
                      Icons.edit_outlined,
                      color: AppColors.textPrimary(dark),
                    ),
                  ),
                ],
              ),

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
                            color: AppColors.cyan.withValues(
                              alpha: 0.2,
                            ),
                            border: Border.all(
                              color: AppColors.cyan,
                              width: 2.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _name.isNotEmpty ? _name[0].toUpperCase() : 'U',
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
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
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB300),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Lv $_level',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _name.isNotEmpty ? _name : 'User',
                      style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _openFriendsList,
                      child: Text(
                        '$_friends Friends',
                        style: TextStyle(
                          color: AppColors.textSecondary(dark),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: AppColors.border(dark),
                    ),
                    bottom: BorderSide(
                      color: AppColors.border(dark),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _StatItem(
                      value: '$_tokens',
                      label: 'Tokens',
                      dark: dark,
                    ),
                    _Divider(dark: dark),
                    _StatItem(
                      value: '$_level',
                      label: 'Level',
                      dark: dark,
                    ),
                    _Divider(dark: dark),
                    _StatItem(
                      value: '$_totalXp',
                      label: 'Total XP',
                      dark: dark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level $_level – $_levelLabel',
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '$_totalXp / $_xpToNext XP',
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: xpProgress.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.secondary(dark),
                  valueColor: const AlwaysStoppedAnimation(
                    Color(0xFFFFB300),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              Text(
                '${xpLeft < 0 ? 0 : xpLeft} XP to level ${_level + 1}',
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Level',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _levelCircles.map((lvl) {
                  final isCurrent = lvl == _level;
                  final isPast = lvl < _level;

                  return Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCurrent
                          ? AppColors.cyan
                          : isPast
                              ? AppColors.cyan.withValues(
                                  alpha: 0.15,
                                )
                              : Colors.transparent,
                      border: Border.all(
                        color: isCurrent || isPast
                            ? AppColors.cyan
                            : AppColors.border(dark),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$lvl',
                        style: TextStyle(
                          color: isCurrent
                              ? Colors.black
                              : isPast
                                  ? AppColors.cyan
                                  : AppColors.textSecondary(dark),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),

              Divider(
                color: AppColors.border(dark),
              ),

              const SizedBox(height: 8),

              Text(
                'LEARNING',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              // FIXED: This row is now clickable.
              _SettingsRow(
                iconBg: const Color(0xFF0D3A1A),
                iconColor: const Color(0xFF4CAF50),
                icon: Icons.save_rounded,
                title: 'Saved words',
                subtitle: '$_wordsSaved words',
                dark: dark,
                onTap: _openSavedWords,
              ),

              _SettingsRow(
                iconBg: const Color(0xFF3A2D00),
                iconColor: const Color(0xFFFFB300),
                icon: Icons.star_rounded,
                title: 'Daily word goal',
                subtitle: '$_wordGoal words / day',
                dark: dark,
                onTap: _selectWordGoal,
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
                  activeThumbColor: AppColors.cyan,
                  onChanged: (v) async {
                    setState(() => _autoTts = v);

                    try {
                      await FirestoreService.updateProfile({
                        'auto_tts': v,
                      });
                    } catch (e) {
                      debugPrint(
                        'auto_tts: $e',
                      );
                    }
                  },
                ),
              ),

              const SizedBox(height: 8),

              Divider(
                color: AppColors.border(dark),
              ),

              const SizedBox(height: 8),

              Text(
                'APP',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              _SettingsRow(
                iconBg: const Color(0xFF162A3A),
                iconColor: AppColors.cyan,
                icon: Icons.workspace_premium_rounded,
                title: 'Subscription',
                subtitle: _subscriptionSubtitle,
                dark: dark,
                onTap: _openSubscription,
              ),

              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.dark_mode_rounded,
                title: 'Dark mode',
                subtitle: 'Always on',
                dark: dark,
                trailing: Switch(
                  value: dark,
                  activeThumbColor: AppColors.cyan,
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
                onTap: _openFeedback,
              ),

              _SettingsRow(
                iconBg: AppColors.secondary(dark),
                iconColor: AppColors.textSecondary(dark),
                icon: Icons.info_outline_rounded,
                title: 'App version',
                subtitle: 'Hololingo v1.0.0',
                dark: dark,
                trailing: Text(
                  'Latest',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 12,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Divider(
                color: AppColors.border(dark),
              ),

              const SizedBox(height: 8),

              Text(
                'NOTIFICATIONS',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              _SettingsRow(
                iconBg: const Color(0xFF3A2D00),
                iconColor: const Color(0xFFFFB300),
                icon: Icons.notifications_rounded,
                title: 'Daily reminder',
                subtitle: _dailyReminder
                    ? '${_formatTime(_dailyReminderTime)} every day'
                    : 'Off',
                dark: dark,
                onTap: _selectDailyReminder,
                trailing: Switch(
                  value: _dailyReminder,
                  activeThumbColor: AppColors.cyan,
                  onChanged: (v) async {
                    setState(() => _dailyReminder = v);
                    try {
                      await FirestoreService.updateProfile({
                        'daily_reminder': v,
                      });
                    } catch (e) {
                      debugPrint('$e');
                    }
                  },
                ),
              ),

              _SettingsRow(
                iconBg: const Color(0xFF0D3A1A),
                iconColor: const Color(0xFF4CAF50),
                icon: Icons.refresh_rounded,
                title: 'Review reminders',
                subtitle: _reviewReminder
                    ? _reviewReminderFrequency[0].toUpperCase() +
                        _reviewReminderFrequency.substring(1)
                    : 'Off',
                dark: dark,
                onTap: _selectReviewReminder,
                trailing: Switch(
                  value: _reviewReminder,
                  activeThumbColor: AppColors.cyan,
                  onChanged: (v) async {
                    setState(() => _reviewReminder = v);
                    try {
                      await FirestoreService.updateProfile({
                        'review_reminder': v,
                      });
                    } catch (e) {
                      debugPrint('$e');
                    }
                  },
                ),
              ),

              const SizedBox(height: 24),

              GestureDetector(
                onTap: _deleteAllData,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delete all data',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Permanently erase everything',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _signOut,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Sign out',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final bool dark;
  final VoidCallback? onTap;

  const _StatItem({
    required this.value,
    required this.label,
    required this.dark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool dark;

  const _Divider({
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.border(dark),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool dark;
  final Widget? trailing;

  // IMPORTANT:
  // This was the reason your Saved words row could not be clicked.
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
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary(dark),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary(dark),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
