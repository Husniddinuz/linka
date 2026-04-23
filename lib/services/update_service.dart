import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

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
      final result = await ApiService.get(
        '/app/version/?version=${pkg.version}',
      );
      final data = (result['data'] is Map<String, dynamic>)
          ? result['data'] as Map<String, dynamic>
          : result;
      final info = UpdateInfo.fromJson(data);
      return info.hasUpdate ? info : null;
    } catch (_) {
      return null;
    }
  }
}
