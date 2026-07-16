import 'dart:io';
import 'package:flutter/material.dart';
import '../services/content_package_service.dart';

class SmartImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  const SmartImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ContentPackageService.instance.resolveLocalPath(url),
      builder: (context, snapshot) {
        final localPath = snapshot.data;

        if (localPath != null) {
          return Image.file(
            File(localPath),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.image_not_supported, color: Colors.grey),
          );
        }

        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.image_not_supported, color: Colors.grey),
        );
      },
    );
  }
}
