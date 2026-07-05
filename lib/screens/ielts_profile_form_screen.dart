import 'package:flutter/material.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import 'ielts_confirmation_screen.dart';

/// Candidate profile + registration submission — the core of the flow.
/// Loads reference data directly from IDP, lets the tutor fill in the
/// candidate's details, then submits registration with our partner ID.
class IeltsProfileFormScreen extends StatefulWidget {
  const IeltsProfileFormScreen({
    super.key,
    required this.session,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.mobileNumber,
  });

  final Map<String, dynamic> session;
  final String email;
  final String firstName;
  final String lastName;
  final String mobileNumber;

  @override
  State<IeltsProfileFormScreen> createState() => _IeltsProfileFormScreenState();
}

class _IeltsProfileFormScreenState extends State<IeltsProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _loadingReferenceData = true;
  String? _loadError;
  bool _submitting = false;
  String? _submitError;

  String? _userProfileId;
  List<dynamic> _countries = [];
  List<dynamic> _nationalities = [];
  List<dynamic> _genders = [];
  List<dynamic> _educationLevels = [];
  List<dynamic> _languages = [];
  List<dynamic> _occupationLevels = [];
  List<dynamic> _occupationSectors = [];
  List<dynamic> _testReasons = [];
  List<dynamic> _identificationTypes = [];
  Map<String, dynamic>? _terms;
  List<Map<String, dynamic>> _speakingSlots = [];
  String? _selectedSpeakingStartUtc;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _postCodeController = TextEditingController();
  final _street1Controller = TextEditingController();
  final _street2Controller = TextEditingController();
  final _idNumberController = TextEditingController();
  final _idIssuingAuthorityController = TextEditingController();
  final _yearsOfStudyController = TextEditingController(text: '0');

  String _title = 'MR';
  DateTime? _dateOfBirth;
  String? _genderId;
  String? _nationalityId;
  String? _languageId;
  String? _countryId;
  String? _identificationTypeId;
  DateTime? _idExpiryDate;
  String? _educationLevelId;
  String? _occupationLevelId;
  String? _occupationSectorId;
  String? _testReasonId;
  bool _biometricConsent = false;

  Map<String, dynamic> get _testLocation => widget.session['testLocation'] as Map<String, dynamic>;
  String get _testLocationId => _testLocation['externalReferenceId'] as String;
  String get _lrwProductId => widget.session['externalBookableProductId'] as String;

  @override
  void initState() {
    super.initState();
    _firstNameController.text = widget.firstName;
    _lastNameController.text = widget.lastName;
    _loadReferenceData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _cityController.dispose();
    _postCodeController.dispose();
    _street1Controller.dispose();
    _street2Controller.dispose();
    _idNumberController.dispose();
    _idIssuingAuthorityController.dispose();
    _yearsOfStudyController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _loadingReferenceData = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        IeltsRegistrationService.getUserProfile(),
        IeltsRegistrationService.checkEmailAvailability(widget.email),
        IeltsRegistrationService.getCountries(),
        IeltsRegistrationService.getNationalities(),
        IeltsRegistrationService.getGenders(),
        IeltsRegistrationService.getEducationLevels(),
        IeltsRegistrationService.getLanguages(),
        IeltsRegistrationService.getOccupationLevels(),
        IeltsRegistrationService.getOccupationSectors(),
        IeltsRegistrationService.getTestReasons(),
        IeltsRegistrationService.getIdentificationTypes(),
        IeltsRegistrationService.getTermsAndConditions(),
        IeltsRegistrationService.searchSpeakingSessions(
          linkedSessionId: widget.session['sessionId'] as String,
          testLocationId: _testLocation['id'] as String,
          date: DateTime.parse(widget.session['testStartUtcDatetime'] as String),
        ),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final speakingResult = results[12] as Map<String, dynamic>;
      final speakingItems = (speakingResult['items'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .where((s) => ((s['seatAvailability'] as Map<String, dynamic>)['remaining'] as int) > 0)
          .toList()
        ..sort(
          (a, b) => (a['testStartUtcDatetime'] as String).compareTo(b['testStartUtcDatetime'] as String),
        );
      setState(() {
        _userProfileId = profile['userProfileId'] as String?;
        _countries = results[2] as List<dynamic>;
        _nationalities = results[3] as List<dynamic>;
        _genders = results[4] as List<dynamic>;
        _educationLevels = results[5] as List<dynamic>;
        _languages = results[6] as List<dynamic>;
        _occupationLevels = results[7] as List<dynamic>;
        _occupationSectors = results[8] as List<dynamic>;
        _testReasons = results[9] as List<dynamic>;
        _identificationTypes = results[10] as List<dynamic>;
        _terms = results[11] as Map<String, dynamic>;
        _speakingSlots = speakingItems;
        _selectedSpeakingStartUtc =
            speakingItems.isNotEmpty ? speakingItems.first['testStartUtcDatetime'] as String : null;
        _loadingReferenceData = false;
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load registration form. Please try again.';
        _loadingReferenceData = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null ||
        _genderId == null ||
        _nationalityId == null ||
        _languageId == null ||
        _countryId == null ||
        _identificationTypeId == null ||
        _idExpiryDate == null ||
        _educationLevelId == null ||
        _occupationLevelId == null ||
        _occupationSectorId == null ||
        _testReasonId == null) {
      setState(() => _submitError = 'Please fill in every field.');
      return;
    }
    if (!_biometricConsent) {
      setState(() => _submitError = 'Biometric consent is required by the test centre.');
      return;
    }
    if (_selectedSpeakingStartUtc == null) {
      setState(() => _submitError = 'No Speaking slot is available for this date at this centre.');
      return;
    }

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      final profile = {
        'title': _title,
        'firstName': _firstNameController.text.trim(),
        'lastName': _lastNameController.text.trim(),
        'emailAddress': widget.email,
        'mobileNumber': widget.mobileNumber,
        'dateOfBirth': _dateOfBirth!.toIso8601String().split('T').first,
        'genderId': _genderId,
        'nationalityId': _nationalityId,
        'languageId': _languageId,
        'addressDetails': {
          'countryId': _countryId,
          'city': _cityController.text.trim(),
          'postCode': _postCodeController.text.trim(),
          'streetAddress1': _street1Controller.text.trim(),
          'streetAddress2': _street2Controller.text.trim(),
        },
        'identityDetails': {
          'identificationTypeId': _identificationTypeId,
          'number': _idNumberController.text.trim(),
          'expiryDate': _idExpiryDate!.toIso8601String().split('T').first,
          'issuingAuthority': _idIssuingAuthorityController.text.trim(),
        },
        'marketingDetails': {
          'countryApplyingToId': _countryId,
          'educationLevelId': _educationLevelId,
          'occupationLevelId': _occupationLevelId,
          'occupationSectorId': _occupationSectorId,
          'testReasonId': _testReasonId,
          'yearsOfStudy': _yearsOfStudyController.text.trim(),
        },
      };

      await IeltsRegistrationService.updateUserProfile(_userProfileId!, profile);
      await IeltsRegistrationService.checkBanned(_userProfileId!);

      final lrwStart = DateTime.parse(widget.session['testStartUtcDatetime'] as String);
      final speakingStart = DateTime.parse(_selectedSpeakingStartUtc!);

      final application = await IeltsRegistrationService.registerApplication(
        lrwProductId: _lrwProductId,
        lrwStartDateTimeUtc: lrwStart,
        speakingProductId: _lrwProductId,
        speakingStartDateTimeUtc: speakingStart,
        testLocationId: _testLocationId,
        timeZone: widget.session['testLocalTimeZone'] as String,
        termsAndConditionsVersion: _terms!['id'] as String,
        countryId: _countryId!,
        nationalityId: _nationalityId!,
      );
      // Linking the profile + biometric consent both require a real
      // uploaded ID document image server-side ("Your ID image couldn't be
      // saved..." if it's missing) — that's sensitive personal data we
      // deliberately don't handle in-app, same reasoning as payment. The
      // student finishes that themselves by logging into their own IDP
      // account, which the confirmation screen points them to.

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsConfirmationScreen(
            application: application,
            mobileNumber: widget.mobileNumber,
          ),
        ),
      );
    } catch (e) {
      setState(() => _submitError = 'Registration failed. Please review the details and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: mtAppBar(context, title: 'Candidate Details'),
      body: _loadingReferenceData
          ? const Center(child: CircularProgressIndicator(color: MockTestColors.navy))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, style: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
                        const SizedBox(height: 16),
                        MtPrimaryButton(label: 'Retry', onPressed: _loadReferenceData),
                      ],
                    ),
                  ),
                )
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _sectionTitle('Speaking test time'),
          if (_speakingSlots.isEmpty)
            const Text(
              'No Speaking slot available on this date at this centre.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red),
            )
          else
            _dropdown<String>(
              label: 'Speaking time',
              value: _selectedSpeakingStartUtc,
              items: _speakingSlots.map((s) => s['testStartUtcDatetime'] as String).toList(),
              labelOf: (utc) {
                final local = DateTime.parse(
                  _speakingSlots.firstWhere((s) => s['testStartUtcDatetime'] == utc)['testStartLocalDatetime'] as String,
                );
                return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
              },
              onChanged: (v) => setState(() => _selectedSpeakingStartUtc = v),
            ),
          const SizedBox(height: 24),
          _sectionTitle('Personal details'),
          _dropdown(
            label: 'Title',
            value: _title,
            items: const ['MR', 'MRS', 'MS', 'MISS', 'DR'],
            labelOf: (v) => v,
            onChanged: (v) => setState(() => _title = v!),
          ),
          const SizedBox(height: 12),
          _textField(_firstNameController, 'First name'),
          const SizedBox(height: 12),
          _textField(_lastNameController, 'Last name'),
          const SizedBox(height: 12),
          _datePicker(
            label: 'Date of birth',
            value: _dateOfBirth,
            firstDate: DateTime(1940),
            lastDate: DateTime.now(),
            onChanged: (d) => setState(() => _dateOfBirth = d),
          ),
          const SizedBox(height: 12),
          _refDropdown(label: 'Gender', items: _genders, value: _genderId, onChanged: (v) => setState(() => _genderId = v)),
          const SizedBox(height: 12),
          _refDropdown(
            label: 'Nationality',
            items: _nationalities,
            value: _nationalityId,
            onChanged: (v) => setState(() => _nationalityId = v),
          ),
          const SizedBox(height: 12),
          _refDropdown(
            label: 'First language',
            items: _languages,
            value: _languageId,
            onChanged: (v) => setState(() => _languageId = v),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Address'),
          _refDropdown(
            label: 'Country',
            items: _countries,
            value: _countryId,
            onChanged: (v) => setState(() => _countryId = v),
          ),
          const SizedBox(height: 12),
          _textField(_cityController, 'City'),
          const SizedBox(height: 12),
          _textField(_postCodeController, 'Post code'),
          const SizedBox(height: 12),
          _textField(_street1Controller, 'Street address'),
          const SizedBox(height: 12),
          _textField(_street2Controller, 'Street address 2 (optional)', required: false),
          const SizedBox(height: 24),
          _sectionTitle('Identity document'),
          _refDropdown(
            label: 'Document type',
            items: _identificationTypes,
            value: _identificationTypeId,
            onChanged: (v) => setState(() => _identificationTypeId = v),
          ),
          const SizedBox(height: 12),
          _textField(_idNumberController, 'Document number'),
          const SizedBox(height: 12),
          _datePicker(
            label: 'Document expiry date',
            value: _idExpiryDate,
            firstDate: DateTime.now(),
            lastDate: DateTime(2099),
            onChanged: (d) => setState(() => _idExpiryDate = d),
          ),
          const SizedBox(height: 12),
          _textField(_idIssuingAuthorityController, 'Issuing authority'),
          const SizedBox(height: 24),
          _sectionTitle('Study background'),
          _refDropdown(
            label: 'Education level',
            items: _educationLevels,
            value: _educationLevelId,
            onChanged: (v) => setState(() => _educationLevelId = v),
          ),
          const SizedBox(height: 12),
          _refDropdown(
            label: 'Occupation level',
            items: _occupationLevels,
            value: _occupationLevelId,
            onChanged: (v) => setState(() => _occupationLevelId = v),
          ),
          const SizedBox(height: 12),
          _refDropdown(
            label: 'Occupation sector',
            items: _occupationSectors,
            value: _occupationSectorId,
            onChanged: (v) => setState(() => _occupationSectorId = v),
          ),
          const SizedBox(height: 12),
          _refDropdown(
            label: 'Reason for taking the test',
            items: _testReasons,
            value: _testReasonId,
            onChanged: (v) => setState(() => _testReasonId = v),
          ),
          const SizedBox(height: 12),
          _textField(_yearsOfStudyController, 'Years of English study', keyboardType: TextInputType.number),
          const SizedBox(height: 20),
          CheckboxListTile(
            value: _biometricConsent,
            onChanged: (v) => setState(() => _biometricConsent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I consent to biometric data collection, as required by the test centre.',
              style: TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.navy),
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 8),
            Text(_submitError!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red)),
          ],
          const SizedBox(height: 20),
          MtPrimaryButton(label: 'Register', loading: _submitting, onPressed: _submit),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'SF Pro',
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: MockTestColors.greyLight,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _textField(
    TextEditingController controller,
    String label, {
    bool required = true,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
        filled: true,
        fillColor: MockTestColors.softBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(labelOf(e)))).toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? 'Required' : null,
      style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
        filled: true,
        fillColor: MockTestColors.softBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _refDropdown({
    required String label,
    required List<dynamic> items,
    required String? value,
    required void Function(String?) onChanged,
  }) {
    return _dropdown<String>(
      label: label,
      value: value,
      items: items.map((e) => (e as Map<String, dynamic>)['id'] as String).toList(),
      labelOf: (id) {
        final item = items.cast<Map<String, dynamic>>().firstWhere((e) => e['id'] == id);
        return item['name'] as String;
      },
      onChanged: onChanged,
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    required DateTime firstDate,
    required DateTime lastDate,
    required void Function(DateTime) onChanged,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? firstDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
          filled: true,
          fillColor: MockTestColors.softBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        child: Text(
          value == null ? 'Select date' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
        ),
      ),
    );
  }
}
