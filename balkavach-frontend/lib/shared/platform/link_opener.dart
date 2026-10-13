import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Seam over the platform so opening a link can be faked in tests.
abstract interface class LinkOpener {
  /// Opens [uri] outside the app (the browser or the video app). Returns
  /// `false` when nothing could open it.
  Future<bool> open(Uri uri);
}

/// Opens links in the user's own browser or the YouTube app. Content is never
/// downloaded or embedded, so each platform's own terms apply to playback.
class PlatformLinkOpener implements LinkOpener {
  const PlatformLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    if (uri.scheme != 'https') return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

final linkOpenerProvider = Provider<LinkOpener>(
  (ref) => const PlatformLinkOpener(),
);
