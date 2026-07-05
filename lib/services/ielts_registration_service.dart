import 'dart:convert';

import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Direct client-side integration with IDP IELTS' public booking backend.
/// Every call here goes straight from the app to IDP's own APIs (confirmed
/// from real network captures) — nothing routes through the linka backend,
/// so candidate PII never touches our servers.
class IeltsConfig {
  static const partnerId = '5bb30157-1b6c-4964-bb24-92e35071ad1f';
  static const testCentreId = '9a6e0ecc-7b9d-4cfa-80b8-061c459b5819';

  static const userPoolId = 'ap-southeast-1_P0ztPrcKW';
  static const clientId = '7h4fe21h8h7oe2gu3q8aua3g72';

  static const bxSearchBase = 'https://api.bxsearch.prod.ielts.com';
  static const sessionSearchBase = 'https://api.session-search.prod.ielts.com';
  static const accountApiBase = 'https://api.account.ielts.idp.com';
  static const testTakerBase = 'https://api.test-taker.prod.ielts.com';
}

/// Persists Cognito tokens in SharedPreferences so a candidate's session
/// survives app restarts (the package defaults to in-memory storage, which
/// would force a fresh sign-in every launch).
class _PrefsCognitoStorage extends CognitoStorage {
  static const _prefix = 'ielts_cognito.';

  @override
  Future<dynamic> getItem(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<dynamic> setItem(String key, value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value.toString());
    return value;
  }

  @override
  Future<dynamic> removeItem(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await prefs.remove(key);
    }
  }
}

class IeltsApiException implements Exception {
  IeltsApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'IeltsApiException($statusCode): $message';
}

class IeltsRegistrationService {
  // Calling cognito-idp.<region>.amazonaws.com directly gets a 403 "Request
  // not allowed due to WAF block" — confirmed by direct testing. IDP's own
  // frontend routes Cognito calls through this proxy instead, so we must too.
  static const _cognitoProxyEndpoint = 'https://ielts.api.security.idp.com/v1/ielts/cognito-proxy';

  static final CognitoUserPool _userPool = CognitoUserPool(
    IeltsConfig.userPoolId,
    IeltsConfig.clientId,
    endpoint: _cognitoProxyEndpoint,
    storage: _PrefsCognitoStorage(),
  );

  // The pool is configured with email as an alias, not as the username
  // itself — SignUp rejects an email-shaped Username ("Username cannot be
  // of email format"). Deriving it from the email keeps login repeatable
  // without needing separate local storage of a generated ID.
  static String _cognitoUsername(String email) =>
      sha1.convert(utf8.encode(email.trim().toLowerCase())).toString();

  // ─── Search (no auth required) ───────────────────────────────────────

  /// Reading/Listening/Writing sessions at the configured test centre.
  static Future<Map<String, dynamic>> searchLrwSessions({
    required DateTime from,
    required DateTime to,
    int page = 1,
    int pageSize = 10,
  }) {
    return _postJson('${IeltsConfig.bxSearchBase}/v2/sessions/private', {
      'dayOfPaperTest': 0,
      'languageSkills': ['L', 'R', 'W'],
      'order': 'A',
      'page': page,
      'pageSize': pageSize,
      'sortBy': 'TEST_START_DATE',
      'referralPartnerId': IeltsConfig.partnerId,
      'testCenterIds': [IeltsConfig.testCentreId],
      'timesOfDay': ['MORNING', 'AFTERNOON'],
      'testDeliveryFormats': [],
      'testCategories': [],
      'testModules': [],
    });
  }

  /// Speaking sessions linked to a chosen LRW session at a test location.
  static Future<Map<String, dynamic>> searchSpeakingSessions({
    required String linkedSessionId,
    required String testLocationId,
    required DateTime date,
  }) {
    final dateStr = date.toIso8601String().split('T').first;
    return _postJson('${IeltsConfig.sessionSearchBase}/v2/sessions/search', {
      'dayOfPaperTest': 0,
      'testCategories': ['IELTS'],
      'fromTestStartDateLocal': dateStr,
      'toTestStartDateLocal': dateStr,
      'linkedSessionId': linkedSessionId,
      'languageSkills': ['S'],
      'order': 'A',
      'page': 1,
      'pageSize': 0,
      'sortBy': 'TEST_START_DATE',
      'testDeliveryFormats': ['CD'],
      'testModules': ['ACADEMIC'],
      'timesOfDay': ['MORNING', 'AFTERNOON'],
      'testLocationIds': [testLocationId],
    });
  }

  // ─── Account (Cognito sign-up / sign-in) ─────────────────────────────

  /// Logs in if the email already has an IDP account, otherwise signs one
  /// up first. Returns the authenticated [CognitoUserSession]. SRP auth is
  /// handled entirely by the package — no password is ever stored.
  static Future<CognitoUserSession> signInOrSignUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final username = _cognitoUsername(email);
    final cognitoUser = CognitoUser(username, _userPool, storage: _PrefsCognitoStorage());
    final authDetails = AuthenticationDetails(username: username, password: password);

    try {
      final session = await cognitoUser.authenticateUser(authDetails);
      if (session == null) throw IeltsApiException('Cognito returned no session');
      return session;
    } on CognitoClientException catch (e) {
      if (e.code != 'UserNotFoundException') rethrow;
    }

    await _userPool.signUp(
      username,
      password,
      userAttributes: [
        AttributeArg(name: 'email', value: email),
        AttributeArg(name: 'name', value: fullName),
      ],
    );

    final session = await cognitoUser.authenticateUser(authDetails);
    if (session == null) throw IeltsApiException('Cognito returned no session after sign-up');
    return session;
  }

  static Future<Map<String, dynamic>> createAccountProfile({
    required String email,
    required String firstName,
    required String lastName,
    required String mobileNumber,
  }) async {
    return _postJson(
      '${IeltsConfig.accountApiBase}/v1/userprofile',
      {
        'emailAddress': email,
        'firstName': firstName,
        'lastName': lastName,
        'mobileNumber': mobileNumber,
        'marketingDetails': {
          'preparationContactPermission': true,
          'studyContactPermission': true,
        },
        'requestType': 'create',
      },
      authenticated: true,
    );
  }

  // Endpoints tied to a specific candidate's identity (profile, applications,
  // account creation, payment methods) 401 without this — confirmed by
  // direct testing. Reference/catalogue data and search stay public. The
  // captured HAR never showed this header (Chrome's HAR export redacts
  // Authorization values), and it's the ACCESS token, not the ID token —
  // confirmed via a live "copy as cURL" from an authenticated session,
  // after the ID token and a full IAM/SigV4 signing attempt both failed.
  static Future<Map<String, String>> _authHeaders() async {
    final user = await _userPool.getCurrentUser();
    if (user == null) throw IeltsApiException('Not signed in');
    final session = await user.getSession();
    final accessToken = session?.getAccessToken().getJwtToken();
    if (accessToken == null) throw IeltsApiException('No valid session');
    return {'Authorization': 'Bearer $accessToken'};
  }

  // ─── Reference data ───────────────────────────────────────────────────

  // These all return {items, page, pageSize, totalCount} — unlike
  // identificationTypes below, which returns a bare array.
  static Future<List<dynamic>> _referenceData(String slug) async {
    final result = await _getJson('${IeltsConfig.testTakerBase}/v1/referenceData/$slug');
    return (result as Map<String, dynamic>)['items'] as List<dynamic>;
  }

  static Future<List<dynamic>> getCountries() => _referenceData('countries');
  static Future<List<dynamic>> getNationalities() => _referenceData('nationalities');
  static Future<List<dynamic>> getGenders() => _referenceData('genders');
  static Future<List<dynamic>> getEducationLevels() => _referenceData('educationLevels');
  static Future<List<dynamic>> getLanguages() => _referenceData('languages');
  static Future<List<dynamic>> getTerritories(String countryCode) =>
      _referenceData('territories?countryCode=$countryCode');
  static Future<List<dynamic>> getOccupationLevels() => _referenceData('occupationLevels');
  static Future<List<dynamic>> getOccupationSectors() => _referenceData('occupationSectors');
  static Future<List<dynamic>> getTestReasons() => _referenceData('testReasons');
  static Future<List<dynamic>> getIdentificationTypes() => _referenceData('identificationTypes');

  /// Observed to 500 in testing regardless of headers/payload — prefer the
  /// `testLocation` object already embedded in search results over calling
  /// this directly.
  static Future<Map<String, dynamic>> getTestLocation(String testLocationId) =>
      _getJson('${IeltsConfig.testTakerBase}/v1/testLocations/$testLocationId')
          .then((r) => r as Map<String, dynamic>);

  static Future<Map<String, dynamic>> getProductFee(String testLocationId, String productId) =>
      _getJson('${IeltsConfig.testTakerBase}/v1/testLocations/$testLocationId/products/$productId/fee')
          .then((r) => r as Map<String, dynamic>);

  static Future<List<dynamic>> getTestCentrePaymentMethods() => _getJson(
        '${IeltsConfig.testTakerBase}/v1/testCentrePaymentMethods?testCentreId=${IeltsConfig.testCentreId}',
        authenticated: true,
      ).then((r) => r as List<dynamic>);

  static Future<Map<String, dynamic>> getTermsAndConditions() =>
      _getJson('${IeltsConfig.testTakerBase}/v1/termsAndConditions/latest').then((r) => r as Map<String, dynamic>);

  // ─── Candidate profile ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getUserProfile() =>
      _getJson('${IeltsConfig.testTakerBase}/v1/userProfiles', authenticated: true)
          .then((r) => r as Map<String, dynamic>);

  /// Despite the endpoint name, this isn't profile-field validation and
  /// isn't an emailed OTP check either — both plausible-looking guesses
  /// that turned out wrong. Confirmed live: `token` just has to be
  /// non-null (any value — captcha is explicitly disabled here via
  /// `enable_captcha_validation: false`, and it's accepted regardless of
  /// what the value is); the actual payload is `emailExistsFlag` /
  /// `recaptchaSuccessFlag`, i.e. a duplicate-email pre-check the real
  /// frontend runs automatically before showing the profile form — no
  /// user input required.
  static Future<Map<String, dynamic>> checkEmailAvailability(String email) => _postJson(
        '${IeltsConfig.testTakerBase}/v1/userProfiles/validate',
        {
          'emailAddress': email,
          'token': DateTime.now().millisecondsSinceEpoch.toString(),
          'enable_captcha_validation': false,
        },
        authenticated: true,
      );

  static Future<Map<String, dynamic>> updateUserProfile(String userProfileId, Map<String, dynamic> profile) =>
      _putJson('${IeltsConfig.testTakerBase}/v1/userProfiles/$userProfileId', profile, authenticated: true);

  static Future<Map<String, dynamic>> checkBanned(String userProfileId) => _postJson(
        '${IeltsConfig.testTakerBase}/v1/userProfiles/$userProfileId/isBanned',
        {},
        authenticated: true,
      );

  // ─── Application registration ─────────────────────────────────────────

  /// Reserves the seats. `referralPartnerId` here is what attributes the
  /// booking to us — this must be present on every registration.
  ///
  /// IDs here are test-taker-side IDs, which differ from the search API's
  /// IDs for the same session: pass search result `externalBookableProductId`
  /// (not `bookableProductId`) as the product IDs, and `testLocation.
  /// externalReferenceId` (not `testLocation.id`) as [testLocationId].
  static Future<Map<String, dynamic>> registerApplication({
    required String lrwProductId,
    required DateTime lrwStartDateTimeUtc,
    required String speakingProductId,
    required DateTime speakingStartDateTimeUtc,
    required String testLocationId,
    required String timeZone,
    required String termsAndConditionsVersion,
    required String countryId,
    required String nationalityId,
  }) {
    return _postJson(
      '${IeltsConfig.testTakerBase}/v1/applications/register',
      {
        'lrwBookingCriteria': {
          'bookableProductId': lrwProductId,
          'startDateTimeUtc': lrwStartDateTimeUtc.toIso8601String(),
        },
        'speakingBookingCriteria': {
          'bookableProductId': speakingProductId,
          'startDateTimeUtc': speakingStartDateTimeUtc.toIso8601String(),
        },
        'testLocationId': testLocationId,
        'timeZone': timeZone,
        'termsAndConditionsVersion': termsAndConditionsVersion,
        'referralPartnerId': IeltsConfig.partnerId,
        'marketingDetails': {},
        'countryId': countryId,
        'nationalityId': nationalityId,
      },
      authenticated: true,
    );
  }

  /// Not currently called from any screen: this 500s with "Your ID image
  /// couldn't be saved..." unless the profile already has a real uploaded
  /// ID document image, which requires an upload endpoint we never found
  /// (deliberately not chased further — same reasoning as payment: that's
  /// sensitive personal data the student should submit directly through
  /// their own IDP account, not through us). Left here in case that
  /// changes; the exact body shape (needs `emailAddress` alongside
  /// `userProfileId`, confirmed live) is otherwise correct.
  static Future<Map<String, dynamic>> linkApplicationProfile(
    String applicationId,
    String userProfileId, {
    required String emailAddress,
  }) =>
      _postJson(
        '${IeltsConfig.testTakerBase}/v1/applications/$applicationId/userProfile',
        {'userProfileId': userProfileId, 'emailAddress': emailAddress},
        authenticated: true,
      );

  /// See [linkApplicationProfile] — same ID-document prerequisite applies.
  static Future<Map<String, dynamic>> submitBiometricConsent(
    String applicationId, {
    required bool consentGiven,
  }) =>
      _patchJson(
        '${IeltsConfig.testTakerBase}/v1/applications/$applicationId/biometricConsentDetails',
        {'consentGiven': consentGiven},
        authenticated: true,
      );

  /// Generates a payment reference for the chosen (non-card) payment
  /// method — no money moves through this call. The resulting receipt is
  /// what gets sent to the student's phone to complete payment themselves.
  static Future<Map<String, dynamic>> createReceipt({
    required String applicationId,
    required String applicationPaymentId,
    required String testCentrePaymentMethodId,
  }) =>
      _postJson(
        '${IeltsConfig.testTakerBase}/v1/receipts',
        {
          'applicationId': applicationId,
          'applicationPaymentId': applicationPaymentId,
          'testCentrePaymentMethodId': testCentrePaymentMethodId,
        },
        authenticated: true,
      );

  // ─── HTTP helpers ─────────────────────────────────────────────────────

  // api.test-taker.prod.ielts.com sits behind a WAF rule that 403s any
  // request without a browser-like User-Agent (confirmed: curl's default
  // UA gets blocked, an explicit one of any kind is enough) — set on every
  // call rather than relying on whatever a given platform's HTTP client
  // sends by default.
  static const _headers = {
    'Accept': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
  };
  static const _jsonHeaders = {..._headers, 'Content-Type': 'application/json'};

  static Future<dynamic> _getJson(String url, {bool authenticated = false}) async {
    final headers = authenticated ? {..._headers, ...await _authHeaders()} : _headers;
    final response = await http.get(Uri.parse(url), headers: headers);
    return _decode(response);
  }

  static Future<Map<String, dynamic>> _postJson(
    String url,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    final headers = authenticated ? {..._jsonHeaders, ...await _authHeaders()} : _jsonHeaders;
    final response = await http.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
    return _decode(response) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _putJson(
    String url,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    final headers = authenticated ? {..._jsonHeaders, ...await _authHeaders()} : _jsonHeaders;
    final response = await http.put(Uri.parse(url), headers: headers, body: jsonEncode(body));
    return _decode(response) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _patchJson(
    String url,
    Map<String, dynamic> body, {
    bool authenticated = false,
  }) async {
    final headers = authenticated ? {..._jsonHeaders, ...await _authHeaders()} : _jsonHeaders;
    final response = await http.patch(Uri.parse(url), headers: headers, body: jsonEncode(body));
    return _decode(response) as Map<String, dynamic>;
  }

  static dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IeltsApiException(response.body, statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body);
  }
}
