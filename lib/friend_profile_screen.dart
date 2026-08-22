import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'firestore_service.dart';

/// Friend profile — matches the "Pim K." profile design:
/// back arrow + name + BFF badge, 3 stat boxes (Friends/Level/Bond),
/// a gold bond progress bar, an events-participated chip row, and a
/// gifts grid with a "Send Gift" action.
///
/// Bond is loaded live from FirestoreService.getBond(uid) — pass the
/// friend's uid in via [friendUid] so this screen can fetch it and let
/// the user send gifts. friendsCount/eventsParticipated are still
/// placeholder until there's backing data for those.
class FriendProfileScreen extends StatefulWidget {
  final String friendUid;
  final String name;
  final int level;
  final bool isBff;
  final int bondGoal;
  final List<String> eventsParticipated;

  const FriendProfileScreen({
    super.key,
    required this.friendUid,
    required this.name,
    required this.level,
    required this.isBff,
    this.bondGoal = 20,
    this.eventsParticipated = const [
      'Treasure Hunt',
      'Word Rush',
      'Colors Sprint'
    ],
  });

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  int _bond = 0;
  int _friendsCount = 0;
  bool _loadingBond = true;
  bool _loadingFriendsCount = true;
  bool _sendingGift = false;

  @override
  void initState() {
    super.initState();
    _loadBond();
    _loadFriendsCount();
  }

  Future<void> _loadBond() async {
    final bond = await FirestoreService.getBond(widget.friendUid);
    if (!mounted) return;
    setState(() {
      _bond = bond;
      _loadingBond = false;
    });
  }

  Future<void> _loadFriendsCount() async {
    final count =
        await FirestoreService.getFriendsCountFor(widget.friendUid);
    if (!mounted) return;
    setState(() {
      _friendsCount = count;
      _loadingFriendsCount = false;
    });
  }

  Future<void> _openGiftPicker() async {
    final dark = ThemeProvider.isDark(context);
    final giftId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg(dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GiftPickerSheet(dark: dark),
    );
    if (giftId == null || !mounted) return;
    await _sendGift(giftId);
  }

  Future<void> _sendGift(String giftId) async {
    setState(() => _sendingGift = true);
    try {
      await FirestoreService.sendGift(
          toUid: widget.friendUid, giftId: giftId);
      await _loadBond();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gift sent!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('Not enough tokens')
              ? 'Not enough tokens for that gift'
              : 'Failed to send gift'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _sendingGift = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    final bondProgress = (_bond / widget.bondGoal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card(dark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border(dark)),
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary(dark), size: 18),
                    ),
                  ),
                  Expanded(
                    child: Text(widget.name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary(dark))),
                  ),
                  if (widget.isBff)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFFB300)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('BFF',
                              style: TextStyle(
                                  color: Color(0xFFFFB300),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(width: 4),
                          Icon(Icons.star_rounded,
                              color: Color(0xFFFFB300), size: 14),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.cyan, width: 2.5),
                    color: AppColors.card(dark),
                  ),
                  child: Center(
                    child: Text(
                        widget.name.isNotEmpty
                            ? widget.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AppColors.cyan)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      color: const Color(0xFF9C6FFF),
                      label: 'Friends',
                      value: _loadingFriendsCount ? '…' : '$_friendsCount',
                      dark: dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      color: AppColors.cyan,
                      label: 'Level',
                      value: '${widget.level}',
                      dark: dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatBox(
                      color: Colors.green,
                      label: 'Bond',
                      value: _loadingBond
                          ? '…'
                          : '$_bond/${widget.bondGoal}',
                      dark: dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _loadingBond ? 0 : bondProgress,
                  backgroundColor: AppColors.secondary(dark),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sendingGift ? null : _openGiftPicker,
                  icon: _sendingGift
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.card_giftcard_rounded,
                          color: Colors.black, size: 18),
                  label: Text(_sendingGift ? 'Sending…' : 'Send Gift',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('EVENTS PARTICIPATED',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.eventsParticipated
                    .map((e) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card(dark),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border(dark)),
                          ),
                          child: Text(e,
                              style: TextStyle(
                                  color: AppColors.textPrimary(dark),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 28),
              Text('GIFTS',
                  style: TextStyle(
                      color: AppColors.textSecondary(dark),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: FirestoreService.giftCatalog
                    .map((g) => SizedBox(
                          width:
                              (MediaQuery.of(context).size.width - 48 - 24) /
                                  3,
                          child: _GiftTile(
                            emoji: g['emoji'] as String,
                            label: g['name'] as String,
                            cost: g['cost'] as int,
                            dark: dark,
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final Color color;
  final String label, value;
  final bool dark;
  const _StatBox(
      {required this.color,
      required this.label,
      required this.value,
      required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary(dark), fontSize: 11)),
        ],
      ),
    );
  }
}

// Read-only tile shown in the friend profile's GIFTS grid — displays the
// gift and its token cost. Tapping "Send Gift" above opens the picker;
// these tiles are just a catalog preview.
class _GiftTile extends StatelessWidget {
  final String emoji, label;
  final int cost;
  final bool dark;
  const _GiftTile(
      {required this.emoji,
      required this.label,
      required this.cost,
      required this.dark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('$cost tokens',
              style: TextStyle(
                  color: AppColors.textSecondary(dark), fontSize: 10)),
        ],
      ),
    );
  }
}

// Bottom sheet gift picker — returns the selected gift id via
// Navigator.pop, or null if dismissed.
class _GiftPickerSheet extends StatelessWidget {
  final bool dark;
  const _GiftPickerSheet({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.border(dark),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Send a gift',
              style: TextStyle(
                  color: AppColors.textPrimary(dark),
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: FirestoreService.giftCatalog.map((g) {
              return GestureDetector(
                onTap: () => Navigator.pop(context, g['id'] as String),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card(dark),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border(dark)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(g['emoji'] as String,
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 6),
                      Text(g['name'] as String,
                          style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${g['cost']} tokens',
                          style: TextStyle(
                              color: AppColors.textSecondary(dark),
                              fontSize: 10)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}