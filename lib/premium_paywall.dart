import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'fake_checkout_screen.dart';
import 'firestore_service.dart';

class _PlanOption {
  final String id;
  final String label;
  final String priceLabel;
  final Duration duration;
  final bool bestValue;

  const _PlanOption({
    required this.id,
    required this.label,
    required this.priceLabel,
    required this.duration,
    this.bestValue = false,
  });
}

// Exhibition-demo pricing — the real prices will come from App Store
// Connect once StoreKit is actually configured; these exist only so the
// fake checkout has something to show.
const List<_PlanOption> _plans = [
  _PlanOption(
    id: 'com.hololingo.premium.monthly',
    label: 'Monthly',
    priceLabel: '฿99 / month',
    duration: Duration(days: 30),
  ),
  _PlanOption(
    id: 'com.hololingo.premium.yearly',
    label: 'Yearly',
    priceLabel: '฿999 / year',
    duration: Duration(days: 365),
    bestValue: true,
  ),
];

/// Shared Premium paywall sheet — opened from both the Profile screen's
/// Subscription row and a locked premium topic in Topics, so there's one
/// purchase flow instead of duplicated paywall UI.
///
/// IMPORTANT — this currently goes through FakeCheckoutScreen, not real
/// Apple StoreKit, since there's no approved Developer Program account or
/// App Store Connect products yet (needed for an exhibition demo on a
/// tight timeline). Swap `_confirm` below to call `SubscriptionService.buy`
/// once that's set up — nothing else about this file needs to change.
Future<void> showPremiumPaywall(BuildContext context) {
  final dark = ThemeProvider.isDark(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.card(dark),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _PremiumPaywallSheet(),
  );
}

class _PremiumPaywallSheet extends StatefulWidget {
  const _PremiumPaywallSheet();

  @override
  State<_PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<_PremiumPaywallSheet> {
  _PlanOption _selected = _plans.last;
  bool _purchasing = false;

  Future<void> _buy() async {
    if (_purchasing) return;

    setState(() => _purchasing = true);

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FakeCheckoutScreen(
          title: 'HoloLingo Premium — ${_selected.label}',
          priceLabel: _selected.priceLabel,
          onConfirm: () async {
            await FirestoreService.updateSubscriptionStatus(
              productId: _selected.id,
              expiresAt: DateTime.now().add(_selected.duration),
              transactionId: 'demo-${DateTime.now().millisecondsSinceEpoch}',
              verificationData: 'demo-checkout',
            );
          },
        ),
      ),
    );

    if (!mounted) return;
    setState(() => _purchasing = false);

    if (confirmed == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome to Premium!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border(dark),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'HoloLingo Premium',
              style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock every topic and remove ads.',
              style: TextStyle(
                color: AppColors.textSecondary(dark),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            ...['Unlocked topics', 'Remove ads'].map(
              (text) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.cyan,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: AppColors.textPrimary(dark),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ..._plans.map(_buildPlanOption),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _purchasing ? null : _buy,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _purchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Continue',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanOption(_PlanOption plan) {
    final dark = ThemeProvider.isDark(context);
    final selected = _selected.id == plan.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _purchasing ? null : () => setState(() => _selected = plan),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan.withValues(alpha: 0.10)
                : AppColors.secondary(dark),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.border(dark),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.cyan : AppColors.textSecondary(dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.label,
                          style: TextStyle(
                            color: AppColors.textPrimary(dark),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (plan.bestValue) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cyan,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'BEST VALUE',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.priceLabel,
                      style: TextStyle(
                        color: AppColors.textSecondary(dark),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
