import 'dart:io';
import 'dart:typed_data';
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
  late final Uint8List _imageBytes;
  bool _cropping = false;

  @override
  void initState() {
    super.initState();
    _imageBytes = widget.imageFile.readAsBytesSync();
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
            onPressed: _cropping
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
        child: Crop(
          image: _imageBytes,
          controller: _controller,
          aspectRatio: widget.aspectRatio,
          interactive: true,
          fixCropRect: true,
          baseColor: Colors.black,
          maskColor: Colors.black.withValues(alpha: 0.7),
          cornerDotBuilder: (size, edgeAlignment) => const SizedBox.shrink(),
          onCropped: (croppedBytes) async {
            final tempDir = Directory.systemTemp;
            final file = File('${tempDir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg');
            await file.writeAsBytes(croppedBytes);
            if (mounted) Navigator.pop(context, file);
          },
        ),
      ),
    );
  }
}
