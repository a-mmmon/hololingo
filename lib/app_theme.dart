import 'package:flutter/material.dart';

// ── Color Tokens ──────────────────────────────────────────────────────────────
class AppColors {
  // Dark mode
  static const darkBg        = Color(0xFF0F0F13);
  static const darkCard      = Color(0xFF1C1C22);
  static const darkSecondary = Color(0xFF26262E);
  static const darkBorder    = Color(0xFF2E2E38);

  // Light mode
  static const lightBg        = Color(0xFFF5F7FA);
  static const lightCard      = Color(0xFFFFFFFF);
  static const lightSecondary = Color(0xFFEEF1F6);
  static const lightBorder    = Color(0xFFD8DEE9);

  // Brand
  static const cyan   = Color(0xFF00C4C4);
  static const flame  = Color(0xFFFF6B2B);
  static const amber  = Color(0xFFFFB300);
  static const purple = Color(0xFF7C5CBF);

  // Semantic
  static const correctGreenDark  = Color(0xFF0D2E1A);
  static const wrongRedDark      = Color(0xFF2E0D0D);
  static const correctGreenLight = Color(0xFFE8F5E9);
  static const wrongRedLight     = Color(0xFFFFEBEE);

  static const scannerCorner = cyan;

  // ── Theme-aware getters ───────────────────────────────────────────────────
  static Color bg(bool isDark)        => isDark ? darkBg        : lightBg;
  static Color card(bool isDark)      => isDark ? darkCard      : lightCard;
  static Color secondary(bool isDark) => isDark ? darkSecondary : lightSecondary;
  static Color border(bool isDark)    => isDark ? darkBorder    : lightBorder;

  static Color textPrimary(bool isDark)   => isDark ? const Color(0xFFFFFFFF) : const Color(0xFF111827);
  static Color textSecondary(bool isDark) => isDark ? const Color(0xFF8A8A9A) : const Color(0xFF6B7280);
  static Color textTertiary(bool isDark)  => isDark ? const Color(0xFF555566) : const Color(0xFF9CA3AF);

  static Color correctGreen(bool isDark) => isDark ? correctGreenDark : correctGreenLight;
  static Color wrongRed(bool isDark)     => isDark ? wrongRedDark     : wrongRedLight;

  static Color correctText(bool isDark)  => isDark ? Colors.greenAccent : const Color(0xFF1B5E20);
  static Color wrongText(bool isDark)    => isDark ? Colors.redAccent   : const Color(0xFFB71C1C);

  static Color divider(bool isDark) => isDark ? Colors.white10 : const Color(0xFFE5E7EB);
  static Color shadow(bool isDark)  => isDark ? Colors.transparent : const Color(0x0A000000);
}

// ── Theme Notifier ────────────────────────────────────────────────────────────
class ThemeNotifier extends ChangeNotifier {
  bool _isDark = true;

  bool get isDark => _isDark;

  void toggle() {
    _isDark = !_isDark;
    notifyListeners();
  }

  void setDark(bool value) {
    if (_isDark != value) {
      _isDark = value;
      notifyListeners();
    }
  }

  ThemeData get themeData => _isDark ? _darkTheme : _lightTheme;

  static final _darkTheme = ThemeData.dark().copyWith(
    scaffoldBackgroundColor: AppColors.darkBg,
    colorScheme: const ColorScheme.dark(primary: AppColors.cyan),
  );

  static final _lightTheme = ThemeData.light().copyWith(
    scaffoldBackgroundColor: AppColors.lightBg,
    colorScheme: const ColorScheme.light(primary: AppColors.cyan),
  );
}

// ── Theme Provider ────────────────────────────────────────────────────────────
class ThemeProvider extends InheritedNotifier<ThemeNotifier> {
  const ThemeProvider({
    super.key,
    required ThemeNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ThemeNotifier of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(provider != null, 'ThemeProvider not found in widget tree');
    return provider!.notifier!;
  }

  static bool isDark(BuildContext context) => of(context).isDark;
}

// ── Bottom Nav ────────────────────────────────────────────────────────────────
class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);

    const items = [
      _NavItem(Icons.home_rounded, 'Home'),
      _NavItem(Icons.qr_code_scanner_rounded, 'Scan'),
      _NavItem(Icons.auto_stories_rounded, 'Review'),
      _NavItem(Icons.bookmark_rounded, 'Vocab'),
      _NavItem(Icons.person_rounded, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        border: Border(
            top: BorderSide(color: AppColors.border(dark), width: 1)),
        boxShadow: dark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                )
              ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: selected
                            ? AppColors.cyan
                            : AppColors.textSecondary(dark),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: selected
                              ? AppColors.cyan
                              : AppColors.textSecondary(dark),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}