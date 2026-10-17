// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Bal Kavach Admin';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navUsers => 'Users';

  @override
  String get navFamilies => 'Families';

  @override
  String get navMissions => 'Missions';

  @override
  String get navCategories => 'Categories';

  @override
  String get navPresets => 'Preset missions';

  @override
  String get navRewards => 'Rewards';

  @override
  String get navRedemptions => 'Reward requests';

  @override
  String get navContent => 'Learning content';

  @override
  String get navBadges => 'Badges';

  @override
  String get navSettings => 'Settings';

  @override
  String get navAudit => 'Audit log';

  @override
  String get navGroupOverview => 'Overview';

  @override
  String get navGroupPeople => 'People';

  @override
  String get navGroupMissions => 'Missions & rewards';

  @override
  String get navGroupLearning => 'Learning';

  @override
  String get navGroupSystem => 'System';

  @override
  String get breadcrumbLabel => 'You are here';

  @override
  String get noAccess => 'Your role does not include access to this section.';

  @override
  String get accountTooltip => 'Account';

  @override
  String accountRoles(String roles) {
    return 'Roles: $roles';
  }

  @override
  String get languageTooltip => 'Language';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionSave => 'Save';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDeactivate => 'Deactivate';

  @override
  String get actionReactivate => 'Reactivate';

  @override
  String get actionSignIn => 'Sign in';

  @override
  String get actionSignOut => 'Sign out';

  @override
  String get actionApply => 'Apply';

  @override
  String get actionChange => 'Change';

  @override
  String get actionDetails => 'Details';

  @override
  String get actionHide => 'Hide';

  @override
  String get actionShow => 'Show';

  @override
  String get actionRoles => 'Roles';

  @override
  String get validationRequired => 'Required';

  @override
  String validationMaxLength(String max) {
    return 'At most $max characters';
  }

  @override
  String get validationWholeNumber => 'Enter a whole number';

  @override
  String validationAtLeast(String min) {
    return 'At least $min';
  }

  @override
  String validationAtMost(String max) {
    return 'At most $max';
  }

  @override
  String get validationHttps => 'Enter a full https:// link';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork => 'Cannot reach the server. Check the connection.';

  @override
  String get errorForbidden => 'You do not have permission to do this.';

  @override
  String get errorSessionExpired =>
      'Your session has ended. Please sign in again.';

  @override
  String get errorNotFound => 'That item no longer exists.';

  @override
  String get errorConflict =>
      'That conflicts with something that already exists.';

  @override
  String get errorValidation =>
      'Some of the values are not valid. Check them and try again.';

  @override
  String get errorServer =>
      'The server had a problem. Please try again in a moment.';

  @override
  String get errorLastSuperAdmin =>
      'The last super administrator cannot be removed or deactivated.';

  @override
  String get errorEmailInUse => 'That email address is already in use.';

  @override
  String get errorUsernameInUse => 'That username is already taken.';

  @override
  String get errorCategoryConflict =>
      'A category with that name already exists.';

  @override
  String get errorInvalidSetting => 'That setting value is not valid.';

  @override
  String get errorInvalidAgeRange =>
      'The youngest age cannot be above the oldest age.';

  @override
  String get errorTooManyRequests =>
      'Too many requests. Please wait a moment and try again.';

  @override
  String get loading => 'Loading';

  @override
  String get loginSubtitle => 'Administrators only';

  @override
  String get loginEmail => 'Email';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginEmailRequired => 'Enter your email';

  @override
  String get loginPasswordRequired => 'Enter your password';

  @override
  String get loginWrongCredentials => 'Email or password is incorrect.';

  @override
  String get loginNotAdmin => 'This account is not an administrator.';

  @override
  String get tableEmpty => 'Nothing to show.';

  @override
  String get tablePrevious => 'Previous page';

  @override
  String get tableNext => 'Next page';

  @override
  String tablePage(String page) {
    return 'Page $page';
  }

  @override
  String get filterAll => 'All';

  @override
  String get statusActive => 'Active';

  @override
  String get statusDeactivated => 'Deactivated';

  @override
  String get statusHidden => 'Hidden';

  @override
  String get statusVisible => 'Visible';

  @override
  String get statusShown => 'Shown';

  @override
  String get statusOffered => 'Offered';

  @override
  String get statusOff => 'Off';

  @override
  String get colName => 'Name';

  @override
  String get colEmail => 'Email';

  @override
  String get colRole => 'Role';

  @override
  String get colStatus => 'Status';

  @override
  String get colLastSignIn => 'Last sign-in';

  @override
  String get colFamily => 'Family';

  @override
  String get colParents => 'Parents';

  @override
  String get colChildren => 'Children';

  @override
  String get colActiveMissions => 'Active missions';

  @override
  String get colCreated => 'Created';

  @override
  String get colMission => 'Mission';

  @override
  String get colCategory => 'Category';

  @override
  String get colChild => 'Child';

  @override
  String get colStarsXp => 'Stars / XP';

  @override
  String get colDescription => 'Description';

  @override
  String get colIcon => 'Icon';

  @override
  String get colReward => 'Reward';

  @override
  String get colType => 'Type';

  @override
  String get colStarCost => 'Star cost';

  @override
  String get colStars => 'Stars';

  @override
  String get colRequested => 'Requested';

  @override
  String get colAges => 'Ages';

  @override
  String get colLink => 'Link';

  @override
  String get colAmount => 'Amount';

  @override
  String get colWhen => 'When';

  @override
  String get colAction => 'Action';

  @override
  String get colItem => 'Item';

  @override
  String get colAdmin => 'Admin';

  @override
  String get fieldName => 'Name';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldDescription => 'Description';

  @override
  String get fieldCategory => 'Category';

  @override
  String get fieldLanguage => 'Language';

  @override
  String get fieldType => 'Type';

  @override
  String get fieldRole => 'Role';

  @override
  String get fieldIconName => 'Icon name';

  @override
  String get fieldIconNameHelp => 'For example book-open or palette';

  @override
  String get dashboardTitle => 'Dashboard';

  @override
  String get dashboardSubtitle => 'A snapshot of how Bal Kavach is being used';

  @override
  String get range7 => '7 days';

  @override
  String get range30 => '30 days';

  @override
  String get range90 => '90 days';

  @override
  String get tileUsers => 'Users';

  @override
  String get tileFamilies => 'Families';

  @override
  String get tileChildren => 'Active children';

  @override
  String get tileMissions => 'Active missions';

  @override
  String get tileVideos => 'Published videos';

  @override
  String get tileRedemptions => 'Pending reward requests';

  @override
  String get systemTitle => 'System status';

  @override
  String get systemRefresh => 'Check again';

  @override
  String get systemChecking => 'Checking…';

  @override
  String get systemApi => 'Server';

  @override
  String get systemDatabase => 'Database';

  @override
  String get systemUp => 'Available';

  @override
  String get systemDown => 'Unavailable';

  @override
  String activityTitle(String days) {
    return 'Last $days days';
  }

  @override
  String activityNewUsers(String n) {
    return 'New users: $n';
  }

  @override
  String activitySubmissions(String n) {
    return 'Submissions: $n';
  }

  @override
  String activityApprovals(String n) {
    return 'Approvals: $n';
  }

  @override
  String activityRejections(String n) {
    return 'Rejections: $n';
  }

  @override
  String activityRedemptions(String n) {
    return 'Reward requests: $n';
  }

  @override
  String get activityChartTitle => 'Daily submissions';

  @override
  String activityDayTooltip(String date, String submitted, String approved) {
    return '$date: $submitted submitted, $approved approved';
  }

  @override
  String activityPeak(String n) {
    return 'Peak: $n';
  }

  @override
  String get activityByStatus => 'Reward requests by status';

  @override
  String get activityTopCategories => 'Top categories (approved missions)';

  @override
  String get activityNoApproved => 'No approved missions yet.';

  @override
  String get usersTitle => 'Users';

  @override
  String get usersSubtitle => 'Parents, children and administrators';

  @override
  String get usersSearch => 'Search name or email';

  @override
  String get usersAllRoles => 'All roles';

  @override
  String get usersEmpty => 'No users match.';

  @override
  String get rolesParents => 'Parents';

  @override
  String get rolesChildren => 'Children';

  @override
  String get rolesAdmins => 'Admins';

  @override
  String get rolesStaff => 'Staff';

  @override
  String get userDeactivateTitle => 'Deactivate account?';

  @override
  String get userReactivateTitle => 'Reactivate account?';

  @override
  String userDeactivateBody(String name) {
    return '$name will be signed out and unable to sign in until reactivated.';
  }

  @override
  String userReactivateBody(String name) {
    return '$name will be able to sign in again.';
  }

  @override
  String get userDeactivated => 'Account deactivated';

  @override
  String get userReactivated => 'Account reactivated';

  @override
  String userRolesTitle(String name) {
    return 'Roles for $name';
  }

  @override
  String get userRolesRemove => 'Remove this role instead of assigning it';

  @override
  String get userRoleAssigned => 'Role assigned';

  @override
  String get userRoleRemoved => 'Role removed';

  @override
  String get familiesTitle => 'Families';

  @override
  String get familiesSubtitle => 'Households, their parents and children';

  @override
  String get familiesSearch => 'Search family name';

  @override
  String get familiesEmpty => 'No families match.';

  @override
  String familyTimeZone(String zone) {
    return 'Time zone: $zone';
  }

  @override
  String get familyParents => 'Parents';

  @override
  String get familyChildren => 'Children';

  @override
  String get familyNoChildren => 'No children yet.';

  @override
  String familyChildAdded(String date) {
    return 'Added $date';
  }

  @override
  String childDeactivateTitle(String name) {
    return 'Deactivate $name?';
  }

  @override
  String childReactivateTitle(String name) {
    return 'Reactivate $name?';
  }

  @override
  String get childDeactivateBody =>
      'The child is signed out everywhere and cannot sign in until reactivated. Their history is kept.';

  @override
  String get childReactivateBody =>
      'The child can be started in child mode again.';

  @override
  String get childDeactivated => 'Child deactivated';

  @override
  String get childReactivated => 'Child reactivated';

  @override
  String get missionsTitle => 'Missions';

  @override
  String get missionsSubtitle =>
      'Every family mission. Deactivating hides it from the child.';

  @override
  String get missionsSearch => 'Search title';

  @override
  String get missionsEmpty => 'No missions match.';

  @override
  String get missionAnyChild => 'Any child';

  @override
  String get missionDeactivateTitle => 'Deactivate mission?';

  @override
  String get missionReactivateTitle => 'Reactivate mission?';

  @override
  String missionConfirmBody(String title, String family) {
    return '\"$title\" in $family.';
  }

  @override
  String get missionDeactivated => 'Mission deactivated';

  @override
  String get missionReactivated => 'Mission reactivated';

  @override
  String get categoriesTitle => 'Mission categories';

  @override
  String get categoriesSubtitle =>
      'The groups parents pick from when creating a mission';

  @override
  String get categoryNewTitle => 'New category';

  @override
  String get categoryEditTitle => 'Edit category';

  @override
  String get categoryCreated => 'Category created';

  @override
  String get categorySaved => 'Category saved';

  @override
  String get categoryVisibleToParents => 'Visible to parents';

  @override
  String get presetsTitle => 'Preset missions';

  @override
  String get presetsSubtitle =>
      'Ready-made ideas parents can start a mission from. The reward values are only suggestions.';

  @override
  String get presetNewButton => 'New preset';

  @override
  String get presetNewTitle => 'New preset mission';

  @override
  String get presetEditTitle => 'Edit preset mission';

  @override
  String get presetCreated => 'Preset created';

  @override
  String get presetSaved => 'Preset saved';

  @override
  String get presetNoCategory => 'No category';

  @override
  String get presetSuggestedStars => 'Suggested stars';

  @override
  String get presetSuggestedXp => 'Suggested XP';

  @override
  String get presetYoungestAge => 'Youngest age';

  @override
  String get presetOldestAge => 'Oldest age';

  @override
  String get presetOffered => 'Offered to parents';

  @override
  String get rewardsTitle => 'Rewards';

  @override
  String get rewardsSubtitle =>
      'Rewards created by families. Parents manage their own; hide one here if needed.';

  @override
  String get rewardsEmpty => 'No rewards yet.';

  @override
  String get rewardHideTitle => 'Hide reward?';

  @override
  String get rewardShowTitle => 'Show reward?';

  @override
  String rewardConfirmBody(String name, String family) {
    return '\"$name\" from $family.';
  }

  @override
  String get rewardHidden => 'Reward hidden';

  @override
  String get rewardShown => 'Reward shown';

  @override
  String get redemptionsTitle => 'Reward requests';

  @override
  String get redemptionsSubtitle =>
      'Read-only. Parents approve or decline their own children\'s requests.';

  @override
  String get redemptionsEmpty => 'No reward requests.';

  @override
  String get redemptionAllStatuses => 'All statuses';

  @override
  String get redemptionPending => 'Pending';

  @override
  String get redemptionApproved => 'Approved';

  @override
  String get redemptionDeclined => 'Declined';

  @override
  String get redemptionGiven => 'Given';

  @override
  String get redemptionCancelled => 'Cancelled';

  @override
  String get contentTitle => 'Learning content';

  @override
  String get contentSubtitle =>
      'What children see under Learn & Watch, in their language';

  @override
  String get contentAddButton => 'Add content';

  @override
  String get contentNewTitle => 'New content';

  @override
  String get contentEditTitle => 'Edit content';

  @override
  String get contentAdded => 'Content added';

  @override
  String get contentSaved => 'Content saved';

  @override
  String get contentEmpty => 'No content yet.';

  @override
  String get contentLink => 'Link (https)';

  @override
  String get contentLinkHelp => 'Opens in the child\'s browser or video app';

  @override
  String get contentThumbnail => 'Thumbnail link (https)';

  @override
  String get contentShownToChildren => 'Shown to children';

  @override
  String get contentTypeLink => 'Link';

  @override
  String get contentTypeVideo => 'Video link';

  @override
  String get contentTypeArticle => 'Article';

  @override
  String get contentTypeDocument => 'Document';

  @override
  String get contentTypeActivity => 'Activity';

  @override
  String get badgesTitle => 'Badges';

  @override
  String get badgesSubtitle =>
      'Awarded automatically when a child reaches the amount. Garden decorations unlock with the default badges.';

  @override
  String get badgeNewTitle => 'New badge';

  @override
  String get badgeEditTitle => 'Edit badge';

  @override
  String get badgeCreated => 'Badge created';

  @override
  String get badgeSaved => 'Badge saved';

  @override
  String get badgeEarnedBy => 'Earned by';

  @override
  String get badgeAmountNeeded => 'Amount needed';

  @override
  String get badgeCanBeEarned => 'Can be earned';

  @override
  String get badgeCriteriaApprovedTasks => 'Approved missions';

  @override
  String get badgeCriteriaTotalStars => 'Total stars';

  @override
  String get badgeCriteriaTotalXp => 'Total XP';

  @override
  String get badgeCriteriaStreak => 'Day streak';

  @override
  String get auditTitle => 'Audit log';

  @override
  String get auditSubtitle => 'Who changed what, and when';

  @override
  String get auditEmpty => 'No administrative changes recorded yet.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSubtitle => 'Read by the mobile app every time it starts';

  @override
  String get settingsLanguageTitle => 'Panel language';

  @override
  String get settingsLanguageHelp =>
      'Changes this admin panel only. Content written by families or the server is not translated.';

  @override
  String get settingsConsentTitle => 'Consent document version';

  @override
  String get settingsConsentField => 'Parent / guardian terms version';

  @override
  String get settingsConsentHelp =>
      'Changing this asks every parent to accept again on their next launch.';

  @override
  String get settingsConsentConfirmTitle => 'Ask all parents to accept again?';

  @override
  String settingsConsentConfirmBody(String version) {
    return 'The new version \"$version\" will be shown to every parent. Confirm that legal has approved the text.';
  }

  @override
  String get settingsConsentPublish => 'Publish version';

  @override
  String get settingsConsentPublished => 'Consent version published';

  @override
  String settingsConsentSummary(String version) {
    return 'Parent / guardian terms: $version';
  }

  @override
  String get settingsConsentDraft => '(built-in draft: legal must confirm)';

  @override
  String get settingsMaintenanceTitle => 'Maintenance notice';

  @override
  String get settingsMaintenanceShow => 'Show a banner in the app';

  @override
  String get settingsMaintenanceMessage => 'Message';

  @override
  String get settingsMaintenanceHelp => 'Leave empty for the default sentence';

  @override
  String get settingsMaintenanceSaved => 'Maintenance notice saved';

  @override
  String settingsMaintenanceShowing(String message) {
    return 'Showing: $message';
  }

  @override
  String get settingsMaintenanceDefault => 'default message';
}
