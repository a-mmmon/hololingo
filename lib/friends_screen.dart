import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';
import 'friend_profile_screen.dart';

enum FriendsScreenMode { friendsOnly, searchOnly }

class FriendsScreen extends StatefulWidget {
  final FriendsScreenMode mode;
  const FriendsScreen({super.key, required this.mode});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _friends = [];
  Set<String> _outgoingUids = {};
  bool _searching = false;
  bool _loading = true;

  bool get _isSearchOnly => widget.mode == FriendsScreenMode.searchOnly;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    if (_isSearchOnly) {
      // Also needs incoming requests now — this is the screen the
      // Profile's friend-add icon opens, and its notification dot is
      // driven by incoming requests, so tapping it has to actually show
      // them, not just a search box with no visible reason for the dot.
      // Also needs the friends list so search results for someone already
      // a friend show "Friends" instead of a re-addable "Add" button.
      final outgoing = await FirestoreService.getOutgoingRequests();
      final incoming = await FirestoreService.getIncomingRequests();
      final friends = await FirestoreService.getFriends();
      if (!mounted) return;
      setState(() {
        _outgoingUids = outgoing.map((r) => r['to'] as String).toSet();
        _incoming = incoming;
        _friends = friends;
        _loading = false;
      });
      return;
    }
    final incoming = await FirestoreService.getIncomingRequests();
    final friends = await FirestoreService.getFriends();
    if (!mounted) return;
    setState(() {
      _incoming = incoming;
      _friends = friends;
      _loading = false;
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    final results = await FirestoreService.searchUsersByName(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _sendRequest(Map<String, dynamic> user) async {
    final uid = user['uid'] as String;
    final name = user['name'] ?? 'User';
    setState(() => _outgoingUids.add(uid));
    try {
      await FirestoreService.sendFriendRequest(uid, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Friend request sent to $name'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      setState(() => _outgoingUids.remove(uid));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send request: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _accept(Map<String, dynamic> req) async {
    try {
      await FirestoreService.acceptFriendRequest(
          req['id'] as String, req['from'] as String);
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to accept: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _decline(Map<String, dynamic> req) async {
    try {
      await FirestoreService.declineFriendRequest(req['id'] as String);
      _loadAll();
    } catch (e) {
      debugPrint('decline error: $e');
    }
  }

  Future<void> _openFriendProfile(Map<String, dynamic> friend) async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(
      builder: (_) => FriendProfileScreen(
        friendUid: friend['uid'] ?? '',
        name: friend['name'] ?? 'User',
        level: friend['level'] ?? 1,
        isBff: false,
      ),
    ));

    if (result == true) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor: AppColors.bg(dark),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary(dark), size: 18),
          ),
        ),
        title: Text(_isSearchOnly ? 'Find friends' : 'Friends',
            style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan))
          : RefreshIndicator(
              onRefresh: _loadAll,
              color: AppColors.cyan,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_isSearchOnly) ...[
                    // ── Search-only mode ────────────────────────────────
                    if (_incoming.isNotEmpty) ...[
                      _SectionLabel('FRIEND REQUESTS', dark),
                      const SizedBox(height: 10),
                      ..._incoming.map((r) => _UserTile(
                            name: r['fromName'] ?? 'Someone',
                            dark: dark,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _decline(r),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Icon(Icons.close_rounded,
                                        color: AppColors.textSecondary(dark),
                                        size: 22),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _accept(r),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.cyan,
                                    ),
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.black, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 24),
                    ],
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border(dark)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        onChanged: _search,
                        style: TextStyle(
                            color: AppColors.textPrimary(dark), fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search by name',
                          hintStyle:
                              TextStyle(color: AppColors.textSecondary(dark)),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: AppColors.textSecondary(dark)),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.cyan)),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                    if (_searchResults.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _SectionLabel('SEARCH RESULTS', dark),
                      const SizedBox(height: 10),
                      ..._searchResults.map((u) {
                        final isFriend = _friends
                            .any((f) => f['uid'] == u['uid']);
                        final isRequested = _outgoingUids.contains(u['uid']);
                        return _UserTile(
                          name: u['name'] ?? 'User',
                          subtitle: u['city'],
                          dark: dark,
                          trailing: isFriend
                              ? _StatusPill(
                                  label: 'Friends',
                                  dark: dark,
                                  muted: true)
                              : isRequested
                                  ? _StatusPill(
                                      label: 'Requested',
                                      dark: dark,
                                      muted: true)
                                  : GestureDetector(
                                      onTap: () => _sendRequest(u),
                                      child: _StatusPill(
                                          label: 'Add',
                                          dark: dark,
                                          muted: false),
                                    ),
                        );
                      }),
                    ] else if (_searchController.text.trim().isNotEmpty &&
                        !_searching) ...[
                      const SizedBox(height: 40),
                      Center(
                        child: Text('No users found',
                            style: TextStyle(
                                color: AppColors.textSecondary(dark),
                                fontSize: 13)),
                      ),
                    ],
                  ] else ...[
                    // ── Friends-only mode ───────────────────────────────
                    if (_incoming.isNotEmpty) ...[
                      _SectionLabel('FRIEND REQUESTS', dark),
                      const SizedBox(height: 10),
                      ..._incoming.map((r) => _UserTile(
                            name: r['fromName'] ?? 'Someone',
                            dark: dark,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GestureDetector(
                                  onTap: () => _decline(r),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Icon(Icons.close_rounded,
                                        color: AppColors.textSecondary(dark),
                                        size: 22),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _accept(r),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.cyan,
                                    ),
                                    child: const Icon(Icons.check_rounded,
                                        color: Colors.black, size: 18),
                                  ),
                                ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 24),
                    ],
                    _SectionLabel('MY FRIENDS (${_friends.length})', dark),
                    const SizedBox(height: 10),
                    if (_friends.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.card(dark),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                              'No friends yet — use the search icon on your profile to add some',
                              style: TextStyle(
                                  color: AppColors.textSecondary(dark),
                                  fontSize: 13)),
                        ),
                      )
                    else
                      ..._friends.map((f) => _UserTile(
                            name: f['name'] ?? 'User',
                            subtitle: f['city'],
                            dark: dark,
                            onTap: () => _openFriendProfile(f),
                          )),
                  ],
                ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const _SectionLabel(this.text, this.dark);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: AppColors.textSecondary(dark),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0));
  }
}

class _UserTile extends StatelessWidget {
  final String name;
  final String? subtitle;
  final bool dark;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _UserTile({
    required this.name,
    this.subtitle,
    required this.dark,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card(dark),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.cyan, width: 1.5),
                color: AppColors.bg(dark),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.cyan),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!,
                        style: TextStyle(
                            color: AppColors.textSecondary(dark),
                            fontSize: 12)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool dark;
  final bool muted;
  const _StatusPill({required this.label, required this.dark, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: muted ? AppColors.bg(dark) : AppColors.cyan,
        borderRadius: BorderRadius.circular(20),
        border: muted ? Border.all(color: AppColors.border(dark)) : null,
      ),
      child: Text(label,
          style: TextStyle(
              color: muted ? AppColors.textSecondary(dark) : Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w700)),
    );
  }
}