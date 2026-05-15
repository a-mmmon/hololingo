import 'package:flutter/material.dart';

// ── Shared Design Tokens ──────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF0A0E1A);
  static const surface = Color(0xFF141929);
  static const card = Color(0xFF1C2237);
  static const cyan = Color(0xFF00E5FF);
  static const cyanDim = Color(0xFF00B8CC);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8A93B2);
  static const scannerCorner = Color(0xFF00E5FF);
  static const navBg = Color(0xFF0D1120);
  static const correctGreen = Color(0xFF1B5E20);
  static const wrongRed = Color(0xFF7F0000);
  static const flame = Color(0xFFFF8C00);
}

// ── Nav Items ─────────────────────────────────────────────────────────────────
class NavItem {
  final IconData icon;
  final String label;
  const NavItem(this.icon, this.label);
}

const navItems = [
  NavItem(Icons.home_rounded, 'Home'),
  NavItem(Icons.qr_code_scanner_rounded, 'Scan'),
  NavItem(Icons.auto_stories_rounded, 'Review'),
  NavItem(Icons.record_voice_over_rounded, 'Vocal'),
  NavItem(Icons.person_rounded, 'Profile'),
];

// ── Bottom Navigation Bar (PUBLIC) ────────────────────────────────────────────
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: AppColors.navBg,
        border: Border(top: BorderSide(color: Colors.white10, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(navItems.length, (i) {
          final item = navItems[i];
          final active = i == currentIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (active)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cyan,
                      ),
                      child: Icon(item.icon, color: Colors.black, size: 22),
                    )
                  else
                    Icon(item.icon, color: Colors.white30, size: 24),
                  SizedBox(height: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: active ? AppColors.cyan : Colors.white30,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}