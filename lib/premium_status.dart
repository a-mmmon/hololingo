import 'package:cloud_firestore/cloud_firestore.dart';

/// Single source of truth for "is this user currently Premium", read from the
/// `subscription` map written by `SubscriptionService`/`FirestoreService`.
/// Used by both `ProfileScreen` (to show real status) and `TopicsScreen` (to
/// gate premium topics), so the two screens can't drift out of sync.
bool isSubscriptionActive(Map<String, dynamic> profile) {
  final subscription = profile['subscription'];

  if (subscription is! Map || subscription['status'] != 'active') {
    return false;
  }

  final expiresAt = _asDateTime(subscription['expires_at']);

  if (expiresAt == null) {
    return false;
  }

  return expiresAt.isAfter(DateTime.now());
}

/// Returns the subscription's expiry as a [DateTime], or null if there is no
/// active subscription on this profile — handy for showing "renews <date>".
DateTime? subscriptionExpiryDate(Map<String, dynamic> profile) {
  final subscription = profile['subscription'];

  if (subscription is! Map) {
    return null;
  }

  return _asDateTime(subscription['expires_at']);
}

DateTime? _asDateTime(dynamic value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  return null;
}
