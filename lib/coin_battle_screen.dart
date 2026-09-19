import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'battle_round_screen.dart';
import 'coin_battle_service.dart';
import 'firestore_service.dart';

class CoinBattleScreen extends StatefulWidget {
  const CoinBattleScreen({super.key});

  @override
  State<CoinBattleScreen> createState() => _CoinBattleScreenState();
}

class _CoinBattleScreenState extends State<CoinBattleScreen> {
  int _coins = 0;
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    final profile = await FirestoreService.getProfileOrDefault();
    if (!mounted) return;
    setState(() {
      _coins = (profile['tokens'] as num?)?.toInt() ?? 0;
      _loading = false;
    });
  }

  Future<void> _createChallenge() async {
    final wager = await _askForWager();
    if (wager == null) return;

    if (wager > _coins) {
      _showSnack('You only have $_coins coins.');
      return;
    }

    setState(() => _creating = true);

    try {
      await CoinBattleService.createChallenge(wager: wager);
      _showSnack('Challenge posted — waiting for someone to accept.');
    } catch (e) {
      _showSnack(e is StateError ? e.message : 'Could not create a challenge.');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<int?> _askForWager() async {
    final dark = ThemeProvider.isDark(context);
    final controller = TextEditingController(text: '10');

    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card(dark),
        title: Text(
          'Wager amount',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary(dark)),
          decoration: InputDecoration(
            hintText: 'Coins to wager',
            hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.pop(dialogContext, (value != null && value > 0) ? value : null);
            },
            child: const Text('Post Challenge'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptChallenge(Map<String, dynamic> challenge) async {
    final wager = (challenge['wager'] as num).toInt();

    if (wager > _coins) {
      _showSnack('You only have $_coins coins.');
      return;
    }

    try {
      final battleId = await CoinBattleService.acceptChallenge(challenge);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BattleRoundScreen(battleId: battleId)),
      );
      await _loadBalance();
    } catch (e) {
      _showSnack(e is StateError ? e.message : 'Could not join that battle.');
    }
  }

  Future<void> _cancelChallenge(String challengeId) async {
    await CoinBattleService.cancelChallenge(challengeId);
  }

  Future<void> _openRefill() async {
    final dark = ThemeProvider.isDark(context);

    try {
      final response = await CoinBattleService.queryRefillProduct();

      if (response.productDetails.isEmpty) {
        _showSnack('Coin refill isn\'t available right now.');
        return;
      }

      final product = response.productDetails.first;
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.card(dark),
          title: Text(
            'Refill coins',
            style: TextStyle(color: AppColors.textPrimary(dark)),
          ),
          content: Text(
            'Get ${CoinBattleService.coinRefillAmount} coins for ${product.price}?',
            style: TextStyle(color: AppColors.textSecondary(dark)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Buy'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await CoinBattleService.buyRefill(product);
      }
    } catch (e) {
      _showSnack('Could not reach the store right now.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
          'Coin Battle',
          style: TextStyle(color: AppColors.textPrimary(dark)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : RefreshIndicator(
              onRefresh: _loadBalance,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildBalanceCard(dark),
                  const SizedBox(height: 20),
                  _buildMyChallenges(dark),
                  const SizedBox(height: 20),
                  Text(
                    'Open challenges',
                    style: TextStyle(
                      color: AppColors.textPrimary(dark),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildOpenChallenges(dark),
                ],
              ),
            ),
    );
  }

  Widget _buildBalanceCard(bool dark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on_rounded, color: AppColors.cyan, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_coins coins',
                  style: TextStyle(
                    color: AppColors.textPrimary(dark),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Wager coins in a 1v1 vocab battle',
                  style: TextStyle(
                    color: AppColors.textSecondary(dark),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _openRefill,
            child: const Text('Get more'),
          ),
        ],
      ),
    );
  }

  Widget _buildMyChallenges(bool dark) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CoinBattleService.watchMyOpenChallenges(),
      builder: (context, snapshot) {
        final mine = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _creating ? null : _createChallenge,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: Text(_creating ? 'Posting…' : 'Post a new challenge'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (mine.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...mine.map(
                (c) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border(dark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your open challenge — ${c['wager']} coins',
                          style: TextStyle(color: AppColors.textPrimary(dark)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _cancelChallenge(c['id'] as String),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildOpenChallenges(bool dark) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CoinBattleService.watchOpenChallenges(),
      builder: (context, snapshot) {
        final challenges = snapshot.data ?? [];

        if (challenges.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border(dark)),
            ),
            child: Text(
              'No open challenges right now. Post one to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 13),
            ),
          );
        }

        return Column(
          children: challenges.map((c) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card(dark),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border(dark)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c['wager']} coins',
                      style: TextStyle(
                        color: AppColors.textPrimary(dark),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _acceptChallenge(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Accept'),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
