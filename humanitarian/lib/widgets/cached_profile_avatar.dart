import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Local file takes precedence; otherwise loads [imageUrl] with cache and safe fallback.
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
    final path = localPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: backgroundColor,
          backgroundImage: FileImage(file),
        );
      }
    }

    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: placeholder,
      );
    }

    final size = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
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
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
