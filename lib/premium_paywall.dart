import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'app_theme.dart';
import 'subscription_service.dart';

/// Shared Premium paywall sheet — opened from both the Profile screen's
/// Subscription row and a locked premium topic in Topics, so there's one
/// real purchase flow instead of duplicated paywall UI.
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
  List<ProductDetails> _products = [];
  ProductDetails? _selected;
  bool _loading = true;
  bool _purchasing = false;
  String? _loadError;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  void initState() {
    super.initState();

    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
    );

    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final response = await SubscriptionService.queryProducts();

      if (!mounted) {
        return;
      }

      if (response.error != null || response.productDetails.isEmpty) {
        setState(() {
          _loading = false;
          _loadError = 'Subscriptions are unavailable right now.';
        });
        return;
      }

      final products = response.productDetails;

      setState(() {
        _products = products;
        _selected = products.firstWhere(
          (p) => p.id == SubscriptionService.premiumYearlyId,
          orElse: () => products.first,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = 'Subscriptions are unavailable right now.';
      });
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    final selected = _selected;

    if (selected == null) {
      return;
    }

    for (final purchase in purchases) {
      if (purchase.productID != selected.id) {
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (mounted) {
            Navigator.of(context).pop();
          }
          break;

        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          if (mounted) {
            setState(() => _purchasing = false);
          }
          break;

        case PurchaseStatus.pending:
          break;
      }
    }
  }

  Future<void> _buy() async {
    final product = _selected;

    if (product == null || _purchasing) {
      return;
    }

    setState(() => _purchasing = true);

    try {
      await SubscriptionService.buy(product);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() => _purchasing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start purchase.')),
      );
    }
  }

  Future<void> _restore() async {
    try {
      await SubscriptionService.restore();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Restoring purchases…')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore purchases.')),
      );
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
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
              'Unlock every topic and remove limits on your learning.',
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
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.cyan),
                ),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _loadError!,
                  style: TextStyle(color: AppColors.textSecondary(dark)),
                ),
              )
            else ...[
              ..._products.map(_buildProductOption),
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
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _purchasing ? null : _restore,
                  child: Text(
                    'Restore Purchases',
                    style: TextStyle(color: AppColors.textSecondary(dark)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductOption(ProductDetails product) {
    final dark = ThemeProvider.isDark(context);
    final selected = _selected?.id == product.id;
    final isYearly = product.id == SubscriptionService.premiumYearlyId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _purchasing ? null : () => setState(() => _selected = product),
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
                          isYearly ? 'Yearly' : 'Monthly',
                          style: TextStyle(
                            color: AppColors.textPrimary(dark),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (isYearly) ...[
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
                      isYearly
                          ? '${product.price} / year'
                          : '${product.price} / month',
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
