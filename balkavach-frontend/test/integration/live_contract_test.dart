// Opt-in contract test: runs the app's real repositories against a LIVE server.
//
//   flutter test test/integration/live_contract_test.dart \
//     --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:8765
//
// It creates throw-away accounts, so point it at a disposable local backend
// (never at production). Without LIVE_API_BASE_URL every test here is skipped,
// so a normal `flutter test` stays offline and side-effect free.
import 'dart:typed_data';

import 'package:balkavach_app/core/config/app_config.dart';
import 'package:balkavach_app/core/network/access_token_store.dart';
import 'package:balkavach_app/core/network/api_client.dart';
import 'package:balkavach_app/features/approvals/data/approvals_repository.dart';
import 'package:balkavach_app/features/approvals/domain/review_models.dart';
import 'package:balkavach_app/features/authentication/data/auth_repository.dart';
import 'package:balkavach_app/features/child_profile/data/family_repository.dart';
import 'package:balkavach_app/features/child_profile/domain/family_models.dart';
import 'package:balkavach_app/features/learning/data/learning_repository.dart';
import 'package:balkavach_app/features/missions/data/missions_repository.dart';
import 'package:balkavach_app/features/missions/domain/mission_models.dart';
import 'package:balkavach_app/features/missions/domain/mission_status.dart';
import 'package:balkavach_app/features/notifications/data/device_repository.dart';
import 'package:balkavach_app/features/progress/data/progress_repository.dart';
import 'package:balkavach_app/features/rewards/data/rewards_repository.dart';
import 'package:balkavach_app/features/settings/data/settings_repository.dart';
import 'package:balkavach_app/shared/media/photo_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = String.fromEnvironment('LIVE_API_BASE_URL');

/// A 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x03, 0x00, 0x08, 0xFC, 0x02, 0xFE, 0xA7, 0x9A, 0xA0, 0xA0, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Dio _dio(AccessTokenStore tokens) => createApiDio(
  config: const AppConfig(apiBaseUrl: _base),
  tokens: tokens,
);

void main() {
  final skip = _base.isEmpty ? 'set --dart-define=LIVE_API_BASE_URL' : null;

  test('the app parses a real server end to end', () async {
    final parentTokens = AccessTokenStore();
    final kidTokens = AccessTokenStore();
    final parentDio = _dio(parentTokens);
    final kidDio = _dio(kidTokens);

    // --- parent, family, child -------------------------------------------------
    final email =
        'flutter-live-${DateTime.now().microsecondsSinceEpoch}@example.com';
    final auth = AuthRepository(parentDio);
    final parent = await auth.register(
      fullName: 'Live Parent',
      email: email,
      password: 'live-contract-password-1',
    );
    expect(parent.refreshToken, isNotNull, reason: 'refresh token parsed');
    parentTokens.token = parent.accessToken;

    final families = FamilyRepository(parentDio);
    final family = await families.createFamily('Live Family');
    final child = await families.createChild(
      family.id,
      const NewChildProfile(displayName: 'Live Kid', preferredLanguage: 'en'),
    );
    final kidSession = await auth.startChildSession(child.id);
    expect(kidSession.user.role.name, 'child');
    kidTokens.token = kidSession.accessToken;

    // --- settings, device, config --------------------------------------------------
    final settings = SettingsRepository(parentDio);
    final saved = await settings.saveTimezone(
      family.id,
      await settings.familySettings(family.id),
      'Asia/Kolkata',
    );
    expect(saved.timezone, 'Asia/Kolkata');
    expect((await settings.mySettings()).pushEnabled, isTrue);
    await DeviceRepository(parentDio).register('live-token-${'x' * 30}');
    await DeviceRepository(parentDio).unregister('live-token-${'x' * 30}');

    // --- mission, photo proof, review ----------------------------------------------
    final missions = MissionsRepository(parentDio);
    final categories = await missions.listCategories();
    expect(categories, isNotEmpty);
    final mission = await missions.createMission(
      NewMission(
        familyId: family.id,
        title: 'Live mission',
        assignedChildId: child.id,
        categoryId: categories.first.id,
        starReward: 5,
        xpReward: 150,
      ),
    );
    expect(await missions.listPresets(), isA<List<MissionPreset>>());

    final kidMissions = MissionsRepository(kidDio);
    expect((await kidMissions.listMissions()).map((m) => m.id), [mission.id]);
    final uploadId = await kidMissions.uploadProof(
      PickedPhoto(bytes: _png, fileName: 'proof.png', mimeType: 'image/png'),
    );
    final submission = await kidMissions.submitMission(
      mission.id,
      note: 'done',
      uploadId: uploadId,
    );
    expect(submission.hasPhoto, isTrue);
    final mine = await kidMissions.listMySubmissions();
    expect(
      resolveStatusesFromSubmissions(mine)[mission.id],
      MissionStatus.pending,
    );

    final approvals = ApprovalsRepository(parentDio);
    final queue = await approvals.listFamilySubmissions(
      family.id,
      statuses: ['pending'],
    );
    expect(queue.single.childName, 'Live Kid');
    expect(queue.single.taskTitle, 'Live mission');
    final photo = await missions.downloadProof(queue.single.proofUrl!);
    expect(photo, isNotEmpty);
    await approvals.review(queue.single.id, ReviewDecision.approved);

    // --- progress, report, garden -----------------------------------------------------
    final progress = await ProgressRepository(kidDio).childProgress(child.id);
    expect(progress.starBalance, 5);
    expect(progress.totalXp, 150);
    expect(progress.garden, isNotNull);
    final report = await ProgressRepository(parentDio).weeklyReport(child.id);
    expect(report, isNotNull);
    expect(report!.timezone, 'Asia/Kolkata');
    expect(report.completedTasks, 1);
    expect(report.categories.single.name, categories.first.name);

    // --- rewards -----------------------------------------------------------------------
    final rewards = RewardsRepository(parentDio);
    final reward = await rewards.createReward(
      family.id,
      const RewardInput(name: 'Ice cream', rewardType: 'custom', starCost: 3),
    );
    final kidRewards = RewardsRepository(kidDio);
    expect((await kidRewards.childCatalog()).map((r) => r.id), [reward.id]);
    final key = newIdempotencyKey();
    final request = await kidRewards.requestReward(reward.id, key);
    expect((await kidRewards.requestReward(reward.id, key)).id, request.id);
    final pending = await rewards.familyRedemptions(
      family.id,
      status: 'pending',
    );
    expect(pending.single.rewardName, 'Ice cream');
    expect(pending.single.childName, 'Live Kid');
    await rewards.approve(request.id);
    expect(
      (await ProgressRepository(kidDio).childProgress(child.id)).starBalance,
      2,
    );

    // --- notifications and learning --------------------------------------------------
    final kidNotifications = await kidMissions.listNotifications();
    expect(
      kidNotifications.map((n) => n.type),
      containsAll(['task_assigned', 'task_approved', 'reward_approved']),
    );
    expect(await LearningRepository(kidDio).list(), isA<List<LearningItem>>());
    expect(await LearningRepository(kidDio).categories(), isNotEmpty);

    // --- sessions ------------------------------------------------------------------------
    await auth.endChildSessions(child.id);
    await expectLater(
      kidMissions.listMissions(),
      throwsA(isA<Exception>()),
      reason: 'the child token is revoked server-side',
    );
    await auth.logout(parent.refreshToken!);
  }, skip: skip);
}
