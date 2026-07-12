import 'dart:io';

import 'package:share_plus/share_plus.dart';

class ShareService {
  static Future<void> shareTutorProfile({
    required int tutorId,
    String? tutorName,
  }) async {
    final link = 'linka://tutor/$tutorId';
    final name = (tutorName ?? '').trim();
    final text = name.isEmpty
        ? 'Check out this tutor on Linka: $link'
        : 'Check out $name on Linka: $link';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  static Future<void> shareWritingResult({required String overallBand, String? promptTitle}) async {
    final title = (promptTitle ?? '').trim();
    final text = title.isEmpty
        ? 'I just scored Band $overallBand on my IELTS Writing practice with Linka! 🎉'
        : 'I just scored Band $overallBand on "$title" with Linka IELTS practice! 🎉';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  /// Shares a rendered result card image (e.g. for posting to an Instagram
  /// Story) alongside the same caption used by [shareWritingResult]. Opens
  /// the native share sheet — apps like Instagram route an incoming image
  /// share straight into their Stories composer.
  static Future<void> shareWritingResultImage({
    required File imageFile,
    required String overallBand,
    String? promptTitle,
  }) async {
    final title = (promptTitle ?? '').trim();
    final text = title.isEmpty
        ? 'I just scored Band $overallBand on my IELTS Writing practice with Linka! 🎉'
        : 'I just scored Band $overallBand on "$title" with Linka IELTS practice! 🎉';
    await SharePlus.instance.share(ShareParams(files: [XFile(imageFile.path)], text: text));
  }
}
