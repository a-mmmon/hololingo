import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'event_group_lobby_screen.dart';
import 'event_invites_screen.dart';

class EventScreen extends StatefulWidget {
  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  Map<String, dynamic>? _event;
  bool _loading = true;
  String? _error;
  int _inviteCount = 0;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    try {
      final event = await DatabaseService.getCurrentEvent();
      debugPrint('EVENT SCREEN FIRESTORE DATA: $event');
      final eventName = event?['name']?.toString().trim();
      final inviteCount = eventName == null || eventName.isEmpty
          ? 0
          : await FirestoreService.getEventGroupInviteCount(
              eventId: FirestoreService.eventIdFromName(eventName),
            );
      if (!mounted) return;
      setState(() {
        _event = event;
        _inviteCount = inviteCount;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('EVENT SCREEN ERROR: $e');
      if (!mounted) return;
      setState(() {
        _event = null;
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool get _isActive {
    if (_event == null) return false;
    final value = _event!['active'];
    if (value is bool) return value;
    return value?.toString().toLowerCase() == 'true';
  }

  String get _eventName {
    final value = _event?['name'];
    if (value == null || value.toString().trim().isEmpty) {
      return 'Special Event';
    }
    return value.toString();
  }

  String get _eventId => FirestoreService.eventIdFromName(_eventName);

  DateTime? _getEventDate() {
    final value = _event?['date'];
    if (value == null) return null;
    try {
      final date = (value as dynamic).toDate();
      if (date is DateTime) return date;
    } catch (_) {}
    return DateTime.tryParse(value.toString());
  }

  String _formatEventDate() {
    final date = _getEventDate();
    if (date == null) return 'Date not available';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _participate() async {
    if (!_isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('There is no active event right now.')),
      );
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
  }

  Future<void> _openInvites() async {
    if (_event == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventInvitesScreen(
          eventId: _eventId,
          eventName: _eventName,
        ),
      ),
    );

    if (!mounted) return;
    final count = await FirestoreService.getEventGroupInviteCount(
      eventId: _eventId,
    );
    if (mounted) setState(() => _inviteCount = count);
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor: AppColors.bg(dark),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary(dark)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Events',
          style: TextStyle(
            color: AppColors.textPrimary(dark),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          if (!_loading && _event != null && _isActive)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  onPressed: _openInvites,
                  icon: Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.textPrimary(dark),
                  ),
                ),
                if (_inviteCount > 0)
                  Positioned(
                    right: 7,
                    top: 6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _inviteCount > 9 ? '9+' : '$_inviteCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: _buildBody(dark),
    );
  }

  Widget _buildBody(bool dark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    }

    if (_error != null) {
      return RefreshIndicator(
        color: AppColors.cyan,
        onRefresh: _loadEvent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.28),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.error_outline_rounded, size: 60,
                      color: Colors.redAccent.withOpacity(0.8)),
                  const SizedBox(height: 16),
                  Text('Could not load event', style: TextStyle(
                    color: AppColors.textPrimary(dark), fontSize: 21, fontWeight: FontWeight.w800,
                  )),
                  const SizedBox(height: 10),
                  Text('Please check your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loadEvent,
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.black),
                    child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_event == null || !_isActive) {
      return RefreshIndicator(
        color: AppColors.cyan,
        onRefresh: _loadEvent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  Container(
                    width: 90, height: 90,
                    decoration: BoxDecoration(color: AppColors.card(dark), shape: BoxShape.circle),
                    child: Icon(Icons.event_busy_rounded, size: 45, color: AppColors.textSecondary(dark)),
                  ),
                  const SizedBox(height: 22),
                  Text('No event right now', textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(
                    'Special events happen once or twice a month. Come back when the next event starts!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _loadEvent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF182C42), Color(0xFF243D55), Color(0xFF263B63)],
                ),
                border: Border.all(color: const Color(0xFF9C6FFF).withOpacity(0.35)),
              ),
              child: Stack(
                children: [
                  Positioned(right: -15, top: -20,
                    child: Icon(Icons.explore_rounded, size: 150, color: Colors.white.withOpacity(0.06))),
                  Positioned(left: -30, bottom: -45,
                    child: Icon(Icons.map_rounded, size: 160, color: AppColors.cyan.withOpacity(0.06))),
                  Positioned(left: 22, top: 22,
                    child: Container(
                      width: 58, height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C4DFF).withOpacity(0.18), shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF9C6FFF).withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFBDA5FF), size: 31),
                    )),
                  Positioned(left: 22, right: 22, bottom: 22,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_eventName, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      const Text('Limited-time special event', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ])),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.13), borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.circle, size: 8, color: Colors.greenAccent), SizedBox(width: 7),
                  Text('EVENT ACTIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w800)),
                ]),
              ),
              const Spacer(),
              Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.textSecondary(dark)),
              const SizedBox(width: 7),
              Text(_formatEventDate(), style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 12)),
            ]),
            const SizedBox(height: 26),
            Text(_eventName, style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 27, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              'A special limited-time challenge where you can team up with friends, complete missions, and earn exclusive rewards.',
              style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _participate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF), foregroundColor: Colors.white,
                  elevation: 0, padding: const EdgeInsets.symmetric(vertical: 17),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Participate in Event', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 28),
            Text('HOW IT WORKS', style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            _EventStep(number: '1', icon: Icons.groups_rounded, title: 'Create or join a group', subtitle: 'Team up with your friends before the event starts.', dark: dark),
            _EventStep(number: '2', icon: Icons.play_circle_outline_rounded, title: 'Get ready', subtitle: 'Everyone in the group must be ready before starting.', dark: dark),
            _EventStep(number: '3', icon: Icons.camera_alt_rounded, title: 'Complete the challenge', subtitle: 'Use HoloLingo to find and scan the required objects.', dark: dark),
            _EventStep(number: '4', icon: Icons.emoji_events_rounded, title: 'Earn rewards', subtitle: 'Finish the event and receive special XP and Tokens.', dark: dark),
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF16103A), borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF9C6FFF).withOpacity(0.3)),
              ),
              child: Row(children: [
                Container(width: 48, height: 48,
                  decoration: BoxDecoration(color: const Color(0xFFFFB300).withOpacity(0.13), shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFB300), size: 26)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Special Event Rewards', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Complete the event to earn special XP and Tokens.', style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12, height: 1.35)),
                ])),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventStep extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool dark;

  const _EventStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.cyan.withOpacity(0.12), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(number, style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.bg(dark), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.textSecondary(dark), size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11, height: 1.3)),
        ])),
      ]),
    );
  }
}
