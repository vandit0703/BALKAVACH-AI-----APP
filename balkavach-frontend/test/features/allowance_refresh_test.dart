// How the child's allowance learns that a parent approved a mission. Provider
// level, with a fake repository: no grant is ever created here, the app only
// re-reads what the server says.

import 'package:balkavach_app/features/learning/data/video_feed_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements VideoFeedRepository {
  int calls = 0;

  @override
  Future<VideoAllowance> getAllowance() async {
    calls++;
    return VideoAllowance(
      childId: 'c',
      localDate: '2026-11-19',
      timezone: 'UTC',
      totalEarnedTodaySeconds: 900 * calls,
      consumedTodaySeconds: 0,
      remainingSeconds: 900 * calls,
      dailyCapSeconds: 4500,
      isExhausted: false,
      activeEntitlementsCount: calls,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppNotification _note(String id, String type) => AppNotification(
  id: id,
  type: type,
  title: 't',
  message: 'm',
  isRead: false,
  createdAt: DateTime(2026, 11, 19),
);

class _Notes extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => const [];

  void set(List<AppNotification> value) => state = value;
}

final _notesProvider = NotifierProvider<_Notes, List<AppNotification>>(
  _Notes.new,
);

ProviderContainer _container(_Repo repo) => ProviderContainer(
  overrides: [
    videoFeedRepositoryProvider.overrideWithValue(repo),
    childNotificationsProvider.overrideWith(
      (ref) async => ref.watch(_notesProvider),
    ),
  ],
);

Future<void> _settle(ProviderContainer c) async {
  await c.read(childNotificationsProvider.future);
  await c.read(videoAllowanceProvider.future);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'a new "video time unlocked" notification reloads the allowance',
    () async {
      final repo = _Repo();
      final c = _container(repo);
      addTearDown(c.dispose);
      c.listen(videoAllowanceProvider, (_, _) {});
      await _settle(c);
      expect(repo.calls, 1);

      c.read(_notesProvider.notifier).set([
        _note('1', 'mission_video_time_granted'),
      ]);
      await _settle(c);
      await _settle(c);
      expect(repo.calls, 2, reason: 'one new grant, one reload');
      expect(c.read(videoAllowanceProvider).value!.remainingSeconds, 1800);
    },
  );

  test('other notifications cause no extra allowance requests', () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    c.listen(videoAllowanceProvider, (_, _) {});
    await _settle(c);

    c.read(_notesProvider.notifier).set([
      _note('1', 'task_approved'),
      _note('2', 'streak_continued'),
    ]);
    await _settle(c);
    await _settle(c);
    expect(repo.calls, 1);
  });

  test('re-fetching the same notifications does not reload it again', () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    c.listen(videoAllowanceProvider, (_, _) {});
    c.read(_notesProvider.notifier).set([
      _note('1', 'mission_video_time_granted'),
    ]);
    await _settle(c);
    await _settle(c);
    final after = repo.calls;

    c.invalidate(childNotificationsProvider);
    await _settle(c);
    await _settle(c);
    expect(repo.calls, after);
  });
}
