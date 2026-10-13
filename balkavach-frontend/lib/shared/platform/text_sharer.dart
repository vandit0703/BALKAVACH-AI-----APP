import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Seam over the platform share sheet so screens can be tested.
abstract interface class TextSharer {
  /// Opens the system share sheet. Returns `false` when it could not be opened.
  Future<bool> share(String text, {String? subject});
}

class PlatformTextSharer implements TextSharer {
  const PlatformTextSharer();

  @override
  Future<bool> share(String text, {String? subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: text, subject: subject),
      );
      return result.status != ShareResultStatus.unavailable;
    } on Exception {
      return false;
    }
  }
}

final textSharerProvider = Provider<TextSharer>(
  (ref) => const PlatformTextSharer(),
);
