import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';

class FriendProfileScreen extends StatefulWidget {
  final String friendUid;
  final String name;
  final int level;
  final bool isBff;
  final int bondGoal;

  const FriendProfileScreen({
    super.key,
    required this.friendUid,
    required this.name,
    required this.level,
    required this.isBff,
    this.bondGoal = 20,
  });

  @override
  State<FriendProfileScreen> createState() =>
      _FriendProfileScreenState();
}

class _FriendProfileScreenState
    extends State<FriendProfileScreen> {
  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  int _bond = 0;
  int _friendsCount = 0;

  bool _loadingBond = true;
  bool _loadingFriendsCount = true;
  bool _loadingEvents = true;
  bool _sendingGift = false;

  List<String> _eventsParticipated = [];

  @override
  void initState() {
    super.initState();

    _loadBond();
    _loadFriendsCount();
    _loadEventsParticipated();
  }

  // ============================================================
  // BOND
  // ============================================================

  Future<void> _loadBond() async {
    try {
      final bond =
          await FirestoreService.getBond(
        widget.friendUid,
      );

      if (!mounted) return;

      setState(() {
        _bond = bond;
        _loadingBond = false;
      });
    } catch (e) {
      debugPrint(
        'FriendProfile: load bond error: $e',
      );

      if (!mounted) return;

      setState(() {
        _bond = 0;
        _loadingBond = false;
      });
    }
  }

  // ============================================================
  // FRIEND COUNT
  // ============================================================

  Future<void> _loadFriendsCount() async {
    try {
      final count =
          await FirestoreService.getFriendsCountFor(
        widget.friendUid,
      );

      if (!mounted) return;

      setState(() {
        _friendsCount = count;
        _loadingFriendsCount = false;
      });
    } catch (e) {
      debugPrint(
        'FriendProfile: load friends count error: $e',
      );

      if (!mounted) return;

      setState(() {
        _friendsCount = 0;
        _loadingFriendsCount = false;
      });
    }
  }

  // ============================================================
  // EVENTS PARTICIPATED
  // ============================================================

  Future<void> _loadEventsParticipated() async {
    try {
      /*
       * Event groups are stored at:
       *
       * /events/{eventId}/groups/{groupId}
       *
       * Each group contains:
       *
       * member_uids: [uid1, uid2, ...]
       * event_id: "treasure_hunt"
       *
       * Therefore we can find every event group containing
       * this friend's UID.
       */
      final groupsSnapshot = await _db
          .collectionGroup('groups')
          .where(
            'member_uids',
            arrayContains: widget.friendUid,
          )
          .get();

      final eventIds = <String>{};

      for (final doc in groupsSnapshot.docs) {
        final data = doc.data();

        final eventId =
            data['event_id']?.toString().trim();

        if (eventId != null &&
            eventId.isNotEmpty) {
          eventIds.add(eventId);
        }
      }

      if (eventIds.isEmpty) {
        if (!mounted) return;

        setState(() {
          _eventsParticipated = [];
          _loadingEvents = false;
        });

        return;
      }

      final eventNames = <String>[];

      for (final eventId in eventIds) {
        try {
          final eventDoc = await _db
              .collection('events')
              .doc(eventId)
              .get();

          if (eventDoc.exists) {
            final data =
                eventDoc.data() ?? {};

            /*
             * Prefer the actual event name stored
             * in the event document.
             */
            final eventName =
                data['name']?.toString().trim();

            final eventTitle =
                data['title']?.toString().trim();

            if (eventName != null &&
                eventName.isNotEmpty) {
              eventNames.add(eventName);
            } else if (eventTitle != null &&
                eventTitle.isNotEmpty) {
              eventNames.add(eventTitle);
            } else {
              eventNames.add(
                _formatEventId(eventId),
              );
            }
          } else {
            /*
             * The group still proves participation,
             * even if the event definition was removed.
             */
            eventNames.add(
              _formatEventId(eventId),
            );
          }
        } catch (e) {
          debugPrint(
            'FriendProfile: event $eventId error: $e',
          );

          /*
           * Still show the event based on event_id
           * if its definition cannot be read.
           */
          eventNames.add(
            _formatEventId(eventId),
          );
        }
      }

      eventNames.sort();

      if (!mounted) return;

      setState(() {
        _eventsParticipated =
            eventNames.toSet().toList();
        _loadingEvents = false;
      });
    } catch (e) {
      debugPrint(
        'FriendProfile: load events error: $e',
      );

      if (!mounted) return;

      setState(() {
        _eventsParticipated = [];
        _loadingEvents = false;
      });
    }
  }

  String _formatEventId(String eventId) {
    return eventId
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              word[0].toUpperCase() +
              word.substring(1),
        )
        .join(' ');
  }

  // ============================================================
  // GIFT PICKER
  // ============================================================

  Future<void> _openGiftPicker() async {
    final dark =
        ThemeProvider.isDark(context);

    final giftId =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor:
          AppColors.bg(dark),
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) =>
          _GiftPickerSheet(
        dark: dark,
      ),
    );

    if (giftId == null ||
        !mounted) {
      return;
    }

    await _sendGift(giftId);
  }

  // ============================================================
  // SEND GIFT
  // ============================================================

  Future<void> _sendGift(
    String giftId,
  ) async {
    if (_sendingGift) return;

    setState(() {
      _sendingGift = true;
    });

    try {
      await FirestoreService.sendGift(
        toUid: widget.friendUid,
        giftId: giftId,
      );

      await _loadBond();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text('Gift sent!'),
            backgroundColor:
                Colors.green,
            duration:
                Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'FriendProfile: send gift error: $e',
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains(
                    'Not enough tokens',
                  )
                  ? 'Not enough tokens for that gift'
                  : 'Failed to send gift',
            ),
            backgroundColor:
                Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingGift = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final dark =
        ThemeProvider.isDark(context);

    final bondProgress =
        (_bond / widget.bondGoal)
            .clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor:
          AppColors.bg(dark),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            16,
            24,
            24,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ==================================================
              // HEADER
              // ==================================================

              Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        Navigator.pop(
                      context,
                    ),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors.card(
                          dark,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          12,
                        ),
                        border:
                            Border.all(
                          color:
                              AppColors
                                  .border(
                            dark,
                          ),
                        ),
                      ),
                      child: Icon(
                        Icons
                            .arrow_back_ios_new_rounded,
                        color:
                            AppColors
                                .textPrimary(
                          dark,
                        ),
                        size: 18,
                      ),
                    ),
                  ),

                  Expanded(
                    child: Text(
                      widget.name,
                      textAlign:
                          TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.w800,
                        color:
                            AppColors
                                .textPrimary(
                          dark,
                        ),
                      ),
                    ),
                  ),

                  if (widget.isBff)
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration:
                          BoxDecoration(
                        borderRadius:
                            BorderRadius
                                .circular(
                          20,
                        ),
                        border:
                            Border.all(
                          color:
                              const Color(
                            0xFFFFB300,
                          ),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Text(
                            'BFF',
                            style:
                                TextStyle(
                              color:
                                  Color(
                                0xFFFFB300,
                              ),
                              fontSize: 12,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),
                          SizedBox(
                            width: 4,
                          ),
                          Icon(
                            Icons
                                .star_rounded,
                            color:
                                Color(
                              0xFFFFB300,
                            ),
                            size: 14,
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(
                      width: 40,
                    ),
                ],
              ),

              const SizedBox(
                height: 24,
              ),

              // ==================================================
              // AVATAR
              // ==================================================

              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,
                    border:
                        Border.all(
                      color:
                          AppColors.cyan,
                      width: 2.5,
                    ),
                    color:
                        AppColors.card(
                      dark,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.name.isNotEmpty
                          ? widget.name[0]
                              .toUpperCase()
                          : '?',
                      style:
                          const TextStyle(
                        fontSize: 36,
                        fontWeight:
                            FontWeight.w800,
                        color:
                            AppColors.cyan,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 24,
              ),

              // ==================================================
              // STATS
              // ==================================================

              Row(
                children: [
                  Expanded(
                    child: _StatBox(
                      color:
                          const Color(
                        0xFF9C6FFF,
                      ),
                      label: 'Friends',
                      value:
                          _loadingFriendsCount
                              ? '…'
                              : '$_friendsCount',
                      dark: dark,
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: _StatBox(
                      color:
                          AppColors.cyan,
                      label: 'Level',
                      value:
                          '${widget.level}',
                      dark: dark,
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: _StatBox(
                      color:
                          Colors.green,
                      label: 'Bond',
                      value:
                          _loadingBond
                              ? '…'
                              : '$_bond/${widget.bondGoal}',
                      dark: dark,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 10,
              ),

              ClipRRect(
                borderRadius:
                    BorderRadius.circular(
                  4,
                ),
                child:
                    LinearProgressIndicator(
                  value: _loadingBond
                      ? 0
                      : bondProgress,
                  backgroundColor:
                      AppColors.secondary(
                    dark,
                  ),
                  valueColor:
                      const AlwaysStoppedAnimation<
                          Color>(
                    Color(0xFFFFB300),
                  ),
                  minHeight: 8,
                ),
              ),

              const SizedBox(
                height: 16,
              ),

              // ==================================================
              // SEND GIFT
              // ==================================================

              SizedBox(
                width:
                    double.infinity,
                child:
                    ElevatedButton.icon(
                  onPressed:
                      _sendingGift
                          ? null
                          : _openGiftPicker,
                  icon: _sendingGift
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color:
                                Colors.black,
                          ),
                        )
                      : const Icon(
                          Icons
                              .card_giftcard_rounded,
                          color:
                              Colors.black,
                          size: 18,
                        ),
                  label: Text(
                    _sendingGift
                        ? 'Sending…'
                        : 'Send Gift',
                    style:
                        const TextStyle(
                      color:
                          Colors.black,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.cyan,
                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 14,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        12,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 28,
              ),

              // ==================================================
              // EVENTS PARTICIPATED
              // ==================================================

              if (_loadingEvents) ...[
                Text(
                  'EVENTS PARTICIPATED',
                  style: TextStyle(
                    color:
                        AppColors
                            .textSecondary(
                      dark,
                    ),
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                const SizedBox(
                  height: 24,
                  width: 24,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                    color:
                        AppColors.cyan,
                  ),
                ),
              ] else if (_eventsParticipated
                  .isNotEmpty) ...[
                Text(
                  'EVENTS PARTICIPATED',
                  style: TextStyle(
                    color:
                        AppColors
                            .textSecondary(
                      dark,
                    ),
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(
                  height: 12,
                ),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                      _eventsParticipated
                          .map(
                    (eventName) =>
                        Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors
                                .card(
                          dark,
                        ),
                        borderRadius:
                            BorderRadius
                                .circular(
                          20,
                        ),
                        border:
                            Border.all(
                          color:
                              AppColors
                                  .border(
                            dark,
                          ),
                        ),
                      ),
                      child: Text(
                        eventName,
                        style:
                            TextStyle(
                          color:
                              AppColors
                                  .textPrimary(
                            dark,
                          ),
                          fontSize: 13,
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                      ),
                    ),
                  ).toList(),
                ),
              ],

              const SizedBox(
                height: 28,
              ),

              // ==================================================
              // GIFTS
              // ==================================================

              Text(
                'GIFTS',
                style: TextStyle(
                  color:
                      AppColors
                          .textSecondary(
                    dark,
                  ),
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    FirestoreService
                        .giftCatalog
                        .map(
                  (g) => SizedBox(
                    width:
                        (MediaQuery.of(
                                      context,
                                    ).size.width -
                                48 -
                                24) /
                            3,
                    child: _GiftTile(
                      emoji:
                          g['emoji']
                              as String,
                      label:
                          g['name']
                              as String,
                      cost:
                          g['cost']
                              as int,
                      dark: dark,
                    ),
                  ),
                ).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// STAT BOX
// ================================================================

class _StatBox extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final bool dark;

  const _StatBox({
    required this.color,
    required this.label,
    required this.value,
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 16,
      ),
      decoration:
          BoxDecoration(
        color:
            AppColors.card(dark),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              color.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            label,
            style: TextStyle(
              color:
                  AppColors
                      .textSecondary(
                dark,
              ),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// GIFT TILE
// ================================================================

class _GiftTile
    extends StatelessWidget {
  final String emoji;
  final String label;
  final int cost;
  final bool dark;

  const _GiftTile({
    required this.emoji,
    required this.label,
    required this.cost,
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 16,
      ),
      decoration:
          BoxDecoration(
        color:
            AppColors.card(dark),
        borderRadius:
            BorderRadius.circular(
          16,
        ),
        border:
            Border.all(
          color:
              AppColors.border(
            dark,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            emoji,
            style:
                const TextStyle(
              fontSize: 26,
            ),
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            label,
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  AppColors
                      .textPrimary(
                dark,
              ),
              fontSize: 12,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
          const SizedBox(
            height: 2,
          ),
          Text(
            '$cost tokens',
            style: TextStyle(
              color:
                  AppColors
                      .textSecondary(
                dark,
              ),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// GIFT PICKER
// ================================================================

class _GiftPickerSheet
    extends StatelessWidget {
  final bool dark;

  const _GiftPickerSheet({
    required this.dark,
  });

  @override
  Widget build(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        20,
        16,
        20,
        28,
      ),
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin:
                  const EdgeInsets.only(
                bottom: 16,
              ),
              decoration:
                  BoxDecoration(
                color:
                    AppColors.border(
                  dark,
                ),
                borderRadius:
                    BorderRadius.circular(
                  2,
                ),
              ),
            ),
          ),

          Text(
            'Send a gift',
            style: TextStyle(
              color:
                  AppColors
                      .textPrimary(
                dark,
              ),
              fontSize: 18,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics:
                const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
            children:
                FirestoreService
                    .giftCatalog
                    .map(
              (g) {
                return GestureDetector(
                  onTap: () =>
                      Navigator.pop(
                    context,
                    g['id'] as String,
                  ),
                  child: Container(
                    decoration:
                        BoxDecoration(
                      color:
                          AppColors.card(
                        dark,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        16,
                      ),
                      border:
                          Border.all(
                        color:
                            AppColors
                                .border(
                          dark,
                        ),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .center,
                      children: [
                        Text(
                          g['emoji']
                              as String,
                          style:
                              const TextStyle(
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(
                          height: 6,
                        ),
                        Text(
                          g['name']
                              as String,
                          style:
                              TextStyle(
                            color:
                                AppColors
                                    .textPrimary(
                              dark,
                            ),
                            fontSize: 12,
                            fontWeight:
                                FontWeight
                                    .w700,
                          ),
                        ),
                        const SizedBox(
                          height: 2,
                        ),
                        Text(
                          '${g['cost']} tokens',
                          style:
                              TextStyle(
                            color:
                                AppColors
                                    .textSecondary(
                              dark,
                            ),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ).toList(),
          ),
        ],
      ),
    );
  }
}