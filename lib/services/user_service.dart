import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Lightweight holder for the authenticated user's identity & role.
///
/// Source of truth is `GET /users/me/`, which returns role flags used to
/// decide whether to render tutor or student UI. The role is cached in
/// `SharedPreferences` so `HomeScreen` can render the correct bottom nav
/// on first paint without waiting for the network.
class UserService {
  static const _roleKey = 'user_role'; // 'tutor' or 'student'
  static const _isTeacherKey = 'user_is_teacher';

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  static UserMe? _current;
  static UserMe? get current => _current;

  /// Returns the cached role if available, else null.
  /// Use on first paint to decide bottom nav before network completes.
  static Future<bool?> getCachedIsTeacher() async {
    final prefs = await _instance;
    if (!prefs.containsKey(_isTeacherKey)) return null;
    return prefs.getBool(_isTeacherKey);
  }

  static Future<void> _cache(UserMe me) async {
    final prefs = await _instance;
    await prefs.setString(_roleKey, me.role);
    await prefs.setBool(_isTeacherKey, me.isTeacher);
  }

  static const _exemptPhone = '+998101002233';

  /// True when the current user's phone is exempt from Plus restrictions.
  /// Used to hide Plus banners, bypass free-minutes limits, and hide the
  /// random-partner speaking practice button on the student home.
  static bool get isExemptFromPlus => _current?.phone == _exemptPhone;

  /// Static-OTP test accounts (see backend `STATIC_OTP_PHONES`). Kept in
  /// sync with `apps/users/constants.py` on linka-backend.
  static const testPhones = {
    '+998101002233',
    '+998900371655',
    '+998779710744',
  };

  /// True when logged in as one of the static test accounts. Used to force
  /// every remote [AppFeatureService] flag on for QA/reviewers, regardless
  /// of what's currently toggled off in production.
  static bool get isTestUser => testPhones.contains(_current?.phone);

  static Future<void> clear() async {
    final prefs = await _instance;
    await prefs.remove(_roleKey);
    await prefs.remove(_isTeacherKey);
    _current = null;
  }

  /// Fetches /users/me/ and caches the result.
  static Future<UserMe> fetchMe() async {
    try {
      final result = await ApiService.get('/users/me/');
      final payload = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      final me = UserMe.fromJson(payload);
      _current = me;
      await _cache(me);
      return me;
    } catch (e, st) {
      rethrow;
    }
  }
}

class UserMe {
  final int id;
  final String phone;

  /// The address this account can also sign in with, or null.
  ///
  /// Accounts are always created by phone; an email is attached afterwards
  /// from My Profile and only counts once its code has been redeemed. So null
  /// means "never linked", not "not loaded yet".
  final String? email;

  final String role;
  final bool isTeacher;
  final bool isStudent;
  final bool isProfileComplete;
  final int? studentProfileId;
  final int? tutorProfileId;
  final String? tutorAccountStatus;

  const UserMe({
    required this.id,
    required this.phone,
    this.email,
    required this.role,
    required this.isTeacher,
    required this.isStudent,
    required this.isProfileComplete,
    this.studentProfileId,
    this.tutorProfileId,
    this.tutorAccountStatus,
  });

  factory UserMe.fromJson(Map<String, dynamic> json) {
    return UserMe(
      id: (json['id'] as num?)?.toInt() ?? 0,
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString(),
      role: json['role']?.toString() ?? 'student',
      isTeacher: json['is_teacher'] as bool? ?? false,
      isStudent: json['is_student'] as bool? ?? false,
      isProfileComplete: json['isProfileComplete'] as bool? ??
          json['is_profile_complete'] as bool? ??
          false,
      studentProfileId: (json['student_profile_id'] as num?)?.toInt(),
      tutorProfileId: (json['tutor_profile_id'] as num?)?.toInt(),
      tutorAccountStatus: json['tutor_account_status'] as String?,
    );
  }
}
