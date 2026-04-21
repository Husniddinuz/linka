import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/cached_avatar.dart';
import 'crop_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../widgets/app_notify.dart';
import 'home_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  final String role;
  final Map<String, dynamic>? profile;

  const ProfileSetupScreen({
    super.key,
    required this.role,
    this.profile,
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
  final _experienceController = TextEditingController();
  final _aboutMeController = TextEditingController();
  final _price20Controller = TextEditingController();
  final _price30Controller = TextEditingController();
  final _price45Controller = TextEditingController();
  String? _englishLevel;
  String? _gender;
  String? _readingScore;
  String? _listeningScore;
  String? _writingScore;
  String? _speakingScore;
  File? _certificateFile;
  String? _certificateFileName;
  String? _existingCertificateUrl;
  File? _introVideo;
  String? _introVideoName;
  bool _submitting = false;
  double _progress = 0;

  static const List<String> _bandOptions = ['7.0', '7.5', '8.0', '8.5', '9.0'];

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
    final p = widget.profile;
    if (p == null) return;

    _firstNameController.text = p['first_name']?.toString() ?? '';
    _lastNameController.text = p['last_name']?.toString() ?? '';
    _gender = p['gender'] as String?;
    _networkImageUrl = p['profile_image'] as String?;

    if (_isTutor) {
      _readingScore = _formatBand(p['reading_score']);
      _listeningScore = _formatBand(p['listening_score']);
      _writingScore = _formatBand(p['writing_score']);
      _speakingScore = _formatBand(p['speaking_score']);
      _experienceController.text = p['experience']?.toString() ?? '';
      _aboutMeController.text = p['about_me']?.toString() ?? '';
      _displayNameController.text = p['display_name']?.toString() ?? '';

      final prices = p['lesson_prices'];
      if (prices is List) {
        for (final raw in prices) {
          if (raw is! Map) continue;
          final mins = (raw['duration_minutes'] as num?)?.toInt();
          final price = _formatPrice(raw['price']);
          if (price.isEmpty) continue;
          if (mins == 20) _price20Controller.text = price;
          if (mins == 30) _price30Controller.text = price;
          if (mins == 45) _price45Controller.text = price;
        }
      }

      final certUrl = (p['ielts_certificate'] ?? p['certificate_image']) as String?;
      if (certUrl != null && certUrl.isNotEmpty) {
        _existingCertificateUrl = certUrl;
        _certificateFileName = _fileNameFromUrl(certUrl);
      }
      final videoUrl = p['intro_video'] as String?;
      if (videoUrl != null && videoUrl.isNotEmpty) {
        _introVideoName = _fileNameFromUrl(videoUrl);
      }
    } else {
      _englishLevel = _reverseLevelMap[p['englishLevel'] as String?];
    }
  }

  static String? _formatBand(dynamic v) {
    if (v == null) return null;
    final n = v is num ? v.toDouble() : double.tryParse(v.toString());
    if (n == null) return null;
    return n.toStringAsFixed(1);
  }

  static String _formatPrice(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    final dot = s.indexOf('.');
    return dot >= 0 ? s.substring(0, dot) : s;
  }

  static String _fileNameFromUrl(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    return seg.isEmpty ? url : seg.last;
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

  String? get _computedIelts {
    if (_readingScore == null ||
        _listeningScore == null ||
        _writingScore == null ||
        _speakingScore == null) {
      return null;
    }
    final avg = (double.parse(_readingScore!) +
            double.parse(_listeningScore!) +
            double.parse(_writingScore!) +
            double.parse(_speakingScore!)) /
        4;
    return ((avg * 2).round() / 2).toStringAsFixed(1);
  }

  bool get _canSubmit {
    if (_firstNameController.text.trim().isEmpty) return false;
    if (_lastNameController.text.trim().isEmpty) return false;
    if (_gender == null) return false;
    if (_isTutor) {
      final hasPhoto = _photo != null ||
          (_networkImageUrl != null && _networkImageUrl!.isNotEmpty);
      final hasCertificate = _certificateFile != null ||
          (_existingCertificateUrl != null &&
              _existingCertificateUrl!.isNotEmpty);
      return _computedIelts != null &&
          _experienceController.text.trim().isNotEmpty &&
          hasPhoto &&
          hasCertificate;
    }
    return _englishLevel != null;
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;

    final cropped = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => CropScreen(
          imageFile: File(path),
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
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) return;
      setState(() {
        _certificateFile = File(path);
        _certificateFileName = picked.name;
      });
    }
  }

  Future<void> _pickIntroVideo() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _introVideo = File(picked.path);
      _introVideoName = picked.name;
    });
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
    setState(() {
      _submitting = true;
      _progress = 0;
    });

    try {
      final body = <String, dynamic>{
        'first_name': _firstNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'gender': _gender,
      };

      if (_isTutor) {
        body['ielts_score'] = double.tryParse(_computedIelts ?? '') ?? 0;
        body['experience'] = _experienceController.text.trim();
        if (_readingScore != null) {
          body['reading_score'] = double.parse(_readingScore!);
        }
        if (_listeningScore != null) {
          body['listening_score'] = double.parse(_listeningScore!);
        }
        if (_writingScore != null) {
          body['writing_score'] = double.parse(_writingScore!);
        }
        if (_speakingScore != null) {
          body['speaking_score'] = double.parse(_speakingScore!);
        }
        final aboutMe = _aboutMeController.text.trim();
        if (aboutMe.isNotEmpty) body['about_me'] = aboutMe;
        final displayName = _displayNameController.text.trim();
        if (displayName.isNotEmpty) body['display_name'] = displayName;
        final prices = <Map<String, dynamic>>[];
        void addPrice(int minutes, TextEditingController c) {
          final raw = c.text.trim();
          if (raw.isEmpty) return;
          final amount = int.tryParse(raw);
          if (amount == null) return;
          prices.add({
            'duration_minutes': minutes,
            'price': '$amount.00',
          });
        }
        addPrice(20, _price20Controller);
        addPrice(30, _price30Controller);
        addPrice(45, _price45Controller);
        if (prices.isNotEmpty) body['prices'] = prices;
      } else {
        body['englishLevel'] = _levelMap[_englishLevel] ?? _englishLevel;
      }

      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        final ext = _photo!.path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        body['profile_image'] = 'data:$mime;base64,${base64Encode(bytes)}';
      }

      if (_isTutor && _certificateFile != null) {
        final bytes = await _certificateFile!.readAsBytes();
        final ext = _certificateFile!.path.split('.').last.toLowerCase();
        final mime = ext == 'pdf'
            ? 'application/pdf'
            : ext == 'png'
                ? 'image/png'
                : 'image/jpeg';
        body['certificate_image'] = 'data:$mime;base64,${base64Encode(bytes)}';
      }

      if (_isTutor && _introVideo != null) {
        final bytes = await _introVideo!.readAsBytes();
        final ext = _introVideo!.path.split('.').last.toLowerCase();
        final mime = ext == 'mov'
            ? 'video/quicktime'
            : ext == 'webm'
                ? 'video/webm'
                : 'video/mp4';
        body['intro_video'] = 'data:$mime;base64,${base64Encode(bytes)}';
      }

      final path = _isTutor ? '/tutor/profile/' : '/student/profile/';
      final hasMedia = _photo != null ||
          (_isTutor && (_certificateFile != null || _introVideo != null));
      await ApiService.put(
        path,
        body,
        onProgress: hasMedia
            ? (sent, total) {
                if (!mounted || total <= 0) return;
                final next = sent / total;
                if ((next - _progress).abs() < 0.01 && next < 1.0) return;
                setState(() => _progress = next);
              }
            : null,
      );

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
    _experienceController.dispose();
    _aboutMeController.dispose();
    _price20Controller.dispose();
    _price30Controller.dispose();
    _price45Controller.dispose();
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

                      _PhotoPicker(
                        photo: _photo,
                        networkImageUrl: _networkImageUrl,
                        onTap: _pickPhoto,
                      ),

                      const SizedBox(height: 28),

                      const _SectionHeader('Personal info'),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: _ProfileTextField(
                              controller: _firstNameController,
                              hint: 'First name',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _ProfileTextField(
                              controller: _lastNameController,
                              hint: 'Last name',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

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

                      if (_isTutor) ...[
                        const SizedBox(height: 12),

                        _ProfileTextField(
                          controller: _displayNameController,
                          hint: 'Tutor display name',
                          maxLength: 15,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 28),

                        const _SectionHeader('IELTS scores'),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField(
                                hint: 'Reading',
                                value: _readingScore,
                                onTap: () => _openDropdown(
                                  title: 'Reading score',
                                  options: _bandOptions,
                                  selected: _readingScore,
                                  onSelect: (v) => _readingScore = v,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField(
                                hint: 'Listening',
                                value: _listeningScore,
                                onTap: () => _openDropdown(
                                  title: 'Listening score',
                                  options: _bandOptions,
                                  selected: _listeningScore,
                                  onSelect: (v) => _listeningScore = v,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _DropdownField(
                                hint: 'Writing',
                                value: _writingScore,
                                onTap: () => _openDropdown(
                                  title: 'Writing score',
                                  options: _bandOptions,
                                  selected: _writingScore,
                                  onSelect: (v) => _writingScore = v,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _DropdownField(
                                hint: 'Speaking',
                                value: _speakingScore,
                                onTap: () => _openDropdown(
                                  title: 'Speaking score',
                                  options: _bandOptions,
                                  selected: _speakingScore,
                                  onSelect: (v) => _speakingScore = v,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        _OverallScoreCard(value: _computedIelts),

                        const SizedBox(height: 28),

                        const _SectionHeader('About you'),
                        const SizedBox(height: 12),

                        _ProfileTextField(
                          controller: _experienceController,
                          hint: 'Experience',
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 12),

                        _ProfileTextField(
                          controller: _aboutMeController,
                          hint: 'Tell students a bit about yourself…',
                          maxLines: 4,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 28),

                        const _SectionHeader('Lesson pricing',
                            trailing: 'UZS'),
                        const SizedBox(height: 12),

                        _PriceRow(
                          minutes: 20,
                          controller: _price20Controller,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _PriceRow(
                          minutes: 30,
                          controller: _price30Controller,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        _PriceRow(
                          minutes: 45,
                          controller: _price45Controller,
                          onChanged: (_) => setState(() {}),
                        ),

                        const SizedBox(height: 28),

                        const _SectionHeader('Documents'),
                        const SizedBox(height: 12),

                        if (_certificateFileName != null)
                          _UploadedFileCard(
                            name: _certificateFileName!,
                            onRemove: () => setState(() {
                              _certificateFile = null;
                              _certificateFileName = null;
                            }),
                          )
                        else
                          _UploadButton(
                            onTap: _pickCertificate,
                            label: 'Upload IELTS certificate',
                            icon: Icons.description_outlined,
                          ),

                        const SizedBox(height: 10),

                        if (_introVideoName != null)
                          _UploadedFileCard(
                            name: _introVideoName!,
                            onRemove: () => setState(() {
                              _introVideo = null;
                              _introVideoName = null;
                            }),
                          )
                        else
                          _UploadButton(
                            onTap: _pickIntroVideo,
                            label: 'Upload intro video',
                            icon: Icons.videocam_outlined,
                          ),
                      ] else ...[
                        const SizedBox(height: 12),
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
                    onPressed: _submitting
                        ? () {}
                        : (_canSubmit ? _submit : null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF272942),
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFFAAAAAA),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: (_progress == 0 || _progress >= 1.0)
                                      ? null
                                      : _progress,
                                  color: Colors.white,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _progress == 0
                                    ? 'Preparing…'
                                    : _progress >= 1.0
                                        ? 'Processing…'
                                        : 'Uploading ${(_progress * 100).round()}%',
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
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
  final int maxLines;
  final void Function(String)? onChanged;

  const _ProfileTextField({
    required this.controller,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
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

  const _DropdownField({
    required this.hint,
    this.value,
    required this.onTap,
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
              Text(
                value!,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF272942),
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFAAAAAA),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upload button ─────────────────────────────────────────────────────────────

class _UploadButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;

  const _UploadButton({
    required this.onTap,
    this.label = 'Upload file',
    this.icon = Icons.file_upload_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF272942).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF272942), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF272942),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap to choose a file',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFFCCCCCC),
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dotted border container ───────────────────────────────────────────────────

class DottedBorderBox extends StatelessWidget {
  final Widget child;

  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DottedBorderPainter(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(color: const Color(0xFFFCFCFD), child: child),
      ),
    );
  }
}

class _DottedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDDDDDD)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 5.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, end.clamp(0, metric.length)),
          paint,
        );
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Overall score card ────────────────────────────────────────────────────────

class _OverallScoreCard extends StatelessWidget {
  final String? value;

  const _OverallScoreCard({required this.value});

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF272942),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall IELTS',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Auto-calculated from sub-scores',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFFAAAAAA),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              hasValue ? value! : '—',
              style: TextStyle(
                fontSize: 16,
                color: hasValue
                    ? const Color(0xFF272942)
                    : const Color(0xFFCCCCCC),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;

  const _SectionHeader(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF272942),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF272942),
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFAAAAAA),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

// ─── Photo picker ──────────────────────────────────────────────────────────────

class _PhotoPicker extends StatelessWidget {
  final File? photo;
  final String? networkImageUrl;
  final VoidCallback onTap;

  const _PhotoPicker({
    required this.photo,
    required this.networkImageUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF272942),
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: photo != null
                  ? CircleAvatar(
                      radius: 56,
                      backgroundImage: FileImage(photo!),
                    )
                  : CachedAvatar(imageUrl: networkImageUrl, size: 112),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF272942),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.camera_alt_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Price row ─────────────────────────────────────────────────────────────────

class _PriceRow extends StatelessWidget {
  final int minutes;
  final TextEditingController controller;
  final void Function(String)? onChanged;

  const _PriceRow({
    required this.minutes,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 15,
                  color: Color(0xFF272942),
                ),
                const SizedBox(width: 6),
                Text(
                  '$minutes min',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF272942),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF272942),
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: Color(0xFFCCCCCC),
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'UZS',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFAAAAAA),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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

        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: 16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final isSelected = opt == selected;
                return InkWell(
                  onTap: () => onSelect(opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
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
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
