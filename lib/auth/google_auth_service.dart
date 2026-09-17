import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when the user backs out of the Google account picker — callers
/// should treat this as a silent no-op rather than an error to display.
class GoogleSignInCancelled implements Exception {}

class GoogleAuthService {
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // On iOS/macOS this reads the CLIENT_ID from GoogleService-Info.plist,
    // which only exists once Google is enabled as a sign-in provider in the
    // Firebase console and the plist is re-downloaded.
    await GoogleSignIn.instance.initialize();

    _initialized = true;
  }

  static Future<UserCredential> signIn() async {
    await _ensureInitialized();

    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;

      final credential = GoogleAuthProvider.credential(idToken: idToken);

      return FirebaseAuth.instance.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleSignInCancelled();
      }
      rethrow;
    }
  }
}
