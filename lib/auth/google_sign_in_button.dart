import 'package:flutter/material.dart';

/// "Continue with Google" button shared by the login and signup screens.
class GoogleSignInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Continue with Google',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
