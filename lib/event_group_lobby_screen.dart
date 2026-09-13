import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'event_invites_screen.dart';

import 'app_theme.dart';
import 'firestore_service.dart';

class EventGroupLobbyScreen extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String? initialGroupId;

  const EventGroupLobbyScreen({
    super.key,
    required this.eventId,
    required this.eventName,
    this.initialGroupId,
  });

  @override
  State<EventGroupLobbyScreen> createState() => _EventGroupLobbyScreenState();
}

class _EventGroupLobbyScreenState extends State<EventGroupLobbyScreen> {
  Map<String, dynamic>? _group;
  bool _loading = true;
  bool _busy = false;
  bool _localReady = false;
  int _inviteCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMyGroup();
  }

  Future<void> _loadMyGroup() async {
    try {
      final group = await FirestoreService.getMyEventGroup(widget.eventId);
      final inviteCount = await FirestoreService.getEventGroupInviteCount(
        eventId: widget.eventId,
      );
      if (!mounted) return;
      setState(() {
        _group = group;
        _inviteCount = inviteCount;
        _loading = false;
        _syncLocalReady(group);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(_cleanError(e));
    }
  }

  List<Map<String, dynamic>> get _members {
    final raw = _group?['members'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> get _readyIds {
    final raw = _group?['ready_ids'];
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  bool get _isLeader =>
      _group?['leader_id']?.toString() == FirestoreService.currentUserId;

  void _syncLocalReady([Map<String, dynamic>? group]) {
    final data = group ?? _group;
    final raw = data?['ready_ids'];
    final ids = raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    _localReady = ids.contains(FirestoreService.currentUserId);
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    String type = 'private';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        final dark = ThemeProvider.isDark(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: AppColors.card(dark),
            title: Text(
              'Create a Group',
              style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  style: TextStyle(color: AppColors.textPrimary(dark)),
                  decoration: InputDecoration(
                    labelText: 'Group name',
                    hintText: 'Example: Dog Lovers',
                    labelStyle: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Group type',
                    style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 13,
                    ),
                  ),
                ),
                RadioListTile<String>(
                  value: 'private',
                  groupValue: type,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Private',
                    style: TextStyle(color: AppColors.textPrimary(dark)),
                  ),
                  subtitle: Text(
                    'Invite teammates with the group code.',
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                  onChanged: (value) => setDialogState(() => type = value!),
                ),
                RadioListTile<String>(
                  value: 'public',
                  groupValue: type,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Public',
                    style: TextStyle(color: AppColors.textPrimary(dark)),
                  ),
                  subtitle: Text(
                    'Anyone can join from the event list or code.',
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                  onChanged: (value) => setDialogState(() => type = value!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(dialogContext, {'name': name, 'type': type});
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Create'),
              ),
            ],
          ),
        );
      },
    );

    nameController.dispose();
    if (result == null) return;

    await _runBusy(() async {
      final group = await FirestoreService.createEventGroup(
        eventId: widget.eventId,
        name: result['name']!,
        type: result['type']!,
      );
      if (!mounted) return;
      setState(() {
        _group = group;
        _syncLocalReady(group);
      });
    });
  }

  Future<void> _joinGroup() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final dark = ThemeProvider.isDark(dialogContext);
        return AlertDialog(
          backgroundColor: AppColors.card(dark),
          title: Text(
            'Join a Group',
            style: TextStyle(
              color: AppColors.textPrimary(dark),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 6,
            style: TextStyle(
              color: AppColors.textPrimary(dark),
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
            decoration: InputDecoration(
              labelText: 'Group code',
              hintText: 'ABC123',
              labelStyle: TextStyle(color: AppColors.textSecondary(dark)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(dialogContext, value);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.black,
              ),
              child: const Text('Join'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (code == null || code.trim().isEmpty) return;

    await _runBusy(() async {
      final group = await FirestoreService.joinEventGroupByCode(
        eventId: widget.eventId,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _group = group;
        _syncLocalReady(group);
      });
    });
  }

  Future<void> _invite() async {
    final group = _group;
    if (group == null) return;

    final friends = await FirestoreService.getFriends();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card(ThemeProvider.isDark(context)),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final dark = ThemeProvider.isDark(sheetContext);
        final sent = <String>{};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Invite friends',
                              style: TextStyle(
                                color: AppColors.textPrimary(dark),
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: Icon(
                              Icons.close_rounded,
                              color: AppColors.textSecondary(dark),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Choose a friend to send an in-app invitation.',
                        style: TextStyle(
                          color: AppColors.textSecondary(dark),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (friends.isEmpty)
                        Expanded(
                          child: Center(
                            child: Text(
                              'You do not have any friends yet.',
                              style: TextStyle(
                                color: AppColors.textSecondary(dark),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.separated(
                            itemCount: friends.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final friend = friends[index];
                              final uid = friend['uid']?.toString() ?? '';
                              final name = friend['name']?.toString() ?? 'User';
                              final alreadySent = sent.contains(uid);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.bg(dark),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: AppColors.border(dark),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.cyan.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.person_rounded,
                                        color: AppColors.cyan,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          color: AppColors.textPrimary(dark),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: alreadySent || uid.isEmpty
                                          ? null
                                          : () async {
                                              try {
                                                await FirestoreService.sendEventGroupInvite(
                                                  eventId: widget.eventId,
                                                  groupId: group['id'].toString(),
                                                  toUid: uid,
                                                  eventName: widget.eventName,
                                                );
                                                if (!context.mounted) return;
                                                setSheetState(() => sent.add(uid));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Invitation sent to $name.'),
                                                  ),
                                                );
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                final message = e.toString().replaceFirst('Exception: ', '');
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text(message)),
                                                );
                                              }
                                            },
                                      child: Text(alreadySent ? 'Sent ✓' : 'Invite'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final name = (group['name'] ?? 'Event Group').toString();
                            final code = (group['code'] ?? '').toString().trim();
                            final box = context.findRenderObject() as RenderBox?;
                            final text =
                                'Join my HoloLingo event group "$name" for ${widget.eventName}!\n\n'
                                'Group code: $code\n\n'
                                'Open HoloLingo → Event → Participate → Join a Group and enter this code.';
                            await SharePlus.instance.share(
                              ShareParams(
                                text: text,
                                title: 'Invite to $name',
                                subject: 'Join my HoloLingo group',
                                sharePositionOrigin: box == null
                                    ? null
                                    : box.localToGlobal(Offset.zero) & box.size,
                              ),
                            );
                          },
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Share group code instead'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openInvites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventInvitesScreen(
          eventId: widget.eventId,
          eventName: widget.eventName,
        ),
      ),
    );
    if (mounted) {
      final count = await FirestoreService.getEventGroupInviteCount(
        eventId: widget.eventId,
      );
      if (mounted) setState(() => _inviteCount = count);
    }
  }

  Future<void> _toggleReady() async {
    final groupId = _group?['id']?.toString();
    if (groupId == null) return;

    final next = !_localReady;
    await _runBusy(() async {
      await FirestoreService.setEventGroupReady(
        eventId: widget.eventId,
        groupId: groupId,
        ready: next,
      );
      await _reloadGroup(groupId);
    });
  }

  Future<void> _startHunt() async {
    final groupId = _group?['id']?.toString();
    if (groupId == null) return;

    await _runBusy(() async {
      await FirestoreService.startEventGroup(
        eventId: widget.eventId,
        groupId: groupId,
      );
      await _reloadGroup(groupId);
      if (mounted) _showMessage('Hunt started!');
    });
  }

  Future<void> _leaveGroup() async {
    final groupId = _group?['id']?.toString();
    if (groupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You can join another group later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _runBusy(() async {
      await FirestoreService.leaveEventGroup(
        eventId: widget.eventId,
        groupId: groupId,
      );
      if (!mounted) return;
      setState(() {
        _group = null;
        _localReady = false;
      });
    });
  }

  Future<void> _reloadGroup(String groupId) async {
    final group = await FirestoreService.getEventGroup(widget.eventId, groupId);
    if (!mounted) return;
    setState(() {
      _group = group;
      _syncLocalReady(group);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) _showError(_cleanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          'Event Group',
          style: TextStyle(
            color: AppColors.textPrimary(dark),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
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
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          : RefreshIndicator(
              color: AppColors.cyan,
              onRefresh: _loadMyGroup,
              child: _group == null
                  ? _buildChooseGroup(dark)
                  : _buildLobby(dark),
            ),
    );
  }

  Widget _buildChooseGroup(bool dark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        _hero(dark),
        const SizedBox(height: 26),
        Text(
          'Join your team',
          style: TextStyle(
            color: AppColors.textPrimary(dark),
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Create a new group or use a friend’s code to join their group.',
          style: TextStyle(
            color: AppColors.textSecondary(dark),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        _actionCard(
          dark: dark,
          icon: Icons.add_circle_outline_rounded,
          title: 'Create a Group',
          subtitle: 'Start a team and invite your friends.',
          onTap: _busy ? null : _createGroup,
        ),
        const SizedBox(height: 12),
        _actionCard(
          dark: dark,
          icon: Icons.login_rounded,
          title: 'Join a Group',
          subtitle: 'Enter the 6-character group code.',
          onTap: _busy ? null : _joinGroup,
        ),
      ],
    );
  }

  Widget _hero(bool dark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF182C42), Color(0xFF263B63)],
        ),
        border: Border.all(
          color: const Color(0xFF9C6FFF).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.groups_rounded,
              color: Color(0xFFBDA5FF),
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.eventName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Team up for the treasure hunt',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required bool dark,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border(dark)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.cyan, size: 25),
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
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
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
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary(dark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLobby(bool dark) {
    final members = _members;
    final readyCount = _readyIds.length;
    final maxPlayers = 4;
    final groupName = (_group?['name'] ?? 'Event Group').toString();
    final code = (_group?['code'] ?? '------').toString();
    final type = (_group?['type'] ?? 'private').toString().toUpperCase();
    final status = (_group?['status'] ?? 'waiting').toString();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF16103A),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF9C6FFF).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                groupName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.eventName,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF9C6FFF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  type,
                  style: const TextStyle(
                    color: Color(0xFFBDA5FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text(
                    'GROUP CODE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const Spacer(),
                  SelectableText(
                    code,
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _invite,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('INVITE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              'Members',
              style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '$readyCount/${members.length} ready',
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...members.map((member) => _memberTile(dark, member)),
        if (members.length < maxPlayers)
          _emptyMemberTile(dark, maxPlayers - members.length),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _invite,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Invite'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFBDA5FF),
              side: const BorderSide(color: Color(0xFF9C6FFF)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (status == 'starting')
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.play_circle_fill_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'The group has started the hunt.',
                    style: TextStyle(color: Colors.greenAccent, height: 1.35),
                  ),
                ),
              ],
            ),
          )
        else ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : _toggleReady,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _localReady ? Colors.greenAccent : AppColors.cyan,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColors.cyan.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                _localReady ? 'READY ✓' : 'READY',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_isLeader)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _busy ? null : _startHunt,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBDA5FF),
                  side: const BorderSide(color: Color(0xFF9C6FFF)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'START HUNT',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Waiting for the group leader to start the hunt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 12,
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : _leaveGroup,
          child: const Text('Leave Group'),
        ),
      ],
    );
  }

  Widget _memberTile(bool dark, Map<String, dynamic> member) {
    final name = (member['name'] ?? 'Player').toString();
    final uid = member['uid']?.toString() ?? '';
    final ready = _readyIds.contains(uid);
    final leaderId = _group?['leader_id']?.toString();
    final leader = uid == leaderId;

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: AppColors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (leader)
                  const Text(
                    'Leader',
                    style: TextStyle(
                      color: Color(0xFFBDA5FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (ready)
            const Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 20),
                SizedBox(width: 5),
                Text(
                  'Ready',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            Text(
              'Waiting',
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyMemberTile(bool dark, int count) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg(dark),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_add_alt_1_rounded,
              color: AppColors.textSecondary(dark)),
          const SizedBox(width: 12),
          Text(
            '$count open ${count == 1 ? 'spot' : 'spots'}',
            style: TextStyle(
              color: AppColors.textSecondary(dark),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
