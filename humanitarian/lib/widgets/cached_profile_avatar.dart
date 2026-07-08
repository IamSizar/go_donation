import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular profile avatar. Local file takes precedence, then the network URL,
/// then the placeholder. Every image path has an error fallback so a bad/half-
/// written file (e.g. right after picking a new photo) degrades gracefully
/// instead of throwing during paint and crash-restarting the app.
class CachedProfileAvatar extends StatelessWidget {
  const CachedProfileAvatar({
    super.key,
    this.localPath,
    this.imageUrl,
    required this.radius,
    required this.backgroundColor,
    required this.placeholder,
  });

  final String? localPath;
  final String? imageUrl;
  final double radius;
  final Color backgroundColor;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(child: _content()),
    );
  }

  // Prefer a local file; fall back to the network image on any decode error.
  Widget _content() {
    final path = localPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          // A corrupt/half-written file no longer crashes — fall through.
          errorBuilder: (_, __, ___) => _networkContent(),
        );
      }
    }
    return _networkContent();
  }

  Widget _networkContent() {
    final url = imageUrl;
    if (url == null || url.isEmpty) return _placeholderContent();
    return CachedNetworkImage(
      imageUrl: url,
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      placeholder: (_, __) => Center(
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _placeholderContent(),
    );
  }

  // Centered so the initial letter / person icon always sits in the middle.
  Widget _placeholderContent() => Center(child: placeholder);
}
