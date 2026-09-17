import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'premium_paywall.dart';
import 'premium_status.dart';
import 'topics_data.dart';
import 'topic_word_grid_screen.dart';
import 'event_group_lobby_screen.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  int _level = 1;
  int _xp = 0;
  int _xpToNextLevel = 3000;

  bool _loading = true;
  bool _notifyLoading = false;
  bool _isPremiumUser = false;

  Map<String, dynamic> _progress = {};

  Map<String, dynamic>? _currentEvent;

  bool _eventNotifyOn = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _loadAll() async {
    try {
      final profile = await FirestoreService.getProfileOrDefault();

      final progress = await FirestoreService.getTopicProgress();

      final event = await FirestoreService.getCurrentEvent();

      bool notifyOn = false;

      if (event != null) {
        final eventId = event['event_id']?.toString().trim() ?? '';

        final eventName = event['name']?.toString().trim() ?? '';

        final notificationKey = eventId.isNotEmpty ? eventId : eventName;

        if (notificationKey.isNotEmpty) {
          notifyOn = FirestoreService.isNotifiedForEvent(
            profile,
            notificationKey,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _level = _toInt(
          profile['level'],
          1,
        );

        _xp = _toInt(
          profile['total_xp'],
          0,
        );

        _progress = progress;

        _currentEvent = event;

        _eventNotifyOn = notifyOn;

        _isPremiumUser = isSubscriptionActive(profile);

        _loading = false;
      });

      debugPrint(
        'TopicsScreen event = $_currentEvent',
      );
    } catch (e) {
      debugPrint(
        'TopicsScreen load error: $e',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  int _toInt(
    dynamic value,
    int fallback,
  ) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        fallback;
  }

  // ============================================================
  // EVENT
  // ============================================================

  DateTime? _readEventDate(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    try {
      final converted = value.toDate();

      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {}

    return DateTime.tryParse(
      value.toString(),
    );
  }

  DateTime? get _eventStart {
    return _readEventDate(
      _currentEvent?['start_at'],
    );
  }

  DateTime? get _eventEnd {
    return _readEventDate(
      _currentEvent?['end_at'],
    );
  }

  bool get _eventIsConfigured {
    if (_currentEvent == null) {
      return false;
    }

    return _currentEvent!['active'] == true;
  }

  bool get _eventIsLive {
    if (!_eventIsConfigured) {
      return false;
    }

    final start = _eventStart;
    final end = _eventEnd;

    if (start == null || end == null) {
      return false;
    }

    final now = DateTime.now();

    return !now.isBefore(start) && now.isBefore(end);
  }

  bool get _eventIsUpcoming {
    if (!_eventIsConfigured) {
      return false;
    }

    final start = _eventStart;

    if (start == null) {
      return false;
    }

    return DateTime.now().isBefore(start);
  }

  bool get _eventHasEnded {
    if (!_eventIsConfigured) {
      return false;
    }

    final end = _eventEnd;

    if (end == null) {
      return false;
    }

    return !DateTime.now().isBefore(end);
  }

  String get _eventId {
    final firebaseId = _currentEvent?['event_id']?.toString().trim();

    if (firebaseId != null && firebaseId.isNotEmpty) {
      return firebaseId;
    }

    // Fallback only if event_id is missing.
    return FirestoreService.eventIdFromName(
      _eventName,
    );
  }

  String get _eventName {
    final name = _currentEvent?['name'];

    if (name == null || name.toString().trim().isEmpty) {
      return 'Special Event';
    }

    return name.toString();
  }

  String get _eventType {
    final type = _currentEvent?['type'];

    if (type == null || type.toString().trim().isEmpty) {
      return 'special_event';
    }

    return type.toString();
  }

  String _formatDate(
    DateTime date,
  ) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  String _formatDateTime(
    DateTime date,
  ) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
            ? date.hour - 12
            : date.hour;

    final minute = date.minute.toString().padLeft(2, '0');

    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '${_formatDate(date)} '
        '$hour:$minute $period';
  }

  String get _eventDateText {
    final start = _eventStart;
    final end = _eventEnd;

    if (start == null) {
      return 'Special Event';
    }

    if (end == null) {
      return _formatDateTime(start);
    }

    return '${_formatDateTime(start)}'
        ' – '
        '${_formatDateTime(end)}';
  }

  // ============================================================
  // EVENT PARTICIPATION
  // ============================================================

  Future<void> _participateInEvent() async {
    if (!_eventIsLive || _currentEvent == null) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventGroupLobbyScreen(
          eventId: _eventId,
          eventName: _eventName,
        ),
      ),
    );

    if (mounted) {
      await _loadAll();
    }
  }

  // ============================================================
  // EVENT NOTIFICATION
  // ============================================================

  Future<void> _toggleEventNotify() async {
    if (_currentEvent == null || !_eventIsUpcoming || _notifyLoading) {
      return;
    }

    final newValue = !_eventNotifyOn;

    setState(() {
      _notifyLoading = true;
    });

    try {
      final notificationKey = _eventId.isNotEmpty ? _eventId : _eventName;

      await FirestoreService.setEventNotify(
        notificationKey,
        newValue,
      );

      if (!mounted) return;

      setState(() {
        _eventNotifyOn = newValue;
        _notifyLoading = false;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? 'You will be notified when the event starts.'
                : 'Event notification turned off.',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Event notify error: $e',
      );

      if (!mounted) return;

      setState(() {
        _notifyLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update event notification.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // TOPICS
  // ============================================================

  int _learnedCount(
    TopicDef topic,
  ) {
    final learned = (_progress[topic.id] as List?)?.cast<String>() ?? [];

    return learned.length;
  }

  bool _isComplete(
    TopicDef topic,
  ) {
    return _learnedCount(topic) >= topic.words.length;
  }

  TopicDef get _activeTopic {
    return kTopics.firstWhere(
      (t) => !_isComplete(t),
      orElse: () => kTopics.last,
    );
  }

  bool _isLocked(
    TopicDef topic,
  ) {
    if (topic.isPremium) {
      return !_isPremiumUser;
    }

    final regularTopics = kTopics.where((item) => !item.isPremium).toList();
    final index = regularTopics.indexOf(topic);
    if (index <= 0) {
      return false;
    }

    return !_isComplete(regularTopics[index - 1]);
  }

  Future<void> _openTopic(
    TopicDef topic,
  ) async {
    if (_isLocked(topic)) {
      if (topic.isPremium) {
        await showPremiumPaywall(context);
        await _loadAll();

        if (!mounted || _isLocked(topic)) {
          return;
        }
      } else {
        return;
      }
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TopicWordGridScreen(
          topic: topic,
        ),
      ),
    );

    if (result == true) {
      _loadAll();
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final dark = ThemeProvider.isDark(
      context,
    );

    final progress = _xpToNextLevel == 0
        ? 0.0
        : (_xp / _xpToNextLevel).clamp(
            0.0,
            1.0,
          );

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.cyan,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ==================================================
                  // HEADER
                  // ==================================================

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Topics',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(
                              dark,
                            ),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(
                          height: 6,
                        ),
                        Text(
                          'Level $_level · $_xp XP',
                          style: TextStyle(
                            color: AppColors.textSecondary(
                              dark,
                            ),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(
                          height: 10,
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            4,
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: AppColors.secondary(
                              dark,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.cyan,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  // ==================================================
                  // UPCOMING EVENT
                  //
                  // ONLY appears BEFORE event starts.
                  // When event starts, this disappears.
                  // ==================================================

                  if (_eventIsUpcoming)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: _UpcomingEventCard(
                        eventName: _eventName,
                        eventType: _eventType,
                        eventDate: _eventDateText,
                        dark: dark,
                        notifyOn: _eventNotifyOn,
                        loading: _notifyLoading,
                        onNotify: _toggleEventNotify,
                      ),
                    ),

                  if (_eventIsUpcoming)
                    const SizedBox(
                      height: 14,
                    ),

                  // ==================================================
                  // LIVE EVENT
                  //
                  // ONLY appears while event is running.
                  // Notification card disappears.
                  // ==================================================

                  if (_eventIsLive)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: _LiveEventCard(
                        eventName: _eventName,
                        eventType: _eventType,
                        eventDate: _eventDateText,
                        dark: dark,
                        onParticipate: _participateInEvent,
                      ),
                    ),

                  if (_eventIsLive)
                    const SizedBox(
                      height: 14,
                    ),

                  // ==================================================
                  // TOPIC MAP
                  // ==================================================

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: _TopicMap(
                        activeTopic: _activeTopic,
                        learnedCount: _learnedCount,
                        isComplete: _isComplete,
                        isLocked: _isLocked,
                        onTapTopic: _openTopic,
                        dark: dark,
                      ),
                    ),
                  ),

                  // ==================================================
                  // CONTINUE
                  // ==================================================

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      12,
                      20,
                      16,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openTopic(
                          _activeTopic,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              16,
                            ),
                          ),
                        ),
                        child: Text(
                          _learnedCount(
                                    _activeTopic,
                                  ) ==
                                  0
                              ? 'Start ${_activeTopic.name}'
                              : 'Continue ${_activeTopic.name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ================================================================
// UPCOMING EVENT CARD
// ================================================================

class _UpcomingEventCard extends StatelessWidget {
  final String eventName;
  final String eventType;
  final String eventDate;
  final bool dark;
  final bool notifyOn;
  final bool loading;
  final VoidCallback onNotify;

  const _UpcomingEventCard({
    required this.eventName,
    required this.eventType,
    required this.eventDate,
    required this.dark,
    required this.notifyOn,
    required this.loading,
    required this.onNotify,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(
          0xFF122235,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppColors.cyan.withOpacity(
            0.30,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(
                      0.14,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: AppColors.cyan,
                    size: 25,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        eventType,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(
                      0.12,
                    ),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: const Text(
                    'UPCOMING',
                    style: TextStyle(
                      color: AppColors.cyan,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.cyan,
                  size: 17,
                ),
                const SizedBox(
                  width: 7,
                ),
                Expanded(
                  child: Text(
                    eventDate,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'A special event is coming soon. Turn on notifications so you know when it starts.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: loading ? null : onNotify,
                icon: loading
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.cyan,
                        ),
                      )
                    : Icon(
                        notifyOn
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                      ),
                label: Text(
                  notifyOn ? 'Notifications On' : 'Notify Me',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.cyan,
                  side: BorderSide(
                    color: AppColors.cyan.withOpacity(
                      0.55,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// LIVE EVENT CARD
// ================================================================

class _LiveEventCard extends StatelessWidget {
  final String eventName;
  final String eventType;
  final String eventDate;
  final bool dark;
  final VoidCallback onParticipate;

  const _LiveEventCard({
    required this.eventName,
    required this.eventType,
    required this.eventDate,
    required this.dark,
    required this.onParticipate,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(
          0xFF122235,
        ),
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppColors.cyan.withOpacity(
            0.35,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(
                      0.14,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.travel_explore_rounded,
                    color: AppColors.cyan,
                    size: 25,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        eventType,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(
                      0.15,
                    ),
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                    border: Border.all(
                      color: Colors.green.withOpacity(
                        0.45,
                      ),
                    ),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.cyan,
                  size: 17,
                ),
                const SizedBox(
                  width: 7,
                ),
                Expanded(
                  child: Text(
                    eventDate,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'The event is live! Join a group and start the challenge.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onParticipate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(
                    0xFF7C4DFF,
                  ),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                ),
                child: const Text(
                  'Participate',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// TOPIC MAP
// ================================================================

class _TopicMap extends StatelessWidget {
  final TopicDef activeTopic;

  final int Function(TopicDef) learnedCount;

  final bool Function(TopicDef) isComplete;

  final bool Function(TopicDef) isLocked;

  final void Function(TopicDef) onTapTopic;

  final bool dark;

  const _TopicMap({
    required this.activeTopic,
    required this.learnedCount,
    required this.isComplete,
    required this.isLocked,
    required this.onTapTopic,
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        final points = kTopics
            .map(
              (t) => Offset(
                t.pos.dx * size.width,
                t.pos.dy * size.height,
              ),
            )
            .toList();

        final activeIndex = kTopics.indexOf(
          activeTopic,
        );

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              24,
            ),
            border: Border.all(
              color: AppColors.border(
                dark,
              ),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MapBackdropPainter(
                    dark: dark,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _PathPainter(
                    points: points,
                    dark: dark,
                  ),
                ),
              ),
              if (activeIndex >= 0 && activeIndex < points.length)
                Positioned(
                  left: points[activeIndex].dx - 12,
                  top: points[activeIndex].dy - 66,
                  child: const Icon(
                    Icons.directions_walk_rounded,
                    color: AppColors.flame,
                    size: 26,
                  ),
                ),
              for (int i = 0; i < kTopics.length; i++)
                _buildNode(
                  kTopics[i],
                  points[i],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNode(
    TopicDef topic,
    Offset center,
  ) {
    const nodeSize = 56.0;

    final complete = isComplete(topic);

    final locked = isLocked(topic);

    final isActive = topic.id == activeTopic.id;

    return Positioned(
      left: center.dx - nodeSize / 2,
      top: center.dy - nodeSize / 2 - 18,
      child: GestureDetector(
        onTap: () => onTapTopic(topic),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (isActive)
                  Container(
                    width: nodeSize + 16,
                    height: nodeSize + 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.cyan.withOpacity(
                          0.5,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                Container(
                  width: nodeSize,
                  height: nodeSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: locked
                        ? AppColors.secondary(
                            dark,
                          )
                        : topic.color.withOpacity(
                            0.18,
                          ),
                    border: Border.all(
                      color: locked
                          ? AppColors.border(
                              dark,
                            )
                          : topic.color,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow(
                          dark,
                        ),
                        blurRadius: 6,
                        offset: const Offset(
                          0,
                          2,
                        ),
                      ),
                    ],
                  ),
                  child: Icon(
                    locked && topic.isPremium
                        ? Icons.star_rounded
                        : locked
                            ? Icons.lock_rounded
                            : topic.icon,
                    color: locked && topic.isPremium
                        ? const Color(0xFFFFB300)
                        : locked
                            ? AppColors.textTertiary(
                                dark,
                              )
                            : topic.color,
                    size: 24,
                  ),
                ),
                if (complete)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green,
                        border: Border.all(
                          color: AppColors.card(
                            dark,
                          ),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (locked && topic.isPremium)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cyan,
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        size: 18,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(
              height: 6,
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.bg(
                  dark,
                ).withOpacity(
                  0.85,
                ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    topic.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: locked
                          ? AppColors.textTertiary(
                              dark,
                            )
                          : AppColors.textPrimary(
                              dark,
                            ),
                    ),
                  ),
                  if (locked && topic.isPremium)
                    const Text(
                      'Subscribe to unlock this topic',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFB300),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// PATH PAINTER
// ================================================================

class _PathPainter extends CustomPainter {
  final List<Offset> points;
  final bool dark;

  const _PathPainter({
    required this.points,
    required this.dark,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    if (points.length < 2) {
      return;
    }

    final path = Path()
      ..moveTo(
        points.first.dx,
        points.first.dy,
      );

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];

      final end = points[i + 1];

      final mid = Offset(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
      );

      final dx = end.dx - start.dx;

      final dy = end.dy - start.dy;

      final length = math.sqrt(
        dx * dx + dy * dy,
      );

      final perp = length == 0
          ? const Offset(
              0,
              0,
            )
          : Offset(
              -dy / length,
              dx / length,
            );

      final wiggle = (i.isEven ? 1 : -1) * length * 0.16;

      final control = mid + perp * wiggle;

      path.quadraticBezierTo(
        control.dx,
        control.dy,
        end.dx,
        end.dy,
      );
    }

    final dashed = _dashPath(
      path,
      dashLength: 8,
      gapLength: 6,
    );

    final paint = Paint()
      ..color = const Color(
        0xFF2D2D2D,
      ).withOpacity(
        0.6,
      )
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      dashed,
      paint,
    );
  }

  Path _dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dest = Path();

    for (final metric in source.computeMetrics()) {
      double distance = 0;
      bool draw = true;

      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;

        final next = (distance + len).clamp(
          0.0,
          metric.length,
        );

        if (draw) {
          dest.addPath(
            metric.extractPath(
              distance,
              next,
            ),
            Offset.zero,
          );
        }

        distance = next;
        draw = !draw;
      }
    }

    return dest;
  }

  @override
  bool shouldRepaint(
    covariant _PathPainter oldDelegate,
  ) {
    return oldDelegate.points != points || oldDelegate.dark != dark;
  }
}

// ================================================================
// MAP BACKGROUND
// ================================================================

class _MapBackdropPainter extends CustomPainter {
  final bool dark;

  const _MapBackdropPainter({
    required this.dark,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = dark
          ? const Color(
              0xFF111820,
            )
          : const Color(
              0xFFF4F7F8,
            );

    canvas.drawRect(
      Offset.zero & size,
      paint,
    );

    final gridPaint = Paint()
      ..color = dark
          ? Colors.white.withOpacity(
              0.025,
            )
          : Colors.black.withOpacity(
              0.025,
            )
      ..strokeWidth = 1;

    const spacing = 28.0;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(
          x,
          size.height,
        ),
        gridPaint,
      );
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(
          size.width,
          y,
        ),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _MapBackdropPainter oldDelegate,
  ) {
    return oldDelegate.dark != dark;
  }
}
