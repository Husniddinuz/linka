import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/api_service.dart';
import '../widgets/app_notify.dart';

class StoryUploadScreen extends StatefulWidget {
  const StoryUploadScreen({super.key});

  @override
  State<StoryUploadScreen> createState() => _StoryUploadScreenState();
}

class _StoryUploadScreenState extends State<StoryUploadScreen> {
  File? _media;
  bool _isVideo = false;
  VideoPlayerController? _videoController;
  final _descController = TextEditingController();
  bool _uploading = false;

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

    _videoController?.dispose();
    _videoController = null;

    final mediaFile = File(file.path);

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
        _isVideo = true;
        _videoController = controller;
      });
    } else {
      setState(() {
        _media = mediaFile;
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
    setState(() => _uploading = true);

    try {
      await ApiService.postMultipart(
        '/student/stories/',
        files: {'file': _media!},
        fields: {
          if (_descController.text.trim().isNotEmpty)
            'description': _descController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            onPressed: () => Navigator.of(context).pop(),
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

        // Description + share button
        Container(
          color: const Color(0xFF1A1A1A),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _descController,
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
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF272942),
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
