import 'dart:async';

import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'saved_screen.dart';
import 'main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _recentWords = [];

  bool _loading = true;

  String _name = '';

  int _wordsToday = 0;
  int _wordGoal = 10;
  int _totalXp = 0;

  static const int _xpThisWeek = 120;

  // ─────────────────────────────────────────
  // LIVE PROFILE STREAM
  // ─────────────────────────────────────────
  //
  // IMPORTANT:
  // The bottom nav keeps every tab alive (IndexedStack), so this screen's
  // initState only ever runs once. A one-time fetch in initState would
  // never notice changes made later in ProfileScreen (daily word goal,
  // etc), so instead of just fetching once we keep a live Firestore
  // stream and read from it directly in build(). The one-time fields
  // above are still used as the initial value/fallback until the first
  // stream event arrives.
  Stream<Map<String, dynamic>>? _profileStream;

  // ─────────────────────────────────────────
  // EVENT
  // ─────────────────────────────────────────

  Map<String, dynamic>? _event;

  bool _eventNotifyOn = false;
  bool _eventLoading = true;

  Timer? _eventTimer;

  @override
  void initState() {
    super.initState();

    _profileStream = DatabaseService.watchProfile();

    _loadProfile();
    _loadRecent();
    _loadEvent();

    // Check event status periodically so the card
    // disappears automatically when the event starts.
    _eventTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        _checkEventStatus();
      },
    );
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // GREETING
  // ─────────────────────────────────────────

  String _getGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 5 && hour < 12) {
      return 'Good morning,';
    }

    if (hour >= 12 && hour < 17) {
      return 'Good afternoon,';
    }

    if (hour >= 17 && hour < 21) {
      return 'Good evening,';
    }

    return 'Good night,';
  }

  // ─────────────────────────────────────────
  // LOAD PROFILE
  // ─────────────────────────────────────────

  Future<void> _loadProfile() async {
    try {
      final data = await DatabaseService.getProfileOrDefault();

      if (!mounted) return;

      setState(() {
        _name = data['name']?.toString() ?? '';

        _totalXp = (data['total_xp'] as num?)?.toInt() ?? 0;

        _wordGoal = (data['words_goal'] as num?)?.toInt() ?? 10;

        _wordsToday = (data['words_today'] as num?)?.toInt() ?? 0;
      });

      _syncNotifyState(data);
    } catch (e) {
      debugPrint('HomeScreen profile error: $e');
    }
  }

  // ─────────────────────────────────────────
  // LOAD RECENT WORDS
  // ─────────────────────────────────────────

  Future<void> _loadRecent() async {
    try {
      final words = await DatabaseService.getSavedWords();

      if (!mounted) return;

      setState(() {
        _recentWords = words.take(5).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('HomeScreen recent error: $e');

      if (!mounted) return;

      setState(() {
        _recentWords = [];
        _loading = false;
      });
    }
  }

  // ─────────────────────────────────────────
  // LOAD EVENT
  // ─────────────────────────────────────────

  Future<void> _loadEvent() async {
    try {
      final event = await DatabaseService.getCurrentEvent();

      debugPrint('HOME EVENT DEBUG: $event');

      if (!mounted) return;

      setState(() {
        _event = event;
        _eventLoading = false;
      });

      if (event != null) {
        final profile = await DatabaseService.getProfileOrDefault();

        if (!mounted) return;

        _syncNotifyState(profile);
      }
    } catch (e) {
      debugPrint('HomeScreen event error: $e');

      if (!mounted) return;

      setState(() {
        _event = null;
        _eventLoading = false;
      });
    }
  }

  // ─────────────────────────────────────────
  // CHECK EVENT STATUS
  // ─────────────────────────────────────────

  Future<void> _checkEventStatus() async {
    if (!mounted) return;

    // Refresh the event from Firestore.
    //
    // The important part is that the UI below checks
    // start_at and only displays the card while the
    // event is still upcoming.
    await _loadEvent();
  }

  // ─────────────────────────────────────────
  // EVENT START TIME
  // ─────────────────────────────────────────

  DateTime? _getEventStart() {
    if (_event == null) return null;

    final timestamp = _event!['start_at'];

    if (timestamp == null) {
      // Compatibility with the old `date` field.
      final oldDate = _event!['date'];

      if (oldDate == null) {
        return null;
      }

      try {
        return (oldDate as dynamic).toDate();
      } catch (_) {
        return DateTime.tryParse(
          oldDate.toString(),
        );
      }
    }

    try {
      return (timestamp as dynamic).toDate();
    } catch (_) {
      return DateTime.tryParse(
        timestamp.toString(),
      );
    }
  }

  // ─────────────────────────────────────────
  // EVENT END TIME
  // ─────────────────────────────────────────

  DateTime? _getEventEnd() {
    if (_event == null) return null;

    final timestamp = _event!['end_at'];

    if (timestamp == null) {
      return null;
    }

    try {
      return (timestamp as dynamic).toDate();
    } catch (_) {
      return DateTime.tryParse(
        timestamp.toString(),
      );
    }
  }

  // ─────────────────────────────────────────
  // IS UPCOMING?
  // ─────────────────────────────────────────

  bool _isEventUpcoming() {
    final start = _getEventStart();

    if (start == null) {
      return false;
    }

    final now = DateTime.now();

    return now.isBefore(start);
  }

  // ─────────────────────────────────────────
  // IS LIVE?
  // ─────────────────────────────────────────

  bool _isEventLive() {
    final start = _getEventStart();
    final end = _getEventEnd();

    if (start == null) {
      return false;
    }

    final now = DateTime.now();

    if (end == null) {
      return !now.isBefore(start);
    }

    return !now.isBefore(start) && now.isBefore(end);
  }

  // ─────────────────────────────────────────
  // EVENT NOTIFICATION
  // ─────────────────────────────────────────

  void _syncNotifyState(
    Map<String, dynamic> profile,
  ) {
    if (!mounted || _event == null) {
      return;
    }

    final eventName = _event!['name']?.toString() ?? '';

    setState(() {
      _eventNotifyOn = DatabaseService.isNotifiedForEvent(
        profile,
        eventName,
      );
    });
  }

  Future<void> _toggleEventNotify() async {
    if (_event == null) {
      return;
    }

    // Don't allow notification interaction
    // once the event is already live.
    if (!_isEventUpcoming()) {
      return;
    }

    final eventName = _event!['name']?.toString() ?? '';

    final newValue = !_eventNotifyOn;

    setState(() {
      _eventNotifyOn = newValue;
    });

    try {
      await DatabaseService.setEventNotify(
        eventName,
        newValue,
      );
    } catch (e) {
      debugPrint(
        'event_notify update error: $e',
      );

      if (!mounted) return;

      setState(() {
        _eventNotifyOn = !newValue;
      });
    }
  }

  // ─────────────────────────────────────────
  // EVENT DATE
  // ─────────────────────────────────────────

  String _formatEventDate(
    DateTime? d,
  ) {
    if (d == null) {
      return '';
    }

    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.day)}.'
        '${two(d.month)}.'
        '${d.year} '
        '${two(d.hour)}:'
        '${two(d.minute)}';
  }

  // ─────────────────────────────────────────
  // EVENT COUNTDOWN TEXT
  // ─────────────────────────────────────────

  String _eventStartsText() {
    final start = _getEventStart();

    if (start == null) {
      return '';
    }

    final difference = start.difference(DateTime.now());

    if (difference.isNegative) {
      return '';
    }

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    if (days > 0) {
      return 'Starts in ${days}d ${hours}h';
    }

    if (hours > 0) {
      return 'Starts in ${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return 'Starts in ${minutes}m';
    }

    return 'Starting soon';
  }

  // ─────────────────────────────────────────
  // THAI TRANSLATIONS
  // ─────────────────────────────────────────

  String _translation(
    String word,
  ) {
    const map = {
      'book': 'หนังสือ',
      'desk': 'โต๊ะ',
      'cup': 'ถ้วย',
      'chair': 'เก้าอี้',
      'phone': 'โทรศัพท์',
      'cell phone': 'โทรศัพท์มือถือ',
      'tablet': 'แท็บเล็ต',
      'laptop': 'แล็ปท็อป',
      'pen': 'ปากกา',
      'pencil': 'ดินสอ',
      'suitcase': 'กระเป๋าเดินทาง',
      'bag': 'กระเป๋า',
      'backpack': 'กระเป๋าเป้',
      'keyboard': 'แป้นพิมพ์',
      'mouse': 'เมาส์',
      'monitor': 'จอภาพ',
      'lamp': 'โคมไฟ',
      'shoe': 'รองเท้า',
      'umbrella': 'ร่ม',
      'bottle': 'ขวด',
      'bowl': 'ชาม',
      'clock': 'นาฬิกา',
      'bed': 'เตียง',
      'table': 'โต๊ะ',
      'car': 'รถยนต์',
      'dog': 'สุนัข',
      'cat': 'แมว',
      'bird': 'นก',
    };

    return map[word.toLowerCase()] ?? '';
  }

  // ─────────────────────────────────────────
  // TIME
  // ─────────────────────────────────────────

  String _getRecentTime(
    Map<String, dynamic> word,
    int index,
  ) {
    final createdAt = word['created_at'];

    if (createdAt != null) {
      try {
        final date = (createdAt as dynamic).toDate();

        final difference = DateTime.now().difference(date);

        if (difference.inMinutes < 1) {
          return 'Just now';
        }

        if (difference.inMinutes < 60) {
          return '${difference.inMinutes} min ago';
        }

        if (difference.inHours < 24) {
          return '${difference.inHours} hr ago';
        }

        if (difference.inDays == 1) {
          return 'Yesterday';
        }

        if (difference.inDays < 7) {
          return '${difference.inDays} days ago';
        }
      } catch (_) {}
    }

    const fallback = [
      'Recently',
      'Recently',
      'Yesterday',
      '2 days ago',
      '3 days ago',
    ];

    return fallback[index % fallback.length];
  }

  // ─────────────────────────────────────────
  // STATUS
  // ─────────────────────────────────────────

  String _getStatus(
    Map<String, dynamic> word,
  ) {
    final status = word['status']?.toString();

    if (status == 'review' || status == 'Review') {
      return 'Review';
    }

    return 'Saved';
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────

  @override
  Widget build(
    BuildContext context,
  ) {
    final dark = ThemeProvider.isDark(context);

    final eventName = _event?['name']?.toString();

    final eventStart = _getEventStart();

    // IMPORTANT:
    //
    // Home only shows the event notification
    // while the event is UPCOMING.
    //
    // If the event is LIVE -> hidden.
    // If the event has ENDED -> hidden.
    final showEventNotification = !_eventLoading &&
        _event != null &&
        eventName != null &&
        eventName.isNotEmpty &&
        _isEventUpcoming();

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            0,
            20,
            16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 20,
              ),

              // ───────────────────────
              // HEADER (LIVE)
              // ───────────────────────
              //
              // Wrapped in a StreamBuilder so the greeting name, and the
              // stats block below, update immediately when the profile
              // document changes (e.g. right after editing settings in
              // ProfileScreen) instead of only on the very first load.

              StreamBuilder<Map<String, dynamic>>(
                stream: _profileStream,
                builder: (context, snapshot) {
                  final profile = snapshot.data;

                  final liveName = profile != null &&
                          (profile['name']?.toString() ?? '').isNotEmpty
                      ? profile['name'].toString()
                      : _name;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              color: AppColors.textSecondary(
                                dark,
                              ),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            liveName.isNotEmpty ? liveName : 'there',
                            style: TextStyle(
                              color: AppColors.textPrimary(
                                dark,
                              ),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // GOBOT
                      GestureDetector(
                        onTap: () => TabSwitcher.of(context)?.switchTab(
                          5,
                        ),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.cyan,
                              width: 2,
                            ),
                            color: AppColors.card(
                              dark,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              liveName.isNotEmpty
                                  ? liveName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.cyan,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(
                height: 22,
              ),

              // ───────────────────────
              // STATS (LIVE)
              // ───────────────────────
              //
              // Same reasoning as the header above: "Words today" and
              // "Total XP" (and the daily word goal denominator) must
              // reflect the latest Firestore values right away, so this
              // is driven by the same live stream rather than the
              // one-time _wordsToday/_wordGoal/_totalXp fields.

              StreamBuilder<Map<String, dynamic>>(
                stream: _profileStream,
                builder: (context, snapshot) {
                  final profile = snapshot.data;

                  final liveWordsToday = profile != null
                      ? (profile['words_today'] as num?)?.toInt() ?? _wordsToday
                      : _wordsToday;

                  final liveWordGoal = profile != null
                      ? (profile['words_goal'] as num?)?.toInt() ?? _wordGoal
                      : _wordGoal;

                  final liveTotalXp = profile != null
                      ? (profile['total_xp'] as num?)?.toInt() ?? _totalXp
                      : _totalXp;

                  return Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(
                            16,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card(
                              dark,
                            ),
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Words today',
                                style: TextStyle(
                                  color: AppColors.textSecondary(
                                    dark,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(
                                height: 6,
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '$liveWordsToday',
                                    style: TextStyle(
                                      color: AppColors.textPrimary(
                                        dark,
                                      ),
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    ' /$liveWordGoal',
                                    style: TextStyle(
                                      color: AppColors.textSecondary(
                                        dark,
                                      ),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 8,
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  3,
                                ),
                                child: LinearProgressIndicator(
                                  value: liveWordGoal == 0
                                      ? 0
                                      : (liveWordsToday / liveWordGoal).clamp(
                                          0.0,
                                          1.0,
                                        ),
                                  backgroundColor: AppColors.bg(
                                    dark,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    AppColors.cyan,
                                  ),
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(
                            16,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.card(
                              dark,
                            ),
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total XP',
                                style: TextStyle(
                                  color: AppColors.textSecondary(
                                    dark,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(
                                height: 6,
                              ),
                              Text(
                                '$liveTotalXp',
                                style: const TextStyle(
                                  color: Color(
                                    0xFFFFD700,
                                  ),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                '+$_xpThisWeek this week',
                                style: TextStyle(
                                  color: AppColors.textSecondary(
                                    dark,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(
                height: 16,
              ),

              // ───────────────────────
              // UPCOMING EVENT
              // ───────────────────────
              //
              // IMPORTANT:
              // This card appears ONLY before
              // the event starts.
              //
              // When start_at is reached,
              // _isEventUpcoming() becomes false
              // and this entire card disappears.

              if (showEventNotification) ...[
                const SizedBox(
                  height: 16,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(
                    18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF16103A,
                    ),
                    borderRadius: BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color: const Color(
                        0xFF9C6FFF,
                      ).withOpacity(
                        0.35,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF9C6FFF,
                              ).withOpacity(
                                0.15,
                              ),
                              borderRadius: BorderRadius.circular(
                                12,
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                '🎉',
                                style: TextStyle(
                                  fontSize: 21,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'UPCOMING EVENT',
                                  style: TextStyle(
                                    color: Color(
                                      0xFFB99AFF,
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(
                                  height: 3,
                                ),
                                Text(
                                  eventName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 14,
                      ),
                      if (eventStart != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              color: Color(
                                0xFFB99AFF,
                              ),
                              size: 15,
                            ),
                            const SizedBox(
                              width: 7,
                            ),
                            Text(
                              _formatEventDate(
                                eventStart,
                              ),
                              style: TextStyle(
                                color: AppColors.textSecondary(
                                  true,
                                ),
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _eventStartsText(),
                              style: const TextStyle(
                                color: Color(
                                  0xFFB99AFF,
                                ),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(
                        height: 14,
                      ),
                      GestureDetector(
                        onTap: _toggleEventNotify,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _eventNotifyOn
                                ? AppColors.cyan
                                : const Color(
                                    0xFF9C6FFF,
                                  ),
                            borderRadius: BorderRadius.circular(
                              12,
                            ),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _eventNotifyOn
                                      ? Icons.notifications_active
                                      : Icons.notifications_none,
                                  color: Colors.white,
                                  size: 17,
                                ),
                                const SizedBox(
                                  width: 7,
                                ),
                                Text(
                                  _eventNotifyOn
                                      ? "You'll be notified"
                                      : 'Notify Me',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(
                height: 22,
              ),

              // ───────────────────────
              // RECENTLY SCANNED
              // ───────────────────────

              Row(
                children: [
                  Text(
                    'RECENTLY SCANNED',
                    style: TextStyle(
                      color: AppColors.textSecondary(
                        dark,
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SavedScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'See all',
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              if (_loading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.cyan,
                  ),
                )
              else if (_recentWords.isEmpty)
                _EmptyRecent(
                  dark: dark,
                )
              else
                ..._recentWords.asMap().entries.map(
                  (entry) {
                    final index = entry.key;

                    final word = entry.value;

                    final name = word['word']?.toString() ?? '';

                    final translation = _translation(
                      name,
                    );

                    final time = _getRecentTime(
                      word,
                      index,
                    );

                    final status = _getStatus(
                      word,
                    );

                    return _RecentWordTile(
                      word: name,
                      translation: translation,
                      time: time,
                      status: status,
                      dark: dark,
                    );
                  },
                ),

              const SizedBox(
                height: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// RECENT WORD TILE
// ─────────────────────────────────────────────

class _RecentWordTile extends StatelessWidget {
  final String word;
  final String translation;
  final String time;
  final String status;
  final bool dark;

  const _RecentWordTile({
    required this.word,
    required this.translation,
    required this.time,
    required this.status,
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    final isReview = status == 'Review';

    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(
          14,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word,
                  style: TextStyle(
                    color: AppColors.textPrimary(
                      dark,
                    ),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '${translation.isNotEmpty ? '$translation · ' : ''}$time',
                  style: TextStyle(
                    color: AppColors.textSecondary(
                      dark,
                    ),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: isReview
                  ? Colors.redAccent.withOpacity(
                      0.15,
                    )
                  : AppColors.cyan.withOpacity(
                      0.12,
                    ),
              borderRadius: BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color: isReview
                    ? Colors.redAccent.withOpacity(
                        0.5,
                      )
                    : AppColors.cyan.withOpacity(
                        0.4,
                      ),
                width: 1,
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: isReview ? Colors.redAccent : AppColors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// EMPTY RECENT
// ─────────────────────────────────────────────

class _EmptyRecent extends StatelessWidget {
  final bool dark;

  const _EmptyRecent({
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(
        24,
      ),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(
          14,
        ),
      ),
      child: Center(
        child: Text(
          'Scan objects to see them here',
          style: TextStyle(
            color: AppColors.textSecondary(
              dark,
            ),
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
