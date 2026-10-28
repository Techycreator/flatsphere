import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const maxUploadBytes = 5 * 1024 * 1024;
const maxOriginalImageBytes = 30 * 1024 * 1024;
const _targetImageBytes = 4500 * 1024;
const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

int maxSourceUploadBytes(String extension) =>
    _imageExtensions.contains(extension.toLowerCase().replaceFirst('.', '')) ? maxOriginalImageBytes : maxUploadBytes;

class PreparedUpload {
  const PreparedUpload({required this.bytes, required this.extension, required this.contentType});

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

Future<PreparedUpload> prepareUpload(Uint8List source, String extension) async {
  final normalized = extension.toLowerCase().replaceFirst('.', '');
  if (source.isEmpty) throw ArgumentError.value(source.length, 'source', 'File is empty');
  if (_imageExtensions.contains(normalized)) {
    if (source.length > maxOriginalImageBytes) {
      throw ArgumentError.value(source.length, 'source', 'Photo must be 30 MB or smaller before compression');
    }
    final compressed = await compute(_compressImage, source);
    if (compressed.length > maxUploadBytes) {
      throw ArgumentError.value(compressed.length, 'source', 'Compressed photo exceeds the 5 MB upload limit');
    }
    return PreparedUpload(bytes: compressed, extension: 'jpg', contentType: 'image/jpeg');
  }
  if (normalized != 'pdf') {
    throw ArgumentError.value(extension, 'extension', 'Only JPG, PNG, WebP, and PDF files are supported');
  }
  if (source.length > maxUploadBytes) {
    throw ArgumentError.value(source.length, 'source', 'PDF must be 5 MB or smaller');
  }
  return PreparedUpload(bytes: source, extension: 'pdf', contentType: 'application/pdf');
}

Uint8List _compressImage(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const FormatException('This image format could not be read');
  final oriented = img.bakeOrientation(decoded);
  for (final dimension in const [1600, 1280, 1024, 800]) {
    final resized = oriented.width > dimension || oriented.height > dimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? dimension : null,
            height: oriented.height > oriented.width ? dimension : null,
          )
        : oriented;
    for (final quality in const [85, 75, 65, 55, 45]) {
      final result = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (result.length <= _targetImageBytes) return result;
    }
  }
  final smallest = Uint8List.fromList(
    img.encodeJpg(
      img.copyResize(oriented, width: 640, height: oriented.height > oriented.width ? 640 : null),
      quality: 35,
    ),
  );
  return smallest;
}
