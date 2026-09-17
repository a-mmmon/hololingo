import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firestore_service.dart';
import '../app_theme.dart';
import 'google_auth_service.dart';
import 'google_sign_in_button.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signup() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      await cred.user?.updateDisplayName(_nameCtrl.text.trim());

      try {
        await FirestoreService.createUserProfile(
          name: _nameCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
        );
        debugPrint('Profile created for ${cred.user?.uid}');
      } catch (e) {
        debugPrint('Profile creation failed: $e');
        // Still let them in
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = await GoogleAuthService.signIn();

      if (cred.additionalUserInfo?.isNewUser ?? false) {
        await FirestoreService.createUserProfile(
          name: cred.user?.displayName ?? 'User',
          email: cred.user?.email ?? '',
        );
      }
    } on GoogleSignInCancelled {
      // User backed out of the account picker; nothing to show.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not sign in with Google.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white70, size: 20),
                ),
              ),

              const SizedBox(height: 32),

              // Header
              const Text('Create account',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
              const SizedBox(height: 8),
              const Text('Start learning words from the world around you',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),

              const SizedBox(height: 36),

              // Name field
              _Label('Name'),
              const SizedBox(height: 8),
              _Field(controller: _nameCtrl, hint: 'Your name'),
              const SizedBox(height: 16),

              // Email field
              _Label('Email'),
              const SizedBox(height: 8),
              _Field(
                  controller: _emailCtrl,
                  hint: 'you@email.com',
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 16),

              // Password field
              _Label('Password'),
              const SizedBox(height: 8),
              _Field(controller: _passCtrl, hint: '••••••••', obscure: true),

              const SizedBox(height: 28),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),

              // Sign up button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2))
                      : const Text('Create Account',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),

              const SizedBox(height: 20),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),

              const SizedBox(height: 20),

              GoogleSignInButton(
                onPressed: _loading ? null : _continueWithGoogle,
              ),

              const SizedBox(height: 20),

              // Login link
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: RichText(
                    text: const TextSpan(
                      text: 'Already have an account? ',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600));
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  const _Field(
      {required this.controller,
      required this.hint,
      this.obscure = false,
      this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
    );
  }
}
