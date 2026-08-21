import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'friend_profile_screen.dart';

/// Friends list — matches the "Friends.png" design: header with
/// "Learn together" subtitle, add/gift/search icons top-right, and a
/// list of friend rows (avatar initial, name, level, BFF/Friend badge).
///
/// TODO(Person 3): swap `_placeholderFriends` for
/// `FirestoreService.getFriends()` once that method exists — call it from
/// initState the same way other screens call DatabaseService.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendData {
  final String name;
  final int level;
  final bool isBff;
  const _FriendData(
      {required this.name, required this.level, required this.isBff});
}

class _FriendsScreenState extends State<FriendsScreen> {
  final List<_FriendData> _friends = const [
    _FriendData(name: 'Pim K.', level: 8, isBff: true),
    _FriendData(name: 'Ohm S.', level: 8, isBff: true),
    _FriendData(name: 'Kai T.', level: 8, isBff: false),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Friends',
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary(dark),
                              letterSpacing: -0.5)),
                      Text('Learn together',
                          style: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 14)),
                    ],
                  ),
                  const Spacer(),
                  _HeaderIcon(
                      icon: Icons.person_add_alt_1_rounded,
                      dark: dark,
                      onTap: _showAddFriend),
                  const SizedBox(width: 14),
                  _HeaderIcon(
                      icon: Icons.card_giftcard_rounded,
                      dark: dark,
                      onTap: () {}),
                  const SizedBox(width: 14),
                  _HeaderIcon(
                      icon: Icons.search_rounded,
                      dark: dark,
                      onTap: () {},
                      color: const Color(0xFF9C6FFF)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _friends.isEmpty
                  ? _EmptyFriends(dark: dark)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                      itemCount: _friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final f = _friends[i];
                        return _FriendRow(
                          friend: f,
                          dark: dark,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FriendProfileScreen(
                                name: f.name,
                                level: f.level,
                                isBff: f.isBff,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFriend() {
    final dark = ThemeProvider.isDark(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a friend',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary(dark))),
            const SizedBox(height: 16),
            TextField(
              style: TextStyle(color: AppColors.textPrimary(dark)),
              decoration: InputDecoration(
                hintText: 'Enter username',
                hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
                filled: true,
                fillColor: AppColors.bg(dark),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Send request',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final bool dark;
  final VoidCallback onTap;
  final Color? color;
  const _HeaderIcon(
      {required this.icon,
      required this.dark,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: color ?? AppColors.cyan, size: 24),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final _FriendData friend;
  final bool dark;
  final VoidCallback onTap;
  const _FriendRow(
      {required this.friend, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary(dark),
                border: Border.all(color: AppColors.border(dark)),
              ),
              child: Center(
                child: Text(friend.name.isNotEmpty ? friend.name[0] : '?',
                    style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.name,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary(dark))),
                  Text('Lv ${friend.level}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary(dark))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFB300)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(friend.isBff ? 'BFF' : 'Friend',
                      style: const TextStyle(
                          color: Color(0xFFFFB300),
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded,
                      color: Color(0xFFFFB300), size: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFriends extends StatelessWidget {
  final bool dark;
  const _EmptyFriends({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded,
                size: 64, color: AppColors.textTertiary(dark)),
            const SizedBox(height: 16),
            Text('No friends yet!\nAdd friends to learn together.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary(dark), fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
