import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../widgets/app_notify.dart';
import '../utils/format.dart';

class StoryUploadScreen extends StatefulWidget {
  const StoryUploadScreen({super.key});

  @override
  State<StoryUploadScreen> createState() => _StoryUploadScreenState();
}

class _StoryUploadScreenState extends State<StoryUploadScreen> {
  File? _media;
  bool _isVideo = false;
  int? _mediaSize;
  VideoPlayerController? _videoController;
  final _descController = TextEditingController();
  bool _uploading = false;
  double _progress = 0;

  @override
  void dispose() {
    _videoController?.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source, {required bool video}) async {
    final picker = ImagePicker();
    final XFile? file;

    if (video) {
      file = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    } else {
      file = await picker.pickImage(source: source, imageQuality: 85);
    }

    if (file == null || !mounted) return;

    final mediaFile = File(file.path);
    final mediaSize = await mediaFile.length();

    _videoController?.dispose();
    _videoController = null;

    if (video) {
      final controller = VideoPlayerController.file(mediaFile);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.setLooping(true);
      controller.play();
      setState(() {
        _media = mediaFile;
        _mediaSize = mediaSize;
        _isVideo = true;
        _videoController = controller;
      });
    } else {
      setState(() {
        _media = mediaFile;
        _mediaSize = mediaSize;
        _isVideo = false;
      });
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _SheetOption(
              icon: Icons.photo_library_outlined,
              label: 'Photo from gallery',
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.gallery, video: false);
              },
            ),
            _SheetOption(
              icon: Icons.videocam_outlined,
              label: 'Video from gallery',
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.gallery, video: true);
              },
            ),
            _SheetOption(
              icon: Icons.camera_alt_outlined,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.camera, video: false);
              },
            ),
            _SheetOption(
              icon: Icons.videocam_outlined,
              label: 'Record a video',
              onTap: () {
                Navigator.pop(context);
                _pickMedia(ImageSource.camera, video: true);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _upload() async {
    if (_media == null || _uploading) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });

    try {
      // Stream the media straight from disk so large videos are never loaded
      // into memory whole (unlike the old base64-in-JSON approach).
      await ApiService.postMultipart(
        '/tutor/stories/',
        files: {'media_file': _media!},
        fields: {
          if (_descController.text.trim().isNotEmpty)
            'description': _descController.text.trim(),
        },
        onProgress: (sent, total) {
          if (!mounted || total <= 0) return;
          final next = sent / total;
          if ((next - _progress).abs() < 0.01 && next < 1.0) return;
          setState(() => _progress = next);
        },
      );

      if (!mounted) return;
      AppNotify.show(context,
        message: 'Story uploaded!',
        type: NotifyType.success,
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppNotify.show(context, message: e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _toggleVideoPlayback() {
    if (_videoController == null) return;
    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  void _handleBack() {
    if (_uploading) {
      AppNotify.show(context,
          message: 'Upload in progress — please keep the app open');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_uploading) return;
        AppNotify.show(context,
            message: 'Upload in progress — please keep the app open');
      },
      child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: _handleBack,
          ),
          title: const Text(
            'New Story',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: _media == null ? _buildPicker() : _buildPreview(),
        ),
      ),
      ),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: GestureDetector(
        onTap: _showPickerSheet,
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF333333), width: 2),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: Color(0xFFF5C542), size: 48),
              SizedBox(height: 12),
              Text(
                'Add photo or video',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        // Media preview
        Expanded(
          child: GestureDetector(
            onTap: _isVideo ? _toggleVideoPlayback : _showPickerSheet,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isVideo && _videoController != null)
                  Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  )
                else if (_media != null)
                  Center(
                    child: Image.file(
                      _media!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),

                // Play/pause overlay for video
                if (_isVideo && _videoController != null && !_videoController!.value.isPlaying)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),

                // Change media button
                Positioned(
                  top: 12,
                  right: 16,
                  child: GestureDetector(
                    onTap: _showPickerSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Upload progress bar
        if (_uploading)
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (_progress == 0 || _progress >= 1.0)
                              ? null
                              : _progress,
                          minHeight: 4,
                          backgroundColor: const Color(0xFF2A2A2A),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFF5C542),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _progress == 0
                          ? 'Preparing…'
                          : _progress >= 1.0
                              ? 'Processing…'
                              : '${(_progress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (_mediaSize != null && _mediaSize! > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    _progress <= 0
                        ? formatBytes(_mediaSize!)
                        : '${formatBytes((_progress.clamp(0.0, 1.0) * _mediaSize!).round())} of ${formatBytes(_mediaSize!)}',
                    style: const TextStyle(
                      color: Color(0xFF8A8A99),
                      fontSize: 11,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFF5C542), size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Keep the app open — leaving now will cancel the upload.',
                        style: TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // Description + share button
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _descController,
                  enabled: !_uploading,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 1,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Add a description...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _uploading ? null : _upload,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5C542),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _uploading
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: (_progress == 0 || _progress >= 1.0)
                                ? null
                                : _progress,
                            color: const Color(0xFF272942),
                            backgroundColor:
                                const Color(0xFF272942).withValues(alpha: 0.2),
                          ),
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF272942),
                          size: 24,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Bottom sheet option ──────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF272942), size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF272942),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
