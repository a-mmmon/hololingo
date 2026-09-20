import 'dart:async';

import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'saved_screen.dart';
import 'main.dart';
import 'daily_battle_service.dart';
import 'daily_challenge_queue_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ─────────────────────────────────────────
  // LIVE WORD STREAMS
  // ─────────────────────────────────────────
  //
  // Same reasoning as _profileStream below: the bottom nav's IndexedStack
  // keeps this screen's State alive forever after the first build, so a
  // one-time Future fetch here would never notice a scan or save made
  // afterward. Live streams keep these sections current regardless.
  Stream<List<Map<String, dynamic>>>? _savedWordsStream;
  Stream<List<Map<String, dynamic>>>? _recentScansStream;
  Stream<List<Map<String, dynamic>>>? _popularWordsStream;

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
    _savedWordsStream = DatabaseService.watchSavedWords(limit: 5);
    _recentScansStream = DatabaseService.watchRecentScans(limit: 5);
    _popularWordsStream = DatabaseService.watchPopularWords(limit: 8);

    _loadProfile();
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

        final eventId = _currentEventId;
        if (eventId != null) {
          unawaited(DailyBattleService.checkAndCrownChampionIfEnded(eventId));
        }
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

  String? get _currentEventId {
    final event = _event;
    if (event == null) return null;

    final eventName = event['name']?.toString().trim() ?? '';
    if (eventName.isEmpty) return null;

    final rawEventId = event['event_id']?.toString().trim();
    return (rawEventId != null && rawEventId.isNotEmpty)
        ? rawEventId
        : FirestoreService.eventIdFromName(eventName);
  }

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
              // POPULAR WORDS OF THE WEEK (banner)
              // ───────────────────────

              Text(
                'POPULAR WORDS OF THE WEEK',
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _popularWordsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.cyan,
                      ),
                    );
                  }

                  final words = snapshot.data ?? [];

                  if (words.isEmpty) {
                    return _EmptyRecent(dark: dark);
                  }

                  return _PopularWordsBanner(
                    words: words,
                    dark: dark,
                  );
                },
              ),

              const SizedBox(
                height: 20,
              ),

              if (_isEventLive() && _currentEventId != null) ...[
                const SizedBox(height: 12),
                _DailyChallengeBanner(eventId: _currentEventId!, dark: dark),
              ],

              StreamBuilder<Map<String, dynamic>?>(
                stream: DailyBattleService.watchLastChampion(),
                builder: (context, snapshot) {
                  final champion = snapshot.data;
                  if (champion == null) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ChampionBanner(champion: champion, dark: dark),
                  );
                },
              ),

              const SizedBox(
                height: 20,
              ),

              // ───────────────────────
              // RECENTLY SAVED
              // ───────────────────────

              Row(
                children: [
                  Text(
                    'RECENTLY SAVED',
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

              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _savedWordsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.cyan,
                      ),
                    );
                  }

                  final savedWords = snapshot.data ?? [];

                  if (savedWords.isEmpty) {
                    return _EmptyRecent(dark: dark);
                  }

                  return Column(
                    children: savedWords.asMap().entries.map(
                      (entry) {
                        final index = entry.key;
                        final word = entry.value;
                        final name = word['word']?.toString() ?? '';

                        return _RecentWordTile(
                          word: name,
                          translation: _translation(name),
                          time: _getRecentTime(word, index),
                          status: _getStatus(word),
                          dark: dark,
                        );
                      },
                    ).toList(),
                  );
                },
              ),

              const SizedBox(
                height: 20,
              ),

              // ───────────────────────
              // RECENTLY SCANNED
              // ───────────────────────
              //
              // Distinct from "Recently Saved" above: this shows every
              // scan (scan_history), whether or not the user chose to save
              // it, with its own Save button per row.

              Text(
                'RECENTLY SCANNED',
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _savedWordsStream,
                builder: (context, savedSnapshot) {
                  final savedWordSet = (savedSnapshot.data ?? [])
                      .map((w) => w['word']?.toString() ?? '')
                      .toSet();

                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _recentScansStream,
                    builder: (context, scanSnapshot) {
                      if (scanSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          !scanSnapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.cyan,
                          ),
                        );
                      }

                      final scans = scanSnapshot.data ?? [];

                      if (scans.isEmpty) {
                        return _EmptyRecent(dark: dark);
                      }

                      return Column(
                        children: scans.map(
                          (scan) {
                            final name = scan['word']?.toString() ?? '';

                            return _ScannedWordTile(
                              word: name,
                              translation: _translation(name),
                              definition:
                                  scan['definition']?.toString() ?? '',
                              phonetic: scan['phonetic']?.toString() ?? '',
                              alreadySaved: savedWordSet.contains(name),
                              dark: dark,
                            );
                          },
                        ).toList(),
                      );
                    },
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
// DAILY CHALLENGE BANNER
// ─────────────────────────────────────────────
//
// Only shown while an event is live; checks whether the admin has set
// up today's 10 words before offering the button, so tapping it never
// leads to an empty challenge.

class _DailyChallengeBanner extends StatefulWidget {
  final String eventId;
  final bool dark;

  const _DailyChallengeBanner({required this.eventId, required this.dark});

  @override
  State<_DailyChallengeBanner> createState() => _DailyChallengeBannerState();
}

class _DailyChallengeBannerState extends State<_DailyChallengeBanner> {
  bool _loading = true;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final available = await DailyBattleService.hasTodaysChallenge(widget.eventId);
    if (!mounted) return;
    setState(() {
      _available = available;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_available) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DailyChallengeQueueScreen(eventId: widget.eventId),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF7C4DFF).withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.flash_on_rounded, color: Color(0xFF7C4DFF), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Challenge',
                    style: TextStyle(
                      color: AppColors.textPrimary(widget.dark),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Wager ${DailyBattleService.wager} coins — beat another player today',
                    style: TextStyle(
                      color: AppColors.textSecondary(widget.dark),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF7C4DFF)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CHAMPION BANNER
// ─────────────────────────────────────────────
//
// Shown to every user once an event has ended and someone's been
// crowned — stays until the next event's champion replaces it.

class _ChampionBanner extends StatelessWidget {
  final Map<String, dynamic> champion;
  final bool dark;

  const _ChampionBanner({required this.champion, required this.dark});

  @override
  Widget build(BuildContext context) {
    final name = champion['name']?.toString() ?? 'A player';
    final eventName = champion['event_name']?.toString() ?? 'the last event';
    final wins = champion['wins']?.toString() ?? '0';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300).withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB300), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name won $eventName!',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$wins Daily Challenge wins',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 12,
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

// ─────────────────────────────────────────────
// POPULAR WORDS BANNER
// ─────────────────────────────────────────────
//
// Single scrollable row of pills, one per popular word, instead of a
// vertical list — this is a "what's trending" glance, not something you
// read line by line.

class _PopularWordsBanner extends StatelessWidget {
  final List<Map<String, dynamic>> words;
  final bool dark;

  const _PopularWordsBanner({
    required this.words,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: words.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final word = words[index]['word']?.toString() ?? '';

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.cyan.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppColors.cyan,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  word,
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// SCANNED WORD TILE (with inline Save button)
// ─────────────────────────────────────────────
//
// Scanning a word records it to scan_history regardless of whether the
// user saves it — this tile is how they can save it after the fact,
// straight from the Home feed, without reopening the AR/scan flow.

class _ScannedWordTile extends StatefulWidget {
  final String word;
  final String translation;
  final String definition;
  final String phonetic;
  final bool alreadySaved;
  final bool dark;

  const _ScannedWordTile({
    required this.word,
    required this.translation,
    required this.definition,
    required this.phonetic,
    required this.alreadySaved,
    required this.dark,
  });

  @override
  State<_ScannedWordTile> createState() => _ScannedWordTileState();
}

class _ScannedWordTileState extends State<_ScannedWordTile> {
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || widget.alreadySaved) return;

    setState(() {
      _saving = true;
    });

    try {
      await FirestoreService.saveWord({
        'word': widget.word,
        'definition': widget.definition,
        'phonetic': widget.phonetic,
      });
    } catch (e) {
      debugPrint('HomeScreen save-from-scan error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.word,
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.translation.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.translation,
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: widget.alreadySaved ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: widget.alreadySaved
                    ? Colors.transparent
                    : AppColors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.alreadySaved
                      ? AppColors.border(dark)
                      : AppColors.cyan.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.cyan,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.alreadySaved
                              ? Icons.check_rounded
                              : Icons.bookmark_border_rounded,
                          size: 15,
                          color: widget.alreadySaved
                              ? AppColors.textSecondary(dark)
                              : AppColors.cyan,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          widget.alreadySaved ? 'Saved' : 'Save',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: widget.alreadySaved
                                ? AppColors.textSecondary(dark)
                                : AppColors.cyan,
                          ),
                        ),
                      ],
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
