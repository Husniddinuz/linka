import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import 'crop_screen.dart';
import 'ielts_confirmation_screen.dart';

/// Final step of the real IELTS registration flow: uploads a photo of the
/// candidate's ID document straight to IDP's own S3 bucket and records
/// biometric consent — both reverse-engineered from a live capture of the
/// real book.ielts.idp.com post-registration flow (see
/// [IeltsRegistrationService.uploadIdImage]/`linkApplicationProfile`/
/// `submitBiometricConsent`). Runs after the seats are already reserved,
/// matching the real site's own step order.
class IeltsIdUploadScreen extends StatefulWidget {
  const IeltsIdUploadScreen({
    super.key,
    required this.application,
    required this.profile,
    required this.mobileNumber,
  });

  /// Response from `POST /v1/applications/register`.
  final Map<String, dynamic> application;

  /// The candidate's userProfile, as returned by the profile update, with
  /// `id` set — this gets re-submitted with the uploaded image details.
  final Map<String, dynamic> profile;
  final String mobileNumber;

  @override
  State<IeltsIdUploadScreen> createState() => _IeltsIdUploadScreenState();
}

class _IeltsIdUploadScreenState extends State<IeltsIdUploadScreen> {
  File? _idPhoto;
  bool _consentGiven = false;
  bool _submitting = false;
  String? _error;

  String get _applicationId => widget.application['id'] as String;

  Future<void> _pickPhoto() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;

    final cropped = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => CropScreen(imageFile: File(path), aspectRatio: 3 / 2)),
    );
    if (cropped != null && mounted) setState(() => _idPhoto = cropped);
  }

  Future<void> _submit() async {
    if (_idPhoto == null) {
      setState(() => _error = 'Please add a photo of the ID document.');
      return;
    }
    if (!_consentGiven) {
      setState(() => _error = 'Biometric consent is required by the test centre.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final bytes = await _idPhoto!.readAsBytes();
      // CropScreen names the file cropped_<timestamp>.jpg, but it always
      // re-encodes through a PNG intermediate (`_loadImage`'s
      // `ui.ImageByteFormat.png`) before cropping, and crop_your_image
      // preserves whatever format it detects on the way in — so the actual
      // bytes are PNG regardless of the .jpg name. Sniffing the real magic
      // bytes here (rather than trusting the extension) avoids sending IDP
      // an image whose declared Content-Type doesn't match its contents,
      // which is very likely why "Your ID image couldn't be saved" showed
      // up after upload.
      final isPng = bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
      final contentType = isPng ? 'image/png' : 'image/jpeg';
      final filename = 'id-document.${isPng ? 'png' : 'jpg'}';
      final upload = await IeltsRegistrationService.uploadIdImage(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );

      final identityDetails = Map<String, dynamic>.from(widget.profile['identityDetails'] as Map);
      identityDetails['s3Url'] = upload.s3Url;
      identityDetails['version'] = upload.version;
      identityDetails['numberOfIdImages'] = 1;
      final profile = Map<String, dynamic>.from(widget.profile);
      profile['identityDetails'] = identityDetails;

      await IeltsRegistrationService.linkApplicationProfile(_applicationId, profile);

      final application = await IeltsRegistrationService.getApplication(_applicationId);
      await IeltsRegistrationService.submitBiometricConsent(
        _applicationId,
        consentGiven: true,
        version: application['version'] as String,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsConfirmationScreen(application: application, mobileNumber: widget.mobileNumber),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Could not upload the ID document. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'ID Verification'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'The seats are reserved. Last step: a photo of the candidate\'s ID '
            'document (the one entered earlier) for the test centre.',
            style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.grey),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: 200,
              width: double.infinity,
              decoration: mtSoftCard(context, radius: 14),
              clipBehavior: Clip.antiAlias,
              child: _idPhoto == null
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.add_a_photo_rounded, color: MockTestColors.grey, size: 32),
                          SizedBox(height: 8),
                          Text('Add ID photo', style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
                        ],
                      ),
                    )
                  : Image.file(_idPhoto!, fit: BoxFit.cover, width: double.infinity),
            ),
          ),
          if (_idPhoto != null) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _pickPhoto,
                child: const Text('Retake', style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.navy)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _consentGiven,
            onChanged: (v) => setState(() => _consentGiven = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I consent to biometric data collection, as required by the test centre.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.navy),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red)),
          ],
          const SizedBox(height: 20),
          MtPrimaryButton(label: 'Finish', loading: _submitting, onPressed: _submit),
        ],
      ),
    );
  }
}
