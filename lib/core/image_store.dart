import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// تخزين الصور محلياً داخل مجلد التطبيق. يُحفظ المسار نسبياً ليسهل النسخ الاحتياطي.
class ImageStore {
  static Future<Directory> _root([String folder = 'order_images']) async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}/$folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> saveBytes(Uint8List bytes,
      {String folder = 'order_images', String ext = '.png'}) async {
    final dir = await _root(folder);
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    await File('${dir.path}/$name').writeAsBytes(bytes, flush: true);
    return '$folder/$name';
  }

  static Future<String> save(String sourcePath,
      {String folder = 'order_images'}) async {
    final dir = await _root(folder);
    final ext =
        RegExp(r'\.[A-Za-z0-9]{1,5}$').firstMatch(sourcePath)?.group(0) ?? '.jpg';
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(sourcePath).copy('${dir.path}/$name');
    return '$folder/$name';
  }

  static Future<File> resolve(String relativePath) async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/$relativePath');
  }
}

class StoredImage extends StatelessWidget {
  const StoredImage({super.key, required this.path, this.height = 160});
  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: ImageStore.resolve(path),
      builder: (context, snap) {
        final f = snap.data;
        if (f == null) return SizedBox(height: height);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            f,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => SizedBox(
              height: height,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        );
      },
    );
  }
}
