import 'package:balkavach_app/features/settings/presentation/parent_settings_screen.dart';
import 'package:balkavach_app/features/settings/presentation/settings_providers.dart';
import 'package:balkavach_app/shared/platform/device_time_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

class _FakeZone implements DeviceTimeZone {
  _FakeZone(this.zone);

  final String? zone;

  @override
  Future<String?> current() async => zone;
}

Map<String, Object?> _familySettings({
  String? timezone,
  Map<String, Object?>? mission,
}) => {
  'family_id': Fx.familyId,
  'default_language': 'en',
  'mission_settings': mission ?? {'timezone': ?timezone},
  'reward_settings': <String, Object?>{},
  'video_settings': {'enabled': true, 'default_daily_limit_seconds': 0},
  'updated_at': null,
};

const _path = '/api/v1/settings/families/${Fx.familyId}';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('looksLikeIanaZone accepts real zones and rejects junk', () {
    for (final ok in [
      'UTC',
      'Asia/Kolkata',
      'America/Argentina/Buenos_Aires',
      'Etc/GMT+5',
    ]) {
      expect(looksLikeIanaZone(ok), isTrue, reason: ok);
    }
    for (final bad in [
      '',
      'IST',
      'Asia',
      'Asia/Kolkata; DROP',
      '../etc/passwd',
    ]) {
      expect(looksLikeIanaZone(bad), isFalse, reason: bad);
    }
  });

  group('automatic time zone', () {
    test('a family without a zone gets this phone\'s zone, once', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend
        ..reply('GET', _path, _familySettings())
        ..on(
          'PATCH',
          _path,
          (_) => FakeReply(200, _familySettings(timezone: 'Asia/Kolkata')),
        );
      final container = containerWithZone(h, _FakeZone('Asia/Kolkata'));
      expect(
        await container.read(familyTimezoneSyncProvider(Fx.familyId).future),
        'Asia/Kolkata',
      );
      final patch = h.backend.requestsTo('PATCH', _path).single.data as Map;
      expect((patch['mission_settings'] as Map)['timezone'], 'Asia/Kolkata');
    });

    test('never overwrites a zone a parent chose', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', _path, _familySettings(timezone: 'Europe/London'));
      final container = containerWithZone(h, _FakeZone('Asia/Kolkata'));
      expect(
        await container.read(familyTimezoneSyncProvider(Fx.familyId).future),
        'Europe/London',
      );
      expect(h.backend.requestsTo('PATCH', _path), isEmpty);
    });

    test('keeps other mission settings when saving the zone', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend
        ..reply('GET', _path, _familySettings(mission: {'daily_goal': 3}))
        ..on(
          'PATCH',
          _path,
          (_) => FakeReply(
            200,
            _familySettings(
              mission: {'daily_goal': 3, 'timezone': 'Asia/Kolkata'},
            ),
          ),
        );
      final container = containerWithZone(h, _FakeZone('Asia/Kolkata'));
      await container.read(familyTimezoneSyncProvider(Fx.familyId).future);
      final sent =
          (h.backend.requestsTo('PATCH', _path).single.data
              as Map)['mission_settings'];
      expect(sent, {'daily_goal': 3, 'timezone': 'Asia/Kolkata'});
    });

    test('an unknown device zone is not sent', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.reply('GET', _path, _familySettings());
      final container = containerWithZone(h, _FakeZone(null));
      expect(
        await container.read(familyTimezoneSyncProvider(Fx.familyId).future),
        isNull,
      );
      expect(h.backend.requestsTo('PATCH', _path), isEmpty);
    });

    test(
      'a refusal from the server leaves UTC in force instead of failing',
      () async {
        final h = await Harness.create(session: Fx.parentSession());
        h.backend
          ..reply('GET', _path, _familySettings())
          ..on(
            'PATCH',
            _path,
            (_) => FakeReply.error(422, 'validation_error', 'bad'),
          );
        final container = containerWithZone(h, _FakeZone('Asia/Kolkata'));
        expect(
          await container.read(familyTimezoneSyncProvider(Fx.familyId).future),
          isNull,
        );
      },
    );
  });

  group('settings screen', () {
    Future<Harness> pump(
      WidgetTester tester, {
      String? zone,
      String? device = 'Asia/Dubai',
    }) async {
      final h = await Harness.create(
        session: Fx.parentSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/settings/me', Fx.userSettings())
        ..reply('GET', _path, _familySettings(timezone: zone))
        ..on(
          'PATCH',
          _path,
          (o) => FakeReply(
            200,
            _familySettings(
              timezone:
                  ((o.data as Map)['mission_settings'] as Map)['timezone']
                      as String,
            ),
          ),
        )
        ..reply('GET', '$_path/consents', <Object?>[]);
      await pumpScreen(
        tester,
        const ParentSettingsScreen(),
        overrides: [
          ...h.overrides,
          deviceTimeZoneProvider.overrideWithValue(_FakeZone(device)),
        ],
      );
      return h;
    }

    testWidgets('shows the family zone and lets the parent change it', (
      tester,
    ) async {
      final h = await pump(tester, zone: 'Asia/Kolkata');
      expect(find.text('Asia/Kolkata'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('settings.timezone')));
      await _tap(
        tester,
        find.byKey(const Key('settings.timezone.Europe/London')),
      );
      final patch = h.backend.requestsTo('PATCH', _path).single.data as Map;
      expect((patch['mission_settings'] as Map)['timezone'], 'Europe/London');
      expect(find.text('Time zone saved'), findsOneWidget);
    });

    testWidgets('offers this phone\'s zone when it differs', (tester) async {
      final h = await pump(tester, zone: 'Asia/Kolkata');
      await _tap(tester, find.byKey(const Key('settings.timezone')));
      expect(
        find.text("Use this phone's time zone (Asia/Dubai)"),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('settings.timezone.device')));
      expect(
        ((h.backend.requestsTo('PATCH', _path).single.data
                as Map)['mission_settings']
            as Map)['timezone'],
        'Asia/Dubai',
      );
    });

    testWidgets(
      'email is honest: stored setting with no delivery is not a switch',
      (tester) async {
        await pump(tester, zone: 'Asia/Kolkata');
        expect(
          find.byType(SwitchListTile),
          findsOneWidget,
          reason: 'only push is a working switch',
        );
        expect(
          find.text("Bal Kavach doesn't send emails yet."),
          findsOneWidget,
        );
      },
    );

    testWidgets('states what is stored where and the safety promises', (
      tester,
    ) async {
      await pump(tester, zone: 'Asia/Kolkata');
      await tester.ensureVisible(find.byKey(const Key('settings.safety')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saved on this phone only'), findsOneWidget);
      expect(find.textContaining('Saved to your account'), findsOneWidget);
      expect(find.text('Bal Kavach shows no ads.'), findsOneWidget);
    });
  });
}

/// A container whose device zone is faked.
ProviderContainer containerWithZone(Harness h, DeviceTimeZone zone) {
  final container = ProviderContainer(
    overrides: [...h.overrides, deviceTimeZoneProvider.overrideWithValue(zone)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}
