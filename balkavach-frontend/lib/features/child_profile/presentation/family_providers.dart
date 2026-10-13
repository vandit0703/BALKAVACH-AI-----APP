import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../shared/models/app_assets.dart';
import '../../authentication/presentation/session_controller.dart';
import '../../onboarding/presentation/onboarding_controller.dart';
import '../data/family_repository.dart';
import '../domain/family_models.dart';

/// The signed-in parent's family, or `null` before one is created.
///
/// The backend allows several families per parent; the app uses the most
/// recently created one (the API returns newest first).
class CurrentFamilyController extends AsyncNotifier<Family?> {
  @override
  Future<Family?> build() async {
    final session = await ref.watch(sessionControllerProvider.future);
    if (session == null || !session.isParent) return null;
    final families = await ref.read(familyRepositoryProvider).listFamilies();
    return families.isEmpty ? null : families.first;
  }

  Future<void> create(String familyName) async {
    final family = await ref
        .read(familyRepositoryProvider)
        .createFamily(familyName);
    state = AsyncData(family);
  }
}

final currentFamilyProvider =
    AsyncNotifierProvider<CurrentFamilyController, Family?>(
      CurrentFamilyController.new,
    );

final familyChildrenProvider =
    FutureProvider.family<List<ChildProfile>, String>((ref, familyId) {
      ref.watch(sessionUserIdProvider);
      return ref.watch(familyRepositoryProvider).listChildren(familyId);
    });

/// Records the consent acknowledged during onboarding against the family, once.
///
/// Completes with `true` when the server has a matching active record.
final consentSyncProvider = FutureProvider.family<bool, String>((
  ref,
  familyId,
) async {
  final prefs = ref.watch(appPreferencesProvider);
  final version = ref.watch(consentVersionProvider);
  final acknowledged = ref.watch(
    onboardingControllerProvider.select((s) => s.consentAcknowledged),
  );
  if (!acknowledged) return false;
  if (prefs.isConsentSynced(familyId, version)) return true;

  final repository = ref.read(familyRepositoryProvider);
  final existing = await repository.listConsents(familyId);
  final hasRecord = existing.any(
    (c) =>
        c.consentType == kConsentType &&
        c.documentVersion == version &&
        c.childId == null &&
        c.isActive,
  );
  if (!hasRecord) {
    await repository.recordConsent(
      familyId: familyId,
      consentType: kConsentType,
      documentVersion: version,
    );
  }
  await prefs.markConsentSynced(familyId, version);
  return true;
});

/// Device-local avatar for a child (B7).
final childAvatarProvider = Provider.family<ChildAvatarOption?, String>(
  (ref, childId) => ChildAvatarOption.fromKey(
    ref.watch(appPreferencesProvider).childAvatarKey(childId),
  ),
);
