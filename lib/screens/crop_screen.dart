import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

class CropScreen extends StatefulWidget {
  final File imageFile;
  final double aspectRatio;

  const CropScreen({
    super.key,
    required this.imageFile,
    this.aspectRatio = 3 / 2,
  });

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  Uint8List? _imageBytes;
  bool _cropping = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  // Decode the picked file through the platform's native codec (iOS ImageIO /
  // Android), which supports HEIC and EXIF orientation, then downscale oversized
  // images and re-encode to PNG. crop_your_image decodes with the Dart `image`
  // package, which can't read HEIC and chokes on huge images — feeding it
  // normalized PNG bytes avoids the black-screen / decode crash.
  Future<void> _loadImage() async {
    try {
      final raw = await widget.imageFile.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final int? targetWidth =
          descriptor.width > 2048 ? 2048 : null;
      final codec = await descriptor.instantiateCodec(targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      final pngData =
          await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      if (!mounted) return;
      setState(() => _imageBytes = pngData!.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Crop Photo',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _cropping || _imageBytes == null
                ? null
                : () {
                    setState(() => _cropping = true);
                    _controller.crop();
                  },
            child: _cropping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5C542)),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFFF5C542),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loadFailed
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not load this image. Please choose another.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ),
              )
            : _imageBytes == null
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFF5C542),
                    ),
                  )
                : Crop(
                    image: _imageBytes!,
          controller: _controller,
          aspectRatio: widget.aspectRatio,
          interactive: true,
          fixCropRect: true,
          baseColor: Colors.black,
          maskColor: Colors.black.withValues(alpha: 0.7),
          cornerDotBuilder: (size, edgeAlignment) => const SizedBox.shrink(),
          onCropped: (result) async {
            if (result is! CropSuccess) return;
            final tempDir = Directory.systemTemp;
            final file = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await file.writeAsBytes(result.croppedImage);
                      if (mounted) Navigator.pop(context, file);
                    },
                  ),
      ),
    );
  }
}
