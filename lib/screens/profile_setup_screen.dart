import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/cached_avatar.dart';
import 'package:image_picker/image_picker.dart';
import 'crop_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../widgets/app_notify.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String role;
  final String? firstName;
  final String? lastName;
  final String? gender;
  final String? englishLevel;
  final String? profileImageUrl;

  const ProfileSetupScreen({
    super.key,
    required this.role,
    this.firstName,
    this.lastName,
    this.gender,
    this.englishLevel,
    this.profileImageUrl,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  File? _photo;
  String? _networkImageUrl;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _displayNameController = TextEditingController();
  String? _englishLevel;
  String? _gender;
  String? _ieltsScore;
  String? _certificateFileName;
  bool _submitting = false;

  bool get _isTutor => widget.role == 'tutor';

  static const _reverseLevelMap = {
    'beginner': 'Beginner (A1)',
    'elementary': 'Elementary (A2)',
    'pre-intermediate': 'Pre-Intermediate (B1)',
    'intermediate': 'Intermediate (B1+)',
    'upper-intermediate': 'Upper-Intermediate (B2)',
    'advanced': 'Advanced (C1)',
    'Ielts': 'IELTS Preparation',
  };

  @override
  void initState() {
    super.initState();
    if (widget.firstName != null) {
      _firstNameController.text = widget.firstName!;
    }
    if (widget.lastName != null) {
      _lastNameController.text = widget.lastName!;
    }
    _gender = widget.gender;
    _englishLevel = _reverseLevelMap[widget.englishLevel];
    _networkImageUrl = widget.profileImageUrl;
  }

  static const _levelMap = {
    'Beginner (A1)': 'beginner',
    'Elementary (A2)': 'elementary',
    'Pre-Intermediate (B1)': 'pre-intermediate',
    'Intermediate (B1+)': 'intermediate',
    'Upper-Intermediate (B2)': 'upper-intermediate',
    'Advanced (C1)': 'advanced',
    'IELTS Preparation': 'Ielts',
  };

  bool get _canSubmit {
    if (_firstNameController.text.trim().isEmpty) return false;
    if (_lastNameController.text.trim().isEmpty) return false;
    if (_gender == null) return false;
    if (_isTutor) {
      return _displayNameController.text.trim().isNotEmpty &&
          _ieltsScore != null;
    }
    return _englishLevel != null;
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    final cropped = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          imageFile: File(image.path),
          aspectRatio: 3 / 2,
        ),
      ),
    );

    if (cropped != null && mounted) {
      setState(() => _photo = cropped);
    }
  }

  Future<void> _pickCertificate() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result != null && mounted) {
      setState(() => _certificateFileName = result.files.single.name);
    }
  }

  void _openDropdown({
    required String title,
    required List<String> options,
    required String? selected,
    required void Function(String) onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DropdownSheet(
        title: title,
        options: options,
        selected: selected,
        onSelect: (val) {
          Navigator.pop(context);
          setState(() => onSelect(val));
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final body = <String, dynamic>{
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'gender': _gender,
      };

      if (_isTutor) {
        body['ielts_score'] = double.tryParse(_ieltsScore ?? '') ?? 0;
        body['experience'] = 0;
      } else {
        body['englishLevel'] = _levelMap[_englishLevel] ?? _englishLevel;
      }

      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        final ext = _photo!.path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        body['profile_image'] = 'data:$mime;base64,${base64Encode(bytes)}';
      }

      final path = _isTutor ? '/tutor/profile/' : '/student/profile/';
      await ApiService.put(path, body);

      if (!mounted) return;
      AppNotify.show(context,
        message: 'Profile updated successfully',
        type: NotifyType.success,
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Color(0xFF272942),
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text(
            'Profile Setup',
            style: TextStyle(
              color: Color(0xFF272942),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),

                      // Avatar
                      GestureDetector(
                        onTap: _pickPhoto,
                        child: _photo != null
                            ? CircleAvatar(
                                radius: 55,
                                backgroundImage: FileImage(_photo!),
                              )
                            : CachedAvatar(imageUrl: _networkImageUrl, size: 110),
                      ),

                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        onPressed: _pickPhoto,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF272942),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text(
                          'Add a photo',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // First name
                      _ProfileTextField(
                        controller: _firstNameController,
                        hint: 'First name',
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 12),

                      // Last name
                      _ProfileTextField(
                        controller: _lastNameController,
                        hint: 'Last name',
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 12),

                      // Gender
                      _DropdownField(
                        hint: 'Gender',
                        value: _gender,
                        onTap: () => _openDropdown(
                          title: 'Gender',
                          options: ['Male', 'Female'],
                          selected: _gender,
                          onSelect: (v) => _gender = v,
                        ),
                      ),

                      const SizedBox(height: 12),

                      if (_isTutor) ...[
                        _ProfileTextField(
                          controller: _displayNameController,
                          hint: 'Tutor display name',
                          maxLength: 15,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 12),

                        _DropdownField(
                          hint: 'IELTS score',
                          value: _ieltsScore,
                          valueColor: const Color(0xFFE53935),
                          valueBadge: true,
                          showArrow: false,
                          onTap: () => _openDropdown(
                            title: 'IELTS score',
                            options: ['7.0', '7.5', '8.0', '8.5', '9.0'],
                            selected: _ieltsScore,
                            onSelect: (v) => _ieltsScore = v,
                          ),
                        ),

                        const SizedBox(height: 12),

                        if (_certificateFileName != null)
                          _UploadedFileCard(
                            name: _certificateFileName!,
                            onRemove: () =>
                                setState(() => _certificateFileName = null),
                          )
                        else
                          _UploadButton(onTap: _pickCertificate),
                      ] else ...[
                        _DropdownField(
                          hint: 'English level',
                          value: _englishLevel,
                          onTap: () => _openDropdown(
                            title: 'English level',
                            options: _levelMap.keys.toList(),
                            selected: _englishLevel,
                            onSelect: (v) => _englishLevel = v,
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),

              // Done button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSubmit && !_submitting ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF272942),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFFAAAAAA),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Text field ────────────────────────────────────────────────────────────────

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final void Function(String)? onChanged;

  const _ProfileTextField({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      inputFormatters: maxLength != null
          ? [LengthLimitingTextInputFormatter(maxLength!)]
          : null,
      style: const TextStyle(
        fontSize: 15,
        color: Color(0xFF272942),
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 15,
          color: Color(0xFFBBBBBB),
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: const Color(0xFFF2F2F2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        counterText: '',
        suffixText: maxLength != null
            ? '${controller.text.length}/$maxLength'
            : null,
        suffixStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFFAAAAAA),
        ),
      ),
    );
  }
}

// ─── Dropdown field ────────────────────────────────────────────────────────────

class _DropdownField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final Color valueColor;
  final bool showArrow;
  final bool valueBadge;

  const _DropdownField({
    required this.hint,
    this.value,
    required this.onTap,
    this.valueColor = const Color(0xFF272942),
    this.showArrow = true,
    this.valueBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(
              hint,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFFBBBBBB),
                fontWeight: FontWeight.w400,
              ),
            ),
            const Spacer(),
            if (value != null)
              valueBadge
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        value!,
                        style: TextStyle(
                          fontSize: 15,
                          color: valueColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : Text(
                      value!,
                      style: TextStyle(
                        fontSize: 15,
                        color: valueColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            if (showArrow) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFFAAAAAA),
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Upload button ─────────────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final VoidCallback onTap;

  const _UploadButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF272942), width: 2),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_outlined, color: Color(0xFF272942), size: 18),
            SizedBox(width: 8),
            Text(
              'Upload IELTS certificate',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF272942),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Uploaded file card ────────────────────────────────────────────────────────

class _UploadedFileCard extends StatelessWidget {
  final String name;
  final VoidCallback onRemove;

  const _UploadedFileCard({required this.name, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF272942),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1E2035),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'The file has been uploaded!',
                  style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dropdown bottom sheet ─────────────────────────────────────────────────────

class _DropdownSheet extends StatelessWidget {
  final String title;
  final List<String> options;
  final String? selected;
  final void Function(String) onSelect;

  const _DropdownSheet({
    required this.title,
    required this.options,
    this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),

        // Handle bar
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFDDDDDD),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        const SizedBox(height: 16),

        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF272942),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.close,
                  color: Color(0xFF272942),
                  size: 22,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        const Divider(height: 1, color: Color(0xFFEEEEEE)),

        // Options
        ...options.map((opt) {
          final isSelected = opt == selected;
          return InkWell(
            onTap: () => onSelect(opt),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Text(
                    opt,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF272942),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? const Color(0xFFF5C542)
                          : Colors.transparent,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFF5C542)
                            : const Color(0xFFCCCCCC),
                        width: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }
}
