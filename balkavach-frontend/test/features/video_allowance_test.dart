import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/learning/presentation/widgets/video_allowance_card.dart';
import 'package:balkavach_app/features/learning/presentation/widgets/video_time_exhausted_dialog.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoAllowance Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'child_id': 'child-123',
        'local_date': '2026-11-13',
        'timezone': 'Asia/Kolkata',
        'total_earned_today_seconds': 1800,
        'consumed_today_seconds': 600,
        'remaining_seconds': 1200,
        'daily_cap_seconds': 3600,
        'is_exhausted': false,
        'active_entitlements_count': 2,
      };

      final allowance = VideoAllowance.fromJson(json);

      assert(allowance.childId == 'child-123');
      assert(allowance.localDate == '2026-11-13');
      assert(allowance.timezone == 'Asia/Kolkata');
      assert(allowance.totalEarnedTodaySeconds == 1800);
      assert(allowance.consumedTodaySeconds == 600);
      assert(allowance.remainingSeconds == 1200);
      assert(allowance.dailyCapSeconds == 3600);
      assert(allowance.isExhausted == false);
      assert(allowance.activeEntitlementsCount == 2);
      assert(allowance.remainingMinutes == 20);
    });

    test('remainingMinutes rounds up for partial minutes', () {
      final allowance = VideoAllowance.fromJson({
        'child_id': 'child-123',
        'local_date': '2026-11-13',
        'timezone': 'UTC',
        'total_earned_today_seconds': 900,
        'consumed_today_seconds': 100,
        'remaining_seconds': 800,
        'daily_cap_seconds': 3600,
        'is_exhausted': false,
        'active_entitlements_count': 1,
      });

      assert(allowance.remainingMinutes == 14); // 800 / 60 = 13.33 -> 14
    });
  });

  group('VideoAllowanceCard Widget', () {
    Future<void> pumpCard(WidgetTester tester, VideoAllowance allowance) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoAllowanceProvider.overrideWith(
              (ref) => Future.value(allowance),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: VideoAllowanceCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('900 earned mission seconds show as 15 minutes, with no free '
        'allowance line', (tester) async {
      // Free daily allowance is zero; one approved mission granted 900 s.
      await pumpCard(
        tester,
        const VideoAllowance(
          childId: 'child-123',
          localDate: '2026-11-13',
          timezone: 'UTC',
          totalEarnedTodaySeconds: 900,
          consumedTodaySeconds: 0,
          remainingSeconds: 900,
          dailyCapSeconds: 3600,
          isExhausted: false,
          activeEntitlementsCount: 1,
          missionRemainingSeconds: 900,
        ),
      );

      expect(find.byKey(const Key('watch.allowance.card')), findsOneWidget);
      expect(find.text('15m video time left today'), findsOneWidget);
      expect(find.text('Mission video: 15 extra minutes'), findsOneWidget);
      expect(find.byKey(const Key('watch.allowance.free')), findsNothing);
      expect(find.textContaining('Daily free video'), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    });

    testWidgets('earned time carried over from an earlier day still shows', (
      tester,
    ) async {
      // Nothing earned today, but 600 s of an earlier grant are unused.
      await pumpCard(
        tester,
        const VideoAllowance(
          childId: 'child-123',
          localDate: '2026-11-14',
          timezone: 'UTC',
          totalEarnedTodaySeconds: 0,
          consumedTodaySeconds: 0,
          remainingSeconds: 600,
          dailyCapSeconds: 3600,
          isExhausted: false,
          activeEntitlementsCount: 1,
          missionRemainingSeconds: 600,
        ),
      );

      expect(find.text('10m video time left today'), findsOneWidget);
      expect(find.textContaining('Daily free video'), findsNothing);
    });

    testWidgets('zero free allowance and no earned time: locked, no free '
        'minutes are suggested', (tester) async {
      await pumpCard(
        tester,
        const VideoAllowance(
          childId: 'child-123',
          localDate: '2026-11-13',
          timezone: 'UTC',
          totalEarnedTodaySeconds: 0,
          consumedTodaySeconds: 0,
          remainingSeconds: 0,
          dailyCapSeconds: 3600,
          isExhausted: true,
          activeEntitlementsCount: 0,
        ),
      );

      expect(find.byKey(const Key('watch.allowance.card')), findsOneWidget);
      expect(find.text('Video time locked'), findsOneWidget);
      expect(find.textContaining('Daily free video'), findsNothing);
      expect(find.textContaining('15'), findsNothing);
      expect(
        find.byKey(const Key('watch.allowance.toMissions')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_clock_rounded), findsOneWidget);
    });

    testWidgets('a free allowance is shown only when the server reports one, '
        'with the server total', (tester) async {
      // An older server that still grants free time reports it explicitly;
      // the card shows the server's own numbers, never a fixed 15.
      await pumpCard(
        tester,
        VideoAllowance.fromJson(const {
          'child_id': 'child-123',
          'local_date': '2026-11-13',
          'timezone': 'UTC',
          'total_earned_today_seconds': 600,
          'consumed_today_seconds': 0,
          'remaining_seconds': 600,
          'free_allowance_seconds': 600,
          'free_remaining_seconds': 300,
          'daily_cap_seconds': 3600,
          'is_exhausted': false,
          'active_entitlements_count': 0,
        }),
      );

      expect(
        find.text('Daily free video: 5 of 10 minutes left'),
        findsOneWidget,
      );
    });
  });

  group('VideoAllowance free allowance parsing', () {
    test('a response without free fields means no free allowance', () {
      final allowance = VideoAllowance.fromJson(const {
        'child_id': 'child-123',
        'local_date': '2026-11-13',
        'remaining_seconds': 0,
        'is_exhausted': true,
        'active_entitlements_count': 0,
      });
      expect(allowance.freeAllowanceSeconds, 0);
      expect(allowance.freeRemainingSeconds, 0);
      expect(allowance.remainingSeconds, 0);
    });
  });

  group('VideoTimeExhaustedDialog', () {
    testWidgets('renders dialog with missions action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showVideoTimeExhaustedDialog(context),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Video time is done for today'), findsOneWidget);
      expect(
        find.byKey(const Key('video.exhausted.toMissions')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('video.exhausted.close')), findsOneWidget);

      await tester.tap(find.byKey(const Key('video.exhausted.close')));
      await tester.pumpAndSettle();

      expect(find.text('Video time is done for today'), findsNothing);
    });
  });
}
