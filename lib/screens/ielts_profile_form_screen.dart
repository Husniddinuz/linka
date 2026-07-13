import 'package:flutter/material.dart';

import '../services/ielts_registration_service.dart';
import '../widgets/mock_test_styles.dart';
import '../widgets/skeleton.dart';
import 'ielts_id_upload_screen.dart';

/// Candidate profile + registration submission — the core of the flow.
/// Loads reference data directly from IDP, lets the tutor fill in the
/// candidate's details across a short wizard, then submits registration
/// with our partner ID. ID document upload + biometric consent happen on
/// [IeltsIdUploadScreen] afterwards, matching the real site's own order.
class IeltsProfileFormScreen extends StatefulWidget {
  const IeltsProfileFormScreen({
    super.key,
    required this.session,
    required this.email,
  });

  final Map<String, dynamic> session;
  final String email;

  @override
  State<IeltsProfileFormScreen> createState() => _IeltsProfileFormScreenState();
}

class _IeltsProfileFormScreenState extends State<IeltsProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  static const _stepTitles = [
    'Speaking test time',
    'Personal details',
    'Address',
    'Identity document',
    'Study background',
  ];
  int _step = 0;

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
  final _mobileController = TextEditingController(text: '+998');
  final _studyingEnglishAtController = TextEditingController();
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

  Map<String, dynamic> get _testLocation => widget.session['testLocation'] as Map<String, dynamic>;
  String get _testLocationId => _testLocation['externalReferenceId'] as String;
  String get _lrwProductId => widget.session['externalBookableProductId'] as String;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _studyingEnglishAtController.dispose();
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
      // TODO: temporary — surfaces the real API error for debugging, revert
      // to a plain "Could not load..." message once the cause is fixed.
      setState(() {
        _loadError = 'Could not load registration form: $e';
        _loadingReferenceData = false;
      });
    }
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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
        'mobileNumber': _mobileController.text.trim(),
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
          'currentlyStudyingEnglishAt': _studyingEnglishAtController.text.trim(),
          'educationLevelId': _educationLevelId,
          'occupationLevelId': _occupationLevelId,
          'occupationSectorId': _occupationSectorId,
          'testReasonId': _testReasonId,
          'yearsOfStudy': _yearsOfStudyController.text.trim(),
        },
      };

      // The account-level profile (api.account.ielts.idp.com) was already
      // provisioned back on the signup screen — it's a placeholder there and
      // stays one; the test-taker profile below is what actually carries the
      // candidate's real name/mobile for registration.
      final updatedProfile = await IeltsRegistrationService.updateUserProfile(_userProfileId!, profile);
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

      // "Reserve now" — confirmed live to be a required step between
      // registering and ID upload, not just a payment-summary formality:
      // IDP rejects the ID image ("couldn't be saved") if this hasn't run
      // yet. The test centre currently only offers one method (in-person/
      // offline), so there's nothing for the tutor to choose here.
      final applicationId = application['id'] as String;
      final applicationPaymentId =
          ((application['applicationPayments'] as List).first as Map<String, dynamic>)['id'] as String;
      final paymentMethods = await IeltsRegistrationService.getTestCentrePaymentMethods();
      final offlineMethod = paymentMethods.cast<Map<String, dynamic>>().firstWhere(
            (m) => (m['paymentMethod'] as Map<String, dynamic>)['code'] == 'OFFLINE',
          );
      await IeltsRegistrationService.createReceipt(
        applicationId: applicationId,
        applicationPaymentId: applicationPaymentId,
        testCentrePaymentMethodId: offlineMethod['id'] as String,
      );
      final reservedApplication = await IeltsRegistrationService.getApplication(applicationId);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => IeltsIdUploadScreen(
            application: reservedApplication,
            // The `/applications/{id}/userProfile` link endpoint expects the
            // profile's id under `id` (confirmed live) — the userProfiles
            // PUT response above uses `userProfileId` instead, so relabel.
            profile: {...updatedProfile, 'id': _userProfileId},
            mobileNumber: _mobileController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      // TODO: temporary — surfaces the real API error for debugging, revert
      // to a plain "Registration failed..." message once the cause is fixed.
      setState(() => _submitError = 'Registration failed: $e');
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
              // Registration is several sequential IDP calls (profile update,
              // ban check, register, payment method, receipt) — can take a
              // few seconds, so swap the wizard for a skeleton rather than
              // leaving the form sitting there with just a button spinner.
              : _submitting
                  ? const _RegisterSkeleton()
                  : _buildWizard(),
    );
  }

  Widget _buildWizard() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _stepHeader(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepSpeakingTime(),
                _stepPersonalDetails(),
                _stepAddress(),
                _stepIdentityDocument(),
                _stepStudyBackground(),
              ],
            ),
          ),
          _stepFooter(),
        ],
      ),
    );
  }

  Widget _stepHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${_step + 1} of ${_stepTitles.length} · ${_stepTitles[_step]}',
            style: const TextStyle(fontFamily: 'SF Pro', fontSize: 12.5, fontWeight: FontWeight.w600, color: MockTestColors.grey),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step + 1) / _stepTitles.length,
              minHeight: 4,
              backgroundColor: MockTestColors.softBg,
              color: MockTestColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepFooter() {
    final isLast = _step == _stepTitles.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_submitError != null) ...[
            Text(_submitError!, style: const TextStyle(fontFamily: 'SF Pro', fontSize: 13, color: MockTestColors.red)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              if (_step > 0) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _goToStep(_step - 1),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MockTestColors.navy,
                      side: const BorderSide(color: MockTestColors.divider),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: 2,
                child: MtPrimaryButton(
                  label: isLast ? 'Register' : 'Next',
                  onPressed: isLast ? _submit : () => _goToStep(_step + 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBody(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _stepSpeakingTime() {
    return _stepBody([
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
    ]);
  }

  Widget _stepPersonalDetails() {
    return _stepBody([
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
      _textField(_mobileController, 'Mobile number', keyboardType: TextInputType.phone),
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
      const SizedBox(height: 12),
      _textField(_studyingEnglishAtController, 'Which country are you currently studying English?'),
    ]);
  }

  Widget _stepAddress() {
    return _stepBody([
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
    ]);
  }

  Widget _stepIdentityDocument() {
    return _stepBody([
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
    ]);
  }

  Widget _stepStudyBackground() {
    return _stepBody([
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
    ]);
  }

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

  /// Opens a search-as-you-type sheet instead of a long plain dropdown —
  /// several of these lists (countries, nationalities) run past 100 items.
  Future<T?> _searchSelect<T>({
    required String label,
    required List<T> items,
    required String Function(T) labelOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = query.isEmpty
                ? items
                : items.where((e) => labelOf(e).toLowerCase().contains(query.toLowerCase())).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        label,
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 16, fontWeight: FontWeight.w700, color: MockTestColors.navy),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setSheetState(() => query = v),
                        style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          prefixIcon: const Icon(Icons.search, size: 20, color: MockTestColors.grey),
                          filled: true,
                          fillColor: MockTestColors.softBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text('No matches', style: TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey)),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) => ListTile(
                                title: Text(labelOf(filtered[i]), style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy)),
                                onTap: () => Navigator.pop(ctx, filtered[i]),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) labelOf,
    required void Function(T?) onChanged,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await _searchSelect<T>(label: label, items: items, labelOf: labelOf);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
          filled: true,
          fillColor: MockTestColors.softBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          // Extra top padding vs. bottom (Flutter's own filled-field default
          // is 20/12) — a floating label needs that room above the value or
          // it clips against the box's top edge.
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
        ),
        child: Text(
          value == null ? 'Select' : labelOf(value),
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
        ),
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
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'SF Pro', color: MockTestColors.grey),
          filled: true,
          fillColor: MockTestColors.softBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
        ),
        child: Text(
          value == null ? 'Select date' : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontFamily: 'SF Pro', fontSize: 15, color: MockTestColors.navy),
        ),
      ),
    );
  }
}

/// Shown in place of the wizard while [_IeltsProfileFormScreenState._submit]
/// works through its chain of IDP calls — mirrors the shape of the form/
/// summary the user was just looking at instead of a blank spinner screen.
class _RegisterSkeleton extends StatelessWidget {
  const _RegisterSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Skeleton(height: 12.5, width: 150, borderRadius: 4),
        const SizedBox(height: 8),
        const Skeleton(height: 4, borderRadius: 4),
        const SizedBox(height: 20),
        const Text(
          'Submitting your registration…',
          style: TextStyle(fontFamily: 'SF Pro', fontSize: 13.5, color: MockTestColors.grey),
        ),
        const SizedBox(height: 20),
        _card([
          const Skeleton(height: 14, width: double.infinity, borderRadius: 6),
          const SizedBox(height: 14),
          const Skeleton(height: 14, width: double.infinity, borderRadius: 6),
          const SizedBox(height: 14),
          const Skeleton(height: 14, width: 160, borderRadius: 6),
        ]),
        const SizedBox(height: 16),
        _card([
          const Skeleton(height: 14, width: double.infinity, borderRadius: 6),
          const SizedBox(height: 14),
          const Skeleton(height: 14, width: 200, borderRadius: 6),
        ]),
        const SizedBox(height: 16),
        _card([
          const Skeleton(height: 14, width: double.infinity, borderRadius: 6),
          const SizedBox(height: 14),
          const Skeleton(height: 14, width: double.infinity, borderRadius: 6),
          const SizedBox(height: 14),
          const Skeleton(height: 14, width: 120, borderRadius: 6),
        ]),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: mtSoftCard(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
