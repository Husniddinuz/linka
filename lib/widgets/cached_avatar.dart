import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/image_cache_service.dart';

class CachedAvatar extends StatefulWidget {
  final String? imageUrl;
  final double size;

  const CachedAvatar({super.key, this.imageUrl, required this.size});

  @override
  State<CachedAvatar> createState() => _CachedAvatarState();
}

class _CachedAvatarState extends State<CachedAvatar> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CachedAvatar old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _load();
  }

  Future<void> _load() async {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) return;
    final img = await ImageCacheService.getImage(widget.imageUrl!);
    if (mounted) setState(() => _image = img);
  }

  @override
  Widget build(BuildContext context) {
    if (_image != null) {
      return ClipOval(
        child: Image(
          image: _image!,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
        ),
      );
    }

    return SvgPicture.asset(
      'assets/images/branding/blank-avatar.svg',
      width: widget.size,
      height: widget.size,
    );
  }
}
