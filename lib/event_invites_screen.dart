import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'event_group_lobby_screen.dart';

class EventInvitesScreen extends StatefulWidget {
  final String eventId;
  final String eventName;

  const EventInvitesScreen({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<EventInvitesScreen> createState() => _EventInvitesScreenState();
}

class _EventInvitesScreenState extends State<EventInvitesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _invites = [];
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    try {
      final invites = await FirestoreService.getEventGroupInvites(
        eventId: widget.eventId,
      );
      if (!mounted) return;
      setState(() {
        _invites = invites;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_cleanError(e));
    }
  }

  Future<void> _accept(Map<String, dynamic> invite) async {
    final id = invite['id']?.toString() ?? '';
    final code = invite['code']?.toString() ?? '';
    if (id.isEmpty || code.isEmpty || _busyIds.contains(id)) return;

    setState(() => _busyIds.add(id));
    try {
      final group = await FirestoreService.joinEventGroupByCode(
        eventId: widget.eventId,
        code: code,
      );
      await FirestoreService.deleteEventGroupInvite(
        eventId: widget.eventId,
        inviteId: id,
      );

      if (!mounted) return;
      setState(() {
        _invites.removeWhere((item) => item['id']?.toString() == id);
        _busyIds.remove(id);
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EventGroupLobbyScreen(
            eventId: widget.eventId,
            eventName: widget.eventName,
            initialGroupId: group['id']?.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(id));
      _showMessage(_cleanError(e));
    }
  }

  Future<void> _decline(Map<String, dynamic> invite) async {
    final id = invite['id']?.toString() ?? '';
    if (id.isEmpty || _busyIds.contains(id)) return;

    setState(() => _busyIds.add(id));
    try {
      await FirestoreService.deleteEventGroupInvite(
        eventId: widget.eventId,
        inviteId: id,
      );
      if (!mounted) return;
      setState(() {
        _invites.removeWhere((item) => item['id']?.toString() == id);
        _busyIds.remove(id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(id));
      _showMessage(_cleanError(e));
    }
  }

  String _cleanError(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary(dark),
          ),
        ),
        title: Text(
          'Invitations',
          style: TextStyle(
            color: AppColors.textPrimary(dark),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadInvites,
            icon: Icon(
              Icons.refresh_rounded,
              color: AppColors.textPrimary(dark),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          : RefreshIndicator(
              color: AppColors.cyan,
              onRefresh: _loadInvites,
              child: _invites.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(30),
                      children: [
                        const SizedBox(height: 90),
                        Icon(
                          Icons.notifications_none_rounded,
                          size: 70,
                          color: AppColors.textSecondary(false),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'No invitations yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary(dark),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'When a friend invites you to an event group, it will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary(dark),
                            height: 1.45,
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
                      itemCount: _invites.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _inviteCard(
                        dark,
                        _invites[index],
                      ),
                    ),
            ),
    );
  }

  Widget _inviteCard(bool dark, Map<String, dynamic> invite) {
    final id = invite['id']?.toString() ?? '';
    final inviter = invite['fromName']?.toString() ?? 'A friend';
    final groupName = invite['groupName']?.toString() ?? 'Event Group';
    final eventName = invite['eventName']?.toString() ?? widget.eventName;
    final type = invite['groupType']?.toString() ?? 'private';
    final busy = _busyIds.contains(id);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(dark)),
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
                  color: const Color(0xFF7C4DFF).withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.group_add_rounded,
                  color: Color(0xFFBDA5FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$inviter invited you',
                      style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      eventName,
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
          const SizedBox(height: 16),
          Text(
            groupName,
            style: TextStyle(
              color: AppColors.textPrimary(dark),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${type == 'public' ? 'Public' : 'Private'} event group',
            style: TextStyle(
              color: AppColors.textSecondary(dark),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _decline(invite),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : () => _accept(invite),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
