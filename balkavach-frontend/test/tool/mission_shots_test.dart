// Screenshot tool (skipped unless SHOTS_DIR is given): renders the Missions and
// Mission detail screens with realistic fake data and writes PNGs.
//
//   flutter test test/tool/mission_shots_test.dart --dart-define=SHOTS_DIR=<dir> --dart-define=SHOTS_TAG=old
import 'dart:io';
import 'dart:ui' as ui;

import 'package:balkavach_app/features/missions/presentation/child_shell.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/features/missions/presentation/missions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

const _dir = String.fromEnvironment('SHOTS_DIR');
const _tag = String.fromEnvironment('SHOTS_TAG', defaultValue: 'shot');

const _catLearn = '66666666-6666-4666-8666-666666666666';
const _catMove = '66666666-6666-4666-8666-666666666667';
const _catHelp = '66666666-6666-4666-8666-666666666668';
const _catCreate = '66666666-6666-4666-8666-666666666669';

String _t(int n) => '55555555-5555-4555-8555-5555555555b$n';

Map<String, Object?> _cat(String id, String name, String icon) => {
  'id': id,
  'name': name,
  'description': null,
  'icon_name': icon,
  'is_default': true,
};

Map<String, Object?> _assignment(
  String id,
  Map<String, Object?> content, {
  String status = 'available',
  String? taskId,
  String date = '2026-10-12',
  int slot = 1,
}) => {
  'id': id,
  'local_date': date,
  'choice_slot': slot,
  'age_band': '7_10',
  'status': status,
  'task_id': taskId,
  'content': content,
};

Map<String, Object?> _content(
  String title,
  String description, {
  int minutes = 12,
  bool surprise = false,
}) => {
  'title': title,
  'description': description,
  'instructions': '1. Do it.',
  'required_materials': ['paper'],
  'duration_minutes': minutes,
  'safety_instructions': 'Stay safe.',
  'completion_criteria': 'Done.',
  'mission_type': 'offline',
  'theme': 'monday_sound_detective',
  'star_reward': 10,
  'xp_reward': 15,
  'is_surprise': surprise,
  'locale': 'en',
};

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync()),
        ),
      );
    }
    await loader.load();
  }

  await load('Rubik', [
    'Rubik-Regular.ttf',
    'Rubik-Medium.ttf',
    'Rubik-SemiBold.ttf',
    'Rubik-Bold.ttf',
  ]);
  await load('NunitoSans', [
    'NunitoSans-Regular.ttf',
    'NunitoSans-SemiBold.ttf',
    'NunitoSans-Bold.ttf',
  ]);
  final icons = File(
    '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final images = <ImageProvider>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Image) images.add(w.image);
      e.visitChildren(visit);
    }

    tester.binding.rootElement!.visitChildren(visit);
    final ctx = tester.element(find.byType(Scaffold).first);
    for (final i in images) {
      await precacheImage(i, ctx);
    }
  });
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(milliseconds: 1500));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File('$_dir/${_tag}_$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<Harness> _scenario({required bool withData}) async {
  final h = await Harness.create(
    session: Fx.childSession(),
    prefs: onboardedPrefs,
  );
  h.backend.reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson());
  if (!withData) {
    h.backend
      ..reply('GET', '/api/v1/tasks', <Object?>[])
      ..reply('GET', '/api/v1/daily-missions/today', {
        'local_date': '2026-10-12',
        'timezone': 'Asia/Kolkata',
        'age_band': '7_10',
        'selected_assignment_id': null,
        'choices': <Object?>[],
      })
      ..reply('GET', '/api/v1/daily-missions/unfinished', <Object?>[]);
    return h;
  }
  h.backend
    ..reply('GET', '/api/v1/tasks/categories', [
      _cat(_catLearn, 'Learn', 'menu_book'),
      _cat(_catMove, 'Move', 'directions_run'),
      _cat(_catHelp, 'Help', 'volunteer'),
      _cat(_catCreate, 'Create', 'palette'),
    ])
    ..reply(
      'GET',
      '/api/v1/tasks',
      _standard([
        Fx.task(
          id: _t(1),
          title: 'Read a Storybook',
          description:
              'Read one story and tell us your favourite part.\n\n'
              '1. Pick a storybook you like.\n'
              '2. Read it out loud, or with a grown-up.\n'
              '3. Draw your favourite part.\n'
              'Another way: listen to the story and say your favourite part.\n\n'
              'A drawing of the favourite part.\n'
              'Parent check: ask why that part was the best.',
          categoryId: _catLearn,
          stars: 10,
        ),
        Fx.task(
          id: _t(2),
          title: 'Play Outdoors or Yoga',
          description: 'Move your body for ten minutes outside.',
          categoryId: _catMove,
          stars: 10,
        ),
        Fx.task(
          id: _t(3),
          title: 'Help Clean Your Study Table',
          description: 'Tidy up the books and wipe the desk.',
          categoryId: _catHelp,
          stars: 10,
        ),
        Fx.task(
          id: _t(4),
          title: 'Draw Something Creative',
          description: 'Draw anything you like and show a grown-up.',
          categoryId: _catCreate,
          stars: 10,
        ),
        Fx.task(
          id: _t(5),
          title: 'Water the Plants',
          description: 'Give each plant a little water.',
          categoryId: _catHelp,
          stars: 10,
        ),
      ]),
    )
    ..reply('GET', '/api/v1/tasks/submissions/mine', [
      {
        ...Fx.submission(
          id: '77777777-7777-4777-8777-7777777777b1',
          taskId: _t(5),
          status: 'approved',
        ),
        'stars_awarded': 10,
        'xp_awarded': 15,
      },
      Fx.submission(
        id: '77777777-7777-4777-8777-7777777777b2',
        taskId: _t(3),
        status: 'pending',
      ),
      Fx.submission(
        id: '77777777-7777-4777-8777-7777777777b3',
        taskId: _t(2),
        status: 'rejected',
      ),
    ])
    ..reply(
      'GET',
      '/api/v1/progress/children/${Fx.childId}',
      Fx.progress(
        activityDays: [
          Fx.activityDay('2026-10-12', tasks: 1, stars: 10, xp: 15),
        ],
      ),
    )
    ..reply('GET', '/api/v1/daily-missions/unfinished', [
      _assignment(
        '99999999-9999-4999-8999-0000000000a1',
        _content(
          'Sound Map Mystery',
          'Listen in two places and draw a sound map.',
        ),
        status: 'rejected',
        taskId: _t(2),
        date: '2026-10-10',
      ),
    ])
    ..reply('GET', '/api/v1/daily-missions/today', {
      'local_date': '2026-10-12',
      'timezone': 'Asia/Kolkata',
      'age_band': '7_10',
      'selected_assignment_id': null,
      'choices': [
        _assignment(
          '99999999-9999-4999-8999-0000000000b1',
          _content(
            'Memory Tray: Six Things',
            'Remember six things, then use a trick to improve your own count.',
            minutes: 10,
          ),
        ),
        _assignment(
          '99999999-9999-4999-8999-0000000000b2',
          _content(
            'Paper Airplane Lab',
            'Fold two planes and test which flies farther.',
            minutes: 8,
          ),
          slot: 2,
        ),
        _assignment(
          '99999999-9999-4999-8999-0000000000b3',
          _content(
            'Surprise Mission',
            'A secret mission picked just for you today!',
            minutes: 15,
            surprise: true,
          ),
          slot: 3,
        ),
      ],
    });
  return h;
}

void main() {
  // A tool, not a test: it only runs when asked for (and given a folder).
  if (_dir.isEmpty) {
    test(
      'mission screenshots',
      () {},
      skip: 'Screenshot tool: pass --dart-define=SHOTS_DIR=<folder> to run',
    );
    return;
  }
  setUpAll(_loadFonts);

  Future<void> missions(
    WidgetTester tester,
    String name, {
    required Size size,
    bool withData = true,
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    final h = await _scenario(withData: withData);
    await pumpScreen(
      tester,
      const RepaintBoundary(
        child: ChildShell(location: '/child/missions', child: MissionsScreen()),
      ),
      overrides: h.overrides,
      size: size,
      textScale: textScale,
      locale: locale,
    );
    await _shot(tester, name);
  }

  testWidgets('missions phone', (t) async {
    await missions(t, 'missions_phone', size: const Size(393, 2300));
  });
  testWidgets('missions small phone', (t) async {
    await missions(t, 'missions_small', size: const Size(320, 2600));
  });
  testWidgets('missions tablet', (t) async {
    await missions(t, 'missions_tablet', size: const Size(840, 1700));
  });
  testWidgets('missions empty', (t) async {
    await missions(
      t,
      'missions_empty',
      size: const Size(393, 852),
      withData: false,
    );
  });
  testWidgets('missions gujarati', (t) async {
    await missions(
      t,
      'missions_gu',
      size: const Size(360, 2400),
      locale: const Locale('gu'),
    );
  });
  testWidgets('missions hindi', (t) async {
    await missions(
      t,
      'missions_hi',
      size: const Size(360, 2400),
      locale: const Locale('hi'),
    );
  });

  Future<void> detail(
    WidgetTester tester,
    String name,
    String taskId, {
    Size size = const Size(393, 1500),
  }) async {
    final h = await _scenario(withData: true);
    await pumpScreen(
      tester,
      RepaintBoundary(child: MissionDetailScreen(taskId: taskId)),
      overrides: h.overrides,
      size: size,
    );
    await _shot(tester, name);
  }

  testWidgets('detail new', (t) async => detail(t, 'detail_new', _t(1)));
  testWidgets(
    'detail pending',
    (t) async => detail(t, 'detail_pending', _t(3)),
  );
  testWidgets(
    'detail approved',
    (t) async => detail(t, 'detail_approved', _t(5)),
  );
  testWidgets(
    'detail rejected',
    (t) async => detail(t, 'detail_rejected', _t(2)),
  );
}

/// Tasks as the backend now serves them: every mission pays 10 stars / 15 XP.
List<Map<String, Object?>> _standard(List<Map<String, Object?>> tasks) => [
  for (final t in tasks) {...t, 'star_reward': 10, 'xp_reward': 15},
];
