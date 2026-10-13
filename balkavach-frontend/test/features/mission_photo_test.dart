import 'package:balkavach_app/core/errors/api_exception.dart';
import 'package:balkavach_app/core/routing/app_routes.dart';
import 'package:balkavach_app/core/theme/app_theme.dart';
import 'package:balkavach_app/features/authentication/presentation/session_controller.dart';
import 'package:balkavach_app/features/missions/data/missions_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/missions/domain/mission_status.dart';
import 'package:balkavach_app/features/missions/presentation/mission_detail_screen.dart';
import 'package:balkavach_app/features/missions/presentation/mission_providers.dart';
import 'package:balkavach_app/features/missions/presentation/mission_submit_screen.dart';
import 'package:balkavach_app/l10n/app_localizations.dart';
import 'package:balkavach_app/shared/media/photo_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_backend.dart';
import '../helpers/fake_photo_picker.dart';
import '../helpers/fixtures.dart';
import '../helpers/harness.dart';

TaskSubmission _sub(Map<String, Object?> json) => TaskSubmission.fromJson(json);

void main() {
  group('status from the server', () {
    test('the newest attempt of each task decides', () {
      final statuses = resolveStatusesFromSubmissions([
        _sub(Fx.submission(id: 'a', status: 'rejected')),
        _sub(Fx.submission(id: 'b', status: 'pending', number: 2)),
        _sub(Fx.submission(id: 'c', taskId: Fx.task2Id, status: 'approved')),
        _sub(Fx.submission(id: 'd', taskId: 'other', status: 'cancelled')),
      ]);
      expect(statuses[Fx.taskId], MissionStatus.pending);
      expect(statuses[Fx.task2Id], MissionStatus.approved);
      expect(statuses['other'], MissionStatus.notStarted);
    });

    test('resubmission_requested maps to its own status', () {
      expect(
        MissionStatus.fromSubmissionStatus('resubmission_requested'),
        MissionStatus.resubmissionRequested,
      );
    });
  });

  group('repository', () {
    test('uploadProof posts multipart form data and returns the id', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('POST', '/api/v1/uploads/task-proofs', {
        'upload_id': 'up-1',
        'content_type': 'image/png',
        'size_bytes': 70,
        'proof_url': '/api/v1/uploads/task-proofs/up-1',
      }, status: 201);
      final repo = h.container().read(missionsRepositoryProvider);

      expect(await repo.uploadProof(tinyPhoto()), 'up-1');
      final request = h.backend
          .requestsTo('POST', '/api/v1/uploads/task-proofs')
          .single;
      expect(request.data, isA<FormData>());
      final form = request.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'proof.png');
      expect(form.files.single.value.contentType?.mimeType, 'image/png');
    });

    test('submitMission sends the upload id as an image proof', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(proofType: 'image'),
        status: 201,
      );
      await h
          .container()
          .read(missionsRepositoryProvider)
          .submitMission(Fx.taskId, note: ' done ', uploadId: 'up-1');
      expect(
        h.backend
            .requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions')
            .single
            .data,
        {
          'proof_type': 'image',
          'proof_upload_id': 'up-1',
          'proof_note': 'done',
        },
      );
    });

    test('a text note is never sent as an image', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(),
        status: 201,
      );
      await h
          .container()
          .read(missionsRepositoryProvider)
          .submitMission(Fx.taskId, note: 'only words');
      final body =
          h.backend
                  .requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions')
                  .single
                  .data
              as Map;
      expect(body['proof_type'], 'note');
      expect(body.containsKey('proof_upload_id'), isFalse);
    });

    test('listMySubmissions parses titles and parent notes', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply('GET', '/api/v1/tasks/submissions/mine', [
        Fx.submission(
          status: 'rejected',
          taskTitle: 'Read a Storybook',
          reviewNote: 'Please add more detail',
        ),
      ]);
      final list = await h
          .container()
          .read(missionsRepositoryProvider)
          .listMySubmissions();
      expect(list.single.taskTitle, 'Read a Storybook');
      expect(list.single.reviewNote, 'Please add more detail');
    });

    test('downloadProof returns the bytes with the session token', () async {
      final h = await Harness.create(session: Fx.parentSession());
      h.backend.on('GET', '/api/v1/uploads/task-proofs/up-1', (_) {
        return const FakeReply(200, 'raw');
      });
      final container = h.container();
      await container
          .read(missionsRepositoryProvider)
          .downloadProof('/api/v1/uploads/task-proofs/up-1');
      expect(h.backend.requests.last.responseType, ResponseType.bytes);
    });
  });

  group('submit controller', () {
    test(
      'uploads once and re-uses the upload when the submit is retried',
      () async {
        final h = await Harness.create(session: Fx.childSession());
        var submitAttempts = 0;
        h.backend
          ..reply('POST', '/api/v1/uploads/task-proofs', {
            'upload_id': 'up-1',
          }, status: 201)
          ..on('POST', '/api/v1/tasks/${Fx.taskId}/submissions', (_) {
            submitAttempts++;
            return submitAttempts == 1
                ? const FakeReply.fail(DioExceptionType.connectionError)
                : FakeReply(201, Fx.submission(proofType: 'image'));
          });
        final container = h.container();
        await container.read(sessionControllerProvider.future);
        // The controller is auto-dispose; a listener plays the screen's role.
        container.listen(missionSubmitControllerProvider, (_, _) {});
        final controller = container.read(
          missionSubmitControllerProvider.notifier,
        );
        final photo = tinyPhoto();

        expect(await controller.submit(Fx.taskId, photo: photo), isNull);
        expect(
          container.read(missionSubmitControllerProvider).error,
          isA<NetworkException>(),
        );
        expect(await controller.submit(Fx.taskId, photo: photo), isNotNull);
        expect(
          h.backend.requestsTo('POST', '/api/v1/uploads/task-proofs'),
          hasLength(1),
          reason: 'the photo must not be uploaded twice',
        );
      },
    );

    test('without a photo nothing is uploaded', () async {
      final h = await Harness.create(session: Fx.childSession());
      h.backend.reply(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        Fx.submission(),
        status: 201,
      );
      final container = h.container();
      await container.read(sessionControllerProvider.future);
      await container
          .read(missionSubmitControllerProvider.notifier)
          .submit(Fx.taskId, note: 'hi');
      expect(
        h.backend.requestsTo('POST', '/api/v1/uploads/task-proofs'),
        isEmpty,
      );
    });
  });

  group('submit screen', () {
    Future<(Harness, FakePhotoPicker)> pump(
      WidgetTester tester, {
      FakePhotoPicker? picker,
    }) async {
      final fake = picker ?? FakePhotoPicker(result: tinyPhoto());
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..reply('POST', '/api/v1/uploads/task-proofs', {
          'upload_id': 'up-9',
        }, status: 201)
        ..reply(
          'POST',
          '/api/v1/tasks/${Fx.taskId}/submissions',
          Fx.submission(proofType: 'image'),
          status: 201,
        );
      setWindow(tester, const Size(393, 852));
      final router = GoRouter(
        initialLocation: '/submit',
        routes: [
          GoRoute(
            path: '/submit',
            builder: (_, _) => const MissionSubmitScreen(taskId: Fx.taskId),
          ),
          GoRoute(
            path: AppRoutes.childMissionWaiting(Fx.taskId),
            builder: (_, _) => const Scaffold(body: Text('waiting-screen')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...h.overrides,
            photoPickerProvider.overrideWithValue(fake),
          ],
          retry: (_, _) => null,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (h, fake);
    }

    testWidgets('choosing a photo shows a preview that can be removed', (
      tester,
    ) async {
      final (_, fake) = await pump(tester);
      expect(find.byKey(const Key('submit.photo.preview')), findsNothing);

      await tester.tap(find.byKey(const Key('submit.photo.camera')));
      await tester.pumpAndSettle();
      expect(fake.sources, [PhotoSource.camera]);
      expect(find.byKey(const Key('submit.photo.preview')), findsOneWidget);
      expect(find.text('Photo ready to send'), findsOneWidget);

      await tester.tap(find.byKey(const Key('submit.photo.remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit.photo.preview')), findsNothing);
    });

    testWidgets('gallery source is used by its own button', (tester) async {
      final (_, fake) = await pump(tester);
      await tester.tap(find.byKey(const Key('submit.photo.gallery')));
      await tester.pumpAndSettle();
      expect(fake.sources, [PhotoSource.gallery]);
    });

    testWidgets('cancelling the picker keeps the form unchanged', (
      tester,
    ) async {
      final (_, _) = await pump(tester, picker: FakePhotoPicker());
      await tester.tap(find.byKey(const Key('submit.photo.camera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit.photo.preview')), findsNothing);
      expect(find.byKey(const Key('submit.photo.error')), findsNothing);
    });

    testWidgets('a denied permission explains what to do', (tester) async {
      await pump(tester, picker: FakePhotoPicker(fails: true));
      await tester.tap(find.byKey(const Key('submit.photo.camera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('submit.photo.error')), findsOneWidget);
      expect(
        find.textContaining('Check the app\'s permission in Settings'),
        findsOneWidget,
      );
    });

    testWidgets(
      'submitting uploads the photo first, then sends it as an image',
      (tester) async {
        final (h, _) = await pump(tester);
        await tester.tap(find.byKey(const Key('submit.photo.gallery')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('submit.note')), 'look!');
        await tester.ensureVisible(find.byKey(const Key('submit.button')));
        await tester.tap(find.byKey(const Key('submit.button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final order = h.backend.requests
            .map((r) => '${r.method} ${r.uri.path}')
            .toList();
        expect(
          order.indexOf('POST /api/v1/uploads/task-proofs'),
          lessThan(
            order.indexOf('POST /api/v1/tasks/${Fx.taskId}/submissions'),
          ),
        );
        expect(
          h.backend
              .requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions')
              .single
              .data,
          {
            'proof_type': 'image',
            'proof_upload_id': 'up-9',
            'proof_note': 'look!',
          },
        );
      },
    );

    testWidgets('server codes are explained in plain language', (tester) async {
      final (h, _) = await pump(tester);
      h.backend.on(
        'POST',
        '/api/v1/tasks/${Fx.taskId}/submissions',
        (_) => FakeReply.error(409, 'submission_pending', 'pending'),
      );
      await tester.ensureVisible(find.byKey(const Key('submit.button')));
      await tester.tap(find.byKey(const Key('submit.button')));
      await tester.pumpAndSettle();
      expect(
        find.text('This mission is already waiting for your parent to check.'),
        findsOneWidget,
      );
    });

    testWidgets('an oversized photo is explained', (tester) async {
      final (h, _) = await pump(tester);
      h.backend.on(
        'POST',
        '/api/v1/uploads/task-proofs',
        (_) => FakeReply.error(413, 'upload_too_large', 'too big'),
      );
      await tester.tap(find.byKey(const Key('submit.photo.gallery')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('submit.button')));
      await tester.tap(find.byKey(const Key('submit.button')));
      await tester.pumpAndSettle();
      expect(
        find.text('That photo is too large. Try a smaller one.'),
        findsOneWidget,
      );
      expect(
        h.backend.requestsTo('POST', '/api/v1/tasks/${Fx.taskId}/submissions'),
        isEmpty,
      );
    });
  });

  group('mission details', () {
    testWidgets('lists earlier tries with the parent\'s note', (tester) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..reply('GET', '/api/v1/tasks/submissions/mine', [
          Fx.submission(
            id: 's2',
            number: 2,
            status: 'pending',
            taskTitle: 'Read a Storybook',
          ),
          Fx.submission(
            id: 's1',
            status: 'rejected',
            taskTitle: 'Read a Storybook',
            reviewNote: 'Please add more detail',
          ),
        ]);
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: h.overrides,
      );
      expect(find.byKey(const Key('mission.history')), findsOneWidget);
      expect(find.text('Try 2'), findsOneWidget);
      expect(find.text('Try 1'), findsOneWidget);
      expect(
        find.text('Note from your parent: Please add more detail'),
        findsOneWidget,
      );
    });

    testWidgets('shows no history section before the first try', (
      tester,
    ) async {
      final h = await Harness.create(
        session: Fx.childSession(),
        prefs: onboardedPrefs,
      );
      h.backend
        ..reply('GET', '/api/v1/auth/me', Fx.childSession().user.toJson())
        ..reply('GET', '/api/v1/tasks/submissions/mine', <Object?>[]);
      await pumpScreen(
        tester,
        const MissionDetailScreen(taskId: Fx.taskId),
        overrides: h.overrides,
      );
      expect(find.byKey(const Key('mission.history')), findsNothing);
    });
  });
}
