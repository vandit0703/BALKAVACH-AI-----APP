import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/features/learning/data/playback_guard.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, dynamic>?> _ok() async => {
  'remaining_allowance_seconds': 600,
  'is_exhausted': false,
};

Future<Map<String, dynamic>?> _fail(ApiException e) async => throw e;

void main() {
  group('PlaybackGuard', () {
    test('a good answer is ok and carries the server remaining time', () async {
      final report = await PlaybackGuard().report(_ok);
      expect(report.verdict, PlaybackVerdict.ok);
      expect(report.remainingSeconds, 600);
    });

    test('is_exhausted from the server stops playback', () async {
      final report = await PlaybackGuard().report(
        () async => {'remaining_allowance_seconds': 0, 'is_exhausted': true},
      );
      expect(report.verdict, PlaybackVerdict.exhausted);
      expect(report.remainingSeconds, 0);
    });

    test('a 403 (video_time_exhausted) stops playback', () async {
      final report = await PlaybackGuard().report(
        () => _fail(
          const ForbiddenException(
            message: 'used up',
            code: 'video_time_exhausted',
          ),
        ),
      );
      expect(report.verdict, PlaybackVerdict.exhausted);
    });

    test('one failure is tolerated, the second in a row pauses', () async {
      final guard = PlaybackGuard();
      final first = await guard.report(() => _fail(const NetworkException()));
      final second = await guard.report(() => _fail(const NetworkException()));
      expect(first.verdict, PlaybackVerdict.ok);
      expect(second.verdict, PlaybackVerdict.offline);
    });

    test('timeouts and server errors count as failures too', () async {
      final guard = PlaybackGuard();
      await guard.report(() => _fail(const RequestTimeoutException()));
      final second = await guard.report(
        () => _fail(const ServerException(message: 'x', statusCode: 503)),
      );
      expect(second.verdict, PlaybackVerdict.offline);
    });

    test('a success in between resets the count', () async {
      final guard = PlaybackGuard();
      await guard.report(() => _fail(const NetworkException()));
      await guard.report(_ok);
      final third = await guard.report(() => _fail(const NetworkException()));
      expect(third.verdict, PlaybackVerdict.ok);
      expect(guard.consecutiveFailures, 1);
    });

    test('stays offline until the server answers', () async {
      final guard = PlaybackGuard();
      for (var i = 0; i < 5; i++) {
        final r = await guard.report(() => _fail(const NetworkException()));
        if (i >= 1) expect(r.verdict, PlaybackVerdict.offline);
      }
      expect((await guard.report(_ok)).verdict, PlaybackVerdict.ok);
    });

    test('an expired session is signed out, never free time', () async {
      final report = await PlaybackGuard().report(
        () => _fail(const UnauthorizedException(message: 'expired')),
      );
      expect(report.verdict, PlaybackVerdict.signedOut);
    });
  });
}
