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
    testWidgets(
      'displays active remaining time badge when allowance is active',
      (tester) async {
        const activeAllowance = VideoAllowance(
          childId: 'child-123',
          localDate: '2026-11-13',
          timezone: 'UTC',
          totalEarnedTodaySeconds: 900,
          consumedTodaySeconds: 0,
          remainingSeconds: 900,
          dailyCapSeconds: 3600,
          isExhausted: false,
          activeEntitlementsCount: 1,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              videoAllowanceProvider.overrideWith(
                (ref) => Future.value(activeAllowance),
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

        expect(find.byKey(const Key('watch.allowance.card')), findsOneWidget);
        expect(
          find.textContaining('15m video time left today'),
          findsOneWidget,
        );
        expect(
          find.text('Daily free video: 15 of 15 minutes left'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'displays locked message and mission action when allowance is exhausted',
      (tester) async {
        const exhaustedAllowance = VideoAllowance(
          childId: 'child-123',
          localDate: '2026-11-13',
          timezone: 'UTC',
          totalEarnedTodaySeconds: 900,
          consumedTodaySeconds: 900,
          remainingSeconds: 0,
          dailyCapSeconds: 3600,
          isExhausted: true,
          activeEntitlementsCount: 0,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              videoAllowanceProvider.overrideWith(
                (ref) => Future.value(exhaustedAllowance),
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

        expect(find.byKey(const Key('watch.allowance.card')), findsOneWidget);
        expect(find.text('Video time locked'), findsOneWidget);
        expect(
          find.text('Daily free video: 0 of 15 minutes left'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('watch.allowance.toMissions')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.lock_clock_rounded), findsOneWidget);
      },
    );
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
