import 'package:package_info_plus/package_info_plus.dart';

import '../models/announcement.dart';
import 'api_service.dart';

/// The one-time "what's new" popups. The server only returns cards this
/// account has not dismissed or opened yet, on any device, so the client's
/// whole job is: show the first one, then tell the server it was seen.
class AnnouncementService {
  /// One popup per app launch. Set the moment a card is shown, so a second
  /// home screen (e.g. after re-login in the same process) stays quiet.
  static bool shownThisSession = false;

  /// Sends this build's version so release notes written for it (the
  /// card's `min_app_version`) show up the first launch after the update.
  static Future<List<Announcement>> fetchUnseen() async {
    final version = (await PackageInfo.fromPlatform()).version;
    final raw = await ApiService.getList(
      '/announcements/?app_version=${Uri.encodeQueryComponent(version)}',
    );
    return [
      for (final item in raw)
        if (item is Map<String, dynamic>) Announcement.fromJson(item),
    ];
  }

  /// Fire-and-forget. A lost write only means the card comes back once more
  /// on the next launch, which is a better failure than a stuck popup.
  static Future<void> markSeen(int id) async {
    try {
      await ApiService.post('/announcements/$id/seen/', const {});
    } catch (_) {}
  }
}
