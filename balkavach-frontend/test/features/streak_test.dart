import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:balkavach_app/features/progress/presentation/streak_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  group('StreakInfo and ChildProgress serialization', () {
    test('StreakInfo.fromJson parses all fields correctly', () {
      final json = {
        'child_id': 'child-123',
        'current_streak': 5,
        'longest_streak': 12,
        'streak_state': 'at_risk',
        'grace_deadline': '2026-11-15T18:30:00Z',
        'seconds_until_grace_expires': 3600,
        'last_activity_date': '2026-11-12',
        'last_activity_at': '2026-11-12T10:00:00Z',
      };

      final info = StreakInfo.fromJson(json);
      expect(info.childId, 'child-123');
      expect(info.currentStreak, 5);
      expect(info.longestStreak, 12);
      expect(info.streakState, 'at_risk');
      expect(info.secondsUntilExpiry, 3600);
      expect(info.graceDeadline, isNotNull);
      expect(info.lastActivityDate, isNotNull);
      expect(info.lastActivityAt, isNotNull);
    });

    test(
      'ChildProgress.fromJson parses streak fields gracefully when present',
      () {
        final json = {
          'child_id': 'child-456',
          'star_balance': 10,
          'total_xp': 150,
          'current_streak': 3,
          'longest_streak': 7,
          'streak_state': 'recovered',
          'grace_deadline': '2026-11-14T12:00:00Z',
          'seconds_until_grace_expires': 7200,
        };

        final progress = ChildProgress.fromJson(json);
        expect(progress.childId, 'child-456');
        expect(progress.currentStreak, 3);
        expect(progress.longestStreak, 7);
        expect(progress.streakState, 'recovered');
        expect(progress.secondsUntilExpiry, 7200);
        expect(progress.graceDeadline, isNotNull);
      },
    );

    test(
      'ChildProgress.fromJson defaults streak_state to active when omitted',
      () {
        final json = {
          'child_id': 'child-789',
          'star_balance': 0,
          'total_xp': 0,
          'current_streak': 0,
          'longest_streak': 0,
        };

        final progress = ChildProgress.fromJson(json);
        expect(progress.streakState, 'active');
        expect(progress.graceDeadline, isNull);
        expect(progress.secondsUntilExpiry, isNull);
      },
    );
  });

  group('StreakCard widget rendering', () {
    testWidgets('renders active streak with flame emoji and count', (
      tester,
    ) async {
      const info = StreakInfo(
        childId: 'c1',
        currentStreak: 4,
        longestStreak: 10,
        streakState: 'active',
      );

      await pumpScreen(
        tester,
        const Scaffold(body: StreakCard(streakInfo: info)),
        overrides: const [],
      );

      expect(find.text('4'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('Active Streak'), findsOneWidget);
      expect(find.text('Longest: 10 days'), findsOneWidget);
    });

    testWidgets('renders at_risk state with hourglass and countdown', (
      tester,
    ) async {
      const info = StreakInfo(
        childId: 'c1',
        currentStreak: 2,
        longestStreak: 5,
        streakState: 'at_risk',
        secondsUntilExpiry: 3600 * 25, // 1 day 1 hour
      );

      await pumpScreen(
        tester,
        const Scaffold(body: StreakCard(streakInfo: info)),
        overrides: const [],
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('⏳'), findsOneWidget);
      expect(find.text('Streak at Risk'), findsOneWidget);
      expect(find.textContaining('remaining'), findsOneWidget);
    });

    testWidgets(
      'renders broken state with broken heart and start new message',
      (tester) async {
        const info = StreakInfo(
          childId: 'c1',
          currentStreak: 0,
          longestStreak: 3,
          streakState: 'broken',
        );

        await pumpScreen(
          tester,
          const Scaffold(body: StreakCard(streakInfo: info)),
          overrides: const [],
        );

        expect(find.text('0'), findsOneWidget);
        expect(find.text('💔'), findsOneWidget);
        expect(find.text('Streak Broken'), findsOneWidget);
        expect(
          find.text('Complete a mission to start your streak!'),
          findsOneWidget,
        );
      },
    );

    testWidgets('triggers celebration animation when streak increases', (
      tester,
    ) async {
      const initial = StreakInfo(
        childId: 'c1',
        currentStreak: 3,
        longestStreak: 5,
        streakState: 'active',
      );
      const updated = StreakInfo(
        childId: 'c1',
        currentStreak: 4,
        longestStreak: 5,
        streakState: 'active',
      );

      await pumpScreen(
        tester,
        const Scaffold(body: StreakCard(streakInfo: initial)),
        overrides: const [],
      );

      expect(find.text('+1 Streak Extended!'), findsNothing);

      // Update widget with incremented streak
      await pumpScreen(
        tester,
        const Scaffold(body: StreakCard(streakInfo: updated)),
        overrides: const [],
      );

      expect(find.text('+1 Streak Extended!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('+1 Streak Extended!'), findsNothing);
    });
  });
}
