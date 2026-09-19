import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'daily_battle_screen.dart';
import 'daily_battle_service.dart';

class DailyChallengeQueueScreen extends StatefulWidget {
  final String eventId;

  const DailyChallengeQueueScreen({super.key, required this.eventId});

  @override
  State<DailyChallengeQueueScreen> createState() =>
      _DailyChallengeQueueScreenState();
}

class _DailyChallengeQueueScreenState extends State<DailyChallengeQueueScreen> {
  StreamSubscription<Map<String, dynamic>?>? _queueSub;
  Timer? _timeoutTimer;
  bool _matched = false;
  bool _joining = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _joinOrMatch();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _joinOrMatch() async {
    final date = DailyBattleService.todayKey();

    try {
      final battleId = await DailyBattleService.findOrJoinQueue(
        eventId: widget.eventId,
        date: date,
      );

      if (battleId != null) {
        _goToBattle(battleId);
        return;
      }

      if (!mounted) return;
      setState(() => _joining = false);

      _queueSub = DailyBattleService.watchMyQueueEntry().listen((entry) {
        final battleId = entry?['battle_id'] as String?;
        if (entry?['status'] == 'matched' && battleId != null) {
          _goToBattle(battleId);
        }
      });

      _timeoutTimer = Timer(const Duration(minutes: 3), () async {
        if (_matched || !mounted) return;
        await DailyBattleService.cancelQueue();
        if (!mounted) return;
        setState(() {
          _error = 'No opponent found this time — try again later.';
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Could not join the challenge.';
      });
    }
  }

  void _goToBattle(String battleId) {
    if (_matched || !mounted) return;
    _matched = true;
    _timeoutTimer?.cancel();
    _queueSub?.cancel();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DailyBattleScreen(battleId: battleId),
      ),
    );
  }

  Future<void> _cancel() async {
    _timeoutTimer?.cancel();
    await DailyBattleService.cancelQueue();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_error == null) ...[
                const CircularProgressIndicator(color: AppColors.cyan),
                const SizedBox(height: 20),
                Text(
                  _joining ? 'Joining today\'s challenge…' : 'Looking for an opponent…',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wager: ${DailyBattleService.wager} coins',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ] else ...[
                Icon(Icons.hourglass_empty_rounded,
                    color: AppColors.textSecondary(dark), size: 48),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 14),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Done'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
