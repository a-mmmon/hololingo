import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';

/// A single-player, no-groups event challenge: scan a target number of
/// words during the event window, then claim the reward once. Replaces
/// the old group/lobby/invite flow with something a single user can
/// complete on their own.
class ScanChallengeScreen extends StatefulWidget {
  final String eventId;

  const ScanChallengeScreen({super.key, required this.eventId});

  @override
  State<ScanChallengeScreen> createState() => _ScanChallengeScreenState();
}

class _ScanChallengeScreenState extends State<ScanChallengeScreen> {
  bool _loading = true;
  bool _claiming = false;
  bool _claimed = false;
  String? _error;
  Map<String, dynamic>? _event;
  int _scanCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final event = await FirestoreService.getEventDefinition(widget.eventId);

      if (event == null) {
        setState(() {
          _error = 'This challenge is no longer available.';
          _loading = false;
        });
        return;
      }

      final startAt = _toDate(event['start_at']) ?? DateTime.now();
      final endAt = _toDate(event['end_at']) ?? DateTime.now();

      final results = await Future.wait([
        FirestoreService.getEventScanCount(startAt: startAt, endAt: endAt),
        FirestoreService.hasClaimedEvent(widget.eventId),
      ]);

      if (!mounted) return;

      setState(() {
        _event = event;
        _scanCount = results[0] as int;
        _claimed = results[1] as bool;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this challenge.';
        _loading = false;
      });
    }
  }

  int get _target => (_event?['target_count'] as num?)?.toInt() ?? 10;
  int get _rewardXp => (_event?['reward_xp'] as num?)?.toInt() ?? 0;
  int get _rewardTokens => (_event?['reward_tokens'] as num?)?.toInt() ?? 0;
  bool get _completed => _scanCount >= _target;

  Future<void> _claim() async {
    setState(() => _claiming = true);

    final newlyClaimed = await FirestoreService.claimEventReward(
      eventId: widget.eventId,
      xp: _rewardXp,
      tokens: _rewardTokens,
    );

    if (!mounted) return;

    setState(() {
      _claiming = false;
      _claimed = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newlyClaimed
              ? 'Reward claimed: +$_rewardXp XP, +$_rewardTokens tokens!'
              : 'Already claimed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary(dark)),
        title: Text(
          _event?['name']?.toString() ?? 'Scan Challenge',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                )
              : _buildContent(dark),
    );
  }

  Widget _buildContent(bool dark) {
    final progress = _target == 0 ? 0.0 : (_scanCount / _target).clamp(0.0, 1.0);
    final theme = (_event?['theme'] as String?)?.trim();
    final description = (_event?['description'] as String?)?.trim();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (theme != null && theme.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                theme,
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
          ],
          Text(
            'Scan $_target words to complete the challenge',
            style: TextStyle(
              color: AppColors.textPrimary(dark),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: AppColors.secondary(dark),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_scanCount / $_target scanned',
            style: TextStyle(
              color: AppColors.textSecondary(dark),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          if (_rewardXp > 0 || _rewardTokens > 0)
            Row(
              children: [
                if (_rewardXp > 0) _rewardChip('★ $_rewardXp XP'),
                if (_rewardXp > 0 && _rewardTokens > 0)
                  const SizedBox(width: 10),
                if (_rewardTokens > 0) _rewardChip('◆ $_rewardTokens tokens'),
              ],
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _claimed || !_completed || _claiming ? null : _claim,
              style: ElevatedButton.styleFrom(
                backgroundColor: _claimed ? Colors.green : const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.secondary(dark),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _claimed
                    ? '✓ Reward Claimed'
                    : _completed
                        ? (_claiming ? 'Claiming…' : 'Claim Reward')
                        : 'Keep scanning to unlock',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.cyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.cyan,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
