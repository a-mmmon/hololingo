import 'package:flutter/material.dart';

import 'app_theme.dart';

/// ============================================================================
/// FAKE CHECKOUT SCREEN — exhibition/demo stand-in for real Apple IAP
/// ============================================================================
///
/// Real StoreKit purchases need an approved Apple Developer Program account
/// and products configured in App Store Connect — neither exists yet. This
/// screen collects card-shaped input for visual realism only: nothing typed
/// here is validated, sent anywhere, or stored. Tapping Pay just waits a
/// moment (so it doesn't feel instant/fake) then calls [onConfirm], which is
/// whatever the real purchase would have granted. Swap the call sites back
/// to the real `in_app_purchase` flow once StoreKit is actually set up —
/// this file can be deleted at that point, nothing else depends on it.
class FakeCheckoutScreen extends StatefulWidget {
  final String title;
  final String priceLabel;
  final Future<void> Function() onConfirm;

  const FakeCheckoutScreen({
    super.key,
    required this.title,
    required this.priceLabel,
    required this.onConfirm,
  });

  @override
  State<FakeCheckoutScreen> createState() => _FakeCheckoutScreenState();
}

class _FakeCheckoutScreenState extends State<FakeCheckoutScreen> {
  final _cardController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _nameController = TextEditingController();

  bool _processing = false;

  @override
  void dispose() {
    _cardController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _formFilled =>
      _cardController.text.trim().isNotEmpty &&
      _expiryController.text.trim().isNotEmpty &&
      _cvvController.text.trim().isNotEmpty &&
      _nameController.text.trim().isNotEmpty;

  Future<void> _pay() async {
    if (_processing || !_formFilled) return;

    setState(() => _processing = true);

    await Future<void>.delayed(const Duration(milliseconds: 900));

    try {
      await widget.onConfirm();
    } finally {
      if (mounted) setState(() => _processing = false);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
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
        title: Text('Checkout', style: TextStyle(color: AppColors.textPrimary(dark))),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card(dark),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border(dark)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              color: AppColors.textPrimary(dark),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.priceLabel,
                            style: const TextStyle(
                              color: AppColors.cyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.credit_card_rounded, color: AppColors.textSecondary(dark)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'CARD DETAILS',
                style: TextStyle(
                  color: AppColors.textSecondary(dark),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              _field(
                dark,
                controller: _cardController,
                label: 'Card number',
                hint: '4242 4242 4242 4242',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(dark, controller: _expiryController, label: 'Expiry', hint: 'MM/YY'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      dark,
                      controller: _cvvController,
                      label: 'CVV',
                      hint: '123',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _field(dark, controller: _nameController, label: 'Name on card', hint: 'Jane Doe'),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_processing || !_formFilled) ? null : _pay,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.secondary(dark),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'Pay ${widget.priceLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Demo checkout — no real charge.',
                  style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    bool dark, {
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: AppColors.textPrimary(dark)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppColors.textSecondary(dark).withValues(alpha: 0.6)),
            filled: true,
            fillColor: AppColors.card(dark),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.border(dark)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.border(dark)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
