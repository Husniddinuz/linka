import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'api_constants.dart';

class UpdateInfo {
  final bool hasUpdate;
  final bool isForce;
  final String title;
  final String message;
  final String storeUrl;

  const UpdateInfo({
    required this.hasUpdate,
    required this.isForce,
    required this.title,
    required this.message,
    required this.storeUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      hasUpdate: json['has_update'] as bool? ?? false,
      isForce: json['force_update'] as bool? ?? false,
      title: json['title'] as String? ?? 'New Update Available',
      message: json['message'] as String? ?? 'Please update the app to continue.',
      storeUrl: json['store_url'] as String? ?? '',
    );
  }
}

class UpdateService {
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final osType = Platform.isIOS ? 'ios' : 'android';
      final uri = Uri.parse(
        '$apiBaseUrl/app/version/?os_type=$osType&version=${pkg.version}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final info = UpdateInfo.fromJson(data);
      return info.hasUpdate ? info : null;
    } catch (_) {
      return null;
    }
  }
}
