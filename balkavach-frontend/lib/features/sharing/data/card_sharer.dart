import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Where "invite another parent" points. Set at build time with
/// `--dart-define=SHARE_URL=https://...`; empty means the message goes out
/// without a link. No store address is guessed.
const kShareUrl = String.fromEnvironment('SHARE_URL');

/// Seam over the system share sheet for a picture, so screens can be tested.
abstract interface class CardSharer {
  /// Shares [png] with [text]. Returns `false` when the share sheet could not
  /// be opened.
  Future<bool> shareImage(Uint8List png, {required String text});
}

class PlatformCardSharer implements CardSharer {
  const PlatformCardSharer();

  @override
  Future<bool> shareImage(Uint8List png, {required String text}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: text,
          files: [
            XFile.fromData(
              png,
              mimeType: 'image/png',
              name: 'bal-kavach-invite.png',
            ),
          ],
          fileNameOverrides: const ['bal-kavach-invite.png'],
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } on Object {
      return false;
    }
  }
}

final cardSharerProvider = Provider<CardSharer>(
  (ref) => const PlatformCardSharer(),
);
