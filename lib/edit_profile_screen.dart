import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;

  File? _pickedPhoto;
  String? _photoUrl;

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
      _photoUrl = data['photo_url']?.toString();
      _isLoading = false;
    });
  }

  Future<void> _pickPhoto() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );

      if (picked == null) return;

      setState(() {
        _pickedPhoto = File(picked.path);
      });
    } catch (e) {
      debugPrint('Pick photo error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open photo library.')),
        );
      }
    }
  }

  Future<String?> _uploadPhotoIfNeeded() async {
    final file = _pickedPhoto;
    if (file == null) return _photoUrl;

    setState(() => _isUploadingPhoto = true);

    try {
      final uid = FirestoreService.currentUserId;
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_photos')
          .child('$uid.jpg');

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      if (mounted) setState(() => _isUploadingPhoto = false);
      return url;
    } catch (e) {
      debugPrint('Photo upload error: $e');
      if (mounted) setState(() => _isUploadingPhoto = false);
      rethrow;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    String? photoUrl;
    try {
      photoUrl = await _uploadPhotoIfNeeded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not upload photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isSaving = false);
      return;
    }

    try {
      await FirestoreService.updateProfile({
        'name': _nameController.text.trim(),
        'city': _cityController.text.trim(),
        if (photoUrl != null) 'photo_url': photoUrl,
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
            onTap: (_isSaving || _isUploadingPhoto) ? null : _saveProfile,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cyan,
                borderRadius: BorderRadius.circular(12),
              ),
              child: (_isSaving || _isUploadingPhoto)
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
                  // Avatar with photo picker
                  Center(
                    child: GestureDetector(
                      onTap: _isUploadingPhoto ? null : _pickPhoto,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.cyan, width: 2.5),
                              color: AppColors.card(dark),
                              image: _pickedPhoto != null
                                  ? DecorationImage(
                                      image: FileImage(_pickedPhoto!),
                                      fit: BoxFit.cover,
                                    )
                                  : (_photoUrl != null && _photoUrl!.isNotEmpty)
                                      ? DecorationImage(
                                          image: NetworkImage(_photoUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                            ),
                            child: (_pickedPhoto == null &&
                                    (_photoUrl == null || _photoUrl!.isEmpty))
                                ? Center(
                                    child: Text(
                                      _nameController.text.isNotEmpty
                                          ? _nameController.text[0]
                                              .toUpperCase()
                                          : 'U',
                                      style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.cyan),
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.cyan,
                                border: Border.all(
                                  color: AppColors.bg(dark),
                                  width: 2,
                                ),
                              ),
                              child: _isUploadingPhoto
                                  ? const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 16,
                                      color: Colors.black,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Center(
                    child: Text(
                      'Tap to change photo',
                      style: TextStyle(
                        color: AppColors.textSecondary(dark),
                        fontSize: 12,
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

                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _isUploadingPhoto)
                          ? null
                          : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: (_isSaving || _isUploadingPhoto)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
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
