import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Checked only so the demo form behaves like a real one; nothing here is
  // sent anywhere (see the note at the top of this file).
  bool get _cardValid =>
      _cardController.text.replaceAll(' ', '').length == 16;

  bool get _expiryValid {
    final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(_expiryController.text);
    if (match == null) return false;
    final month = int.parse(match.group(1)!);
    final year = 2000 + int.parse(match.group(2)!);
    if (month < 1 || month > 12) return false;
    final now = DateTime.now();
    // A card is valid until the end of its expiry month.
    return year > now.year || (year == now.year && month >= now.month);
  }

  bool get _cvvValid => _cvvController.text.length == 3;

  bool get _formFilled =>
      _cardValid &&
      _expiryValid &&
      _cvvValid &&
      _nameController.text.trim().isNotEmpty;

  // Shown once the expiry is fully typed but isn't a real, future date.
  String? get _expiryError =>
      _expiryController.text.length == 5 && !_expiryValid
          ? 'Enter a valid date'
          : null;

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
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                  _CardNumberFormatter(),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      dark,
                      controller: _expiryController,
                      label: 'Expiry',
                      hint: 'MM/YY',
                      keyboardType: TextInputType.number,
                      errorText: _expiryError,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                        _ExpiryDateFormatter(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      dark,
                      controller: _cvvController,
                      label: 'CVV',
                      hint: '123',
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
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
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppColors.textSecondary(dark), fontSize: 11)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: AppColors.textPrimary(dark)),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
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

/// Groups the card number in blocks of four: "4242424242424242" becomes
/// "4242 4242 4242 4242". Runs after digitsOnly, so it only sees digits.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Turns typed digits into MM/YY, adding the slash after the month:
/// "1" → "1", "12" → "12", "128" → "12/8", "1228" → "12/28".
class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text;
    final text = digits.length > 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
