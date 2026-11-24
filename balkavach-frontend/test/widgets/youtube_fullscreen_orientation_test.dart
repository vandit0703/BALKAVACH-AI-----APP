import 'package:balkavach_app/features/learning/presentation/youtube_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

void main() {
  group('iframe fullscreen button and orientation', () {
    test('the fullscreen button (locked) turns the phone landscape', () {
      expect(
        youtubeFullscreenWantsLandscape(
          const FullScreenOption(enabled: true, locked: true),
        ),
        isTrue,
      );
    });

    test('fullscreen from physical rotation is not locked to landscape', () {
      expect(
        youtubeFullscreenWantsLandscape(const FullScreenOption(enabled: true)),
        isFalse,
      );
    });

    test('leaving fullscreen gives rotation back', () {
      expect(
        youtubeFullscreenWantsLandscape(
          const FullScreenOption(enabled: false, locked: true),
        ),
        isFalse,
      );
    });
  });
}
