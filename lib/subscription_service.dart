import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'firestore_service.dart';

/// ============================================================================
/// HOLOLINGO SUBSCRIPTION SERVICE
/// ============================================================================
///
/// Thin wrapper around `package:in_app_purchase` (StoreKit on iOS) for the
/// single "Hololingo Premium" entitlement, sold as a monthly and a yearly
/// auto-renewable subscription.
///
/// IMPORTANT — this is client-only validation. There is no backend verifying
/// receipts or listening for Apple's renewal/cancellation/refund
/// notifications, so `expiresAt` below is only an approximation computed from
/// the purchase date plus the product's nominal duration. This is a known,
/// accepted trade-off for now; a real launch should eventually add
/// server-side validation (Firebase Cloud Function handling App Store Server
/// Notifications) so entitlement stays correct even when the app isn't open.
/// `verificationData` is already captured and stored for exactly that future
/// migration.
class SubscriptionService {
  static const String premiumMonthlyId = 'com.hololingo.premium.monthly';
  static const String premiumYearlyId = 'com.hololingo.premium.yearly';

  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
  };

  static final InAppPurchase _iap = InAppPurchase.instance;

  static StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  static bool _initialized = false;

  /// Purchase errors (declined payment, user cancelled, etc.) for the paywall
  /// UI to surface. Successful purchases aren't pushed through this — screens
  /// re-read the Firestore `subscription` field instead, since entitlement
  /// must be correct after an app restart anyway, not just in memory.
  static final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  // ===========================================================================
  // INIT
  // ===========================================================================

  /// Call once at app startup (not only when the paywall is open), so a
  /// purchase or restored transaction delivered by the store isn't missed.
  static Future<void> init() async {
    if (_initialized) {
      return;
    }

    _initialized = true;

    final available = await _iap.isAvailable();

    if (!available) {
      debugPrint('SubscriptionService: store unavailable.');
      return;
    }

    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        debugPrint('SubscriptionService: purchase stream error: $error');
      },
    );

    // Silently re-assert any still-active subscription from a previous
    // install/relaunch, since nothing server-side is tracking renewals.
    unawaited(restore());
  }

  // ===========================================================================
  // PRODUCTS
  // ===========================================================================

  static Future<ProductDetailsResponse> queryProducts() {
    return _iap.queryProductDetails(_productIds);
  }

  // ===========================================================================
  // PURCHASE / RESTORE
  // ===========================================================================

  static Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Apple requires every app offering subscriptions to expose a way to
  /// restore past purchases (Guideline 3.1.1) — wire this to a visible
  /// "Restore Purchases" action in the paywall, not just call it silently.
  static Future<void> restore() {
    return _iap.restorePurchases();
  }

  // ===========================================================================
  // PURCHASE STREAM HANDLING
  // ===========================================================================

  static Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;

        case PurchaseStatus.error:
          lastError.value = purchase.error?.message ?? 'Purchase failed.';
          debugPrint(
            'SubscriptionService: purchase error: ${purchase.error}',
          );
          break;

        case PurchaseStatus.canceled:
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantEntitlement(purchase);
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  static Future<void> _grantEntitlement(PurchaseDetails purchase) async {
    final transactionDateMillis = int.tryParse(
      purchase.transactionDate ?? '',
    );

    final purchaseTime = transactionDateMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(transactionDateMillis)
        : DateTime.now();

    final duration = purchase.productID == premiumYearlyId
        ? const Duration(days: 365)
        : const Duration(days: 30);

    try {
      await FirestoreService.updateSubscriptionStatus(
        productId: purchase.productID,
        expiresAt: purchaseTime.add(duration),
        transactionId: purchase.purchaseID ?? '',
        verificationData: purchase.verificationData.serverVerificationData,
      );
    } catch (e) {
      debugPrint(
        'SubscriptionService: could not record entitlement: $e',
      );
    }
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  static void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _initialized = false;
  }
}
