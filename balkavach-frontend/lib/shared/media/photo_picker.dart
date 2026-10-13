import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// A photo the user chose, held in memory until it is sent.
@immutable
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// Seam over the platform camera/gallery so screens can be tested.
abstract interface class PhotoPicker {
  /// Returns `null` when the user cancels. Throws [PhotoPickException] when
  /// the platform refuses (for example a denied permission).
  Future<PickedPhoto?> pick(PhotoSource source);
}

class PhotoPickException implements Exception {
  const PhotoPickException();
}

/// Uses `image_picker`. Photos are downscaled on the device before upload to
/// keep mobile data use low; the server re-encodes and strips location data.
class PlatformPhotoPicker implements PhotoPicker {
  PlatformPhotoPicker([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      return PickedPhoto(
        bytes: bytes,
        fileName: file.name.isEmpty ? 'photo.jpg' : file.name,
        mimeType: mimeTypeFor(file.name, file.mimeType),
      );
    } on Exception {
      throw const PhotoPickException();
    }
  }

  /// Only the types the server accepts; anything else is sent as JPEG and
  /// rejected by the server's content check if it is not an image.
  @visibleForTesting
  static String mimeTypeFor(String name, String? reported) {
    final lower = name.toLowerCase();
    if (reported == 'image/png' || lower.endsWith('.png')) return 'image/png';
    if (reported == 'image/webp' || lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => PlatformPhotoPicker(),
);
