import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  String _selectedLanguage = 'English (US)';
  bool _isSaving = false;
  bool _isLoading = true;

  final List<String> _languages = [
    'English (US)',
    'English (UK)',
    'Thai',
    'Japanese',
    'Chinese',
    'Korean',
    'French',
    'Spanish',
    'German',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final data = await DatabaseService.getProfileOrDefault();
    if (!mounted) return;
    setState(() {
      _nameController.text = data['name'] ?? '';
      _cityController.text = data['city'] ?? 'Bangkok';
      _selectedLanguage = data['language'] ?? 'English (US)';
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await FirestoreService.updateProfile({
        'name': _nameController.text.trim(),
        'city': _cityController.text.trim(),
        'language': _selectedLanguage,
      });
    } catch (e) {
      debugPrint('Save profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isSaving = false);
      return;
    }
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeProvider.isDark(context);
    return Scaffold(
      backgroundColor: AppColors.bg(dark),
      appBar: AppBar(
        backgroundColor: AppColors.bg(dark),
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.card(dark),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimary(dark), size: 18),
          ),
        ),
        title: Text('Edit Profile',
            style: TextStyle(
                color: AppColors.textPrimary(dark),
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: _isSaving ? null : _saveProfile,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.cyan, width: 2.5),
                        color: AppColors.card(dark),
                      ),
                      child: Center(
                        child: Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: AppColors.cyan),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  _FieldLabel('Display Name', dark),
                  const SizedBox(height: 8),
                  _InputField(
                    controller: _nameController,
                    hint: 'Your name',
                    icon: Icons.person_rounded,
                    dark: dark,
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 20),

                  _FieldLabel('City', dark),
                  const SizedBox(height: 8),
                  _InputField(
                    controller: _cityController,
                    hint: 'Your city',
                    icon: Icons.location_on_rounded,
                    dark: dark,
                  ),

                  const SizedBox(height: 20),

                  _FieldLabel('Target Language', dark),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.card(dark),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border(dark)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedLanguage,
                        isExpanded: true,
                        dropdownColor: AppColors.card(dark),
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textSecondary(dark)),
                        items: _languages
                            .map((lang) => DropdownMenuItem(
                                  value: lang,
                                  child: Text(lang,
                                      style: TextStyle(
                                          color:
                                              AppColors.textPrimary(dark),
                                          fontSize: 15)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedLanguage = v!),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool dark;
  const _FieldLabel(this.text, this.dark);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: AppColors.textSecondary(dark),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5));
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool dark;
  final void Function(String)? onChanged;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.dark,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(dark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border(dark)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: AppColors.textPrimary(dark), fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary(dark)),
          prefixIcon:
              Icon(icon, color: AppColors.textSecondary(dark), size: 20),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}