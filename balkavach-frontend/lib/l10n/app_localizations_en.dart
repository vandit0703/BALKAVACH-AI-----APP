// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Bal Kavach AI';

  @override
  String get brandEyebrow => 'KIDS DIGITAL GUARDIAN';

  @override
  String get brandName => 'Bal Kavach';

  @override
  String get brandSuffix => 'AI';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get optional => 'Optional';

  @override
  String get loading => 'Loading…';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork =>
      'Can\'t reach Bal Kavach. Check your internet connection.';

  @override
  String get errorTimeout =>
      'The server is taking a while. It may be waking up, so please try again.';

  @override
  String get errorSessionExpired =>
      'Your session has ended. Please sign in again.';

  @override
  String get errorForbidden => 'You don\'t have access to this.';

  @override
  String get errorNotFound => 'We couldn\'t find that.';

  @override
  String get errorServer => 'The server had a problem. Please try again soon.';

  @override
  String get welcomeTagline =>
      'Safe Childhood, Smart Future • Play • Learn • Grow Together';

  @override
  String get welcomeMascotLabel => 'Kavach Panda';

  @override
  String get welcomeBuddyLabel => 'AI Buddy';

  @override
  String get welcomeBubble => 'Namaste! Choose your language';

  @override
  String get welcomeSelectLanguage => 'Select App Language';

  @override
  String get welcomeChangeAnytime => 'You can change anytime';

  @override
  String get welcomeGetStarted => 'Get Started';

  @override
  String get welcomeFooter => 'Private • Ad-Free • 100% Parent Controlled';

  @override
  String get consentEyebrow => 'BAL KAVACH ECOSYSTEM';

  @override
  String get consentTitle => 'Parent Safety First';

  @override
  String get consentSubtitle =>
      'Your child\'s digital wellbeing and safety are our highest priorities.';

  @override
  String get consentApprovalTitle => 'Parent Approval Required';

  @override
  String get consentApprovalBody =>
      'All child mission submissions and star reward redemptions require your explicit tap.';

  @override
  String get consentAdsTitle => 'Zero Advertisements';

  @override
  String get consentAdsBody =>
      '100% ad-free environment. No commercial trackers, marketing profiling, or third-party retargeting.';

  @override
  String get consentPrivateTitle => 'Private Family Sanctuary';

  @override
  String get consentPrivateBody =>
      'No public child directories and zero stranger communication.';

  @override
  String get consentGoalsTitle => 'Parent-Controlled Goals';

  @override
  String get consentGoalsBody =>
      'You set everyday missions and review every submission before stars are awarded.';

  @override
  String get consentCheckbox =>
      'I confirm I am the parent or legal guardian and agree to the Terms of Service & Child Data Protection Policy.';

  @override
  String get consentCheckboxRequired =>
      'Please confirm you are the parent or legal guardian to continue.';

  @override
  String get consentContinue => 'I Agree & Continue';

  @override
  String get roleTitle => 'Who is using Bal Kavach?';

  @override
  String get roleSubtitle =>
      'Parents set up the family first. Children join through a parent.';

  @override
  String get roleParent => 'I\'m a Parent';

  @override
  String get roleParentBody =>
      'Sign in, add your children, create missions and approve progress.';

  @override
  String get roleChild => 'I\'m a Child';

  @override
  String get roleChildBody =>
      'Play missions after a parent starts child mode for you.';

  @override
  String get childStartTitle => 'Ask a parent to help';

  @override
  String get childStartBody =>
      'Child mode is started from a parent account. Ask your parent to sign in, choose your profile and tap “Start child mode”.';

  @override
  String get childStartParentSignIn => 'Parent sign in';

  @override
  String get authHeroEyebrow => 'PARENTAL SAFESPHERE GATE';

  @override
  String get authHeroCaption =>
      'Dual-perspective guardianship & child well-being';

  @override
  String get authTitle => 'Parent Login / Register';

  @override
  String get authSubtitle => 'Secure access to your family\'s safety hub';

  @override
  String get authTabSignIn => 'Sign in';

  @override
  String get authTabRegister => 'Create account';

  @override
  String get authFullName => 'Full name';

  @override
  String get authEmail => 'Email';

  @override
  String get authPassword => 'Password';

  @override
  String get authPasswordHint => 'At least 12 characters';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authSignInButton => 'Sign in';

  @override
  String get authRegisterButton => 'Create account';

  @override
  String get authUnavailableMethods =>
      'Phone OTP and Google sign-in are not available yet. Please use email and password.';

  @override
  String get authInvalidCredentials => 'Email or password is incorrect.';

  @override
  String get authEmailInUse =>
      'An account with this email already exists. Try signing in.';

  @override
  String get validationNameRequired => 'Please enter a name.';

  @override
  String get validationNameTooShort => 'Use at least 2 characters.';

  @override
  String get validationEmailInvalid => 'Enter a valid email address.';

  @override
  String get validationPasswordRequired => 'Please enter your password.';

  @override
  String get validationPasswordTooShort => 'Use at least 12 characters.';

  @override
  String validationTooLong(int max) {
    return 'Use at most $max characters.';
  }

  @override
  String validationNumberRange(int min, int max) {
    return 'Enter a number from $min to $max.';
  }

  @override
  String get parentHubTitle => 'Parent Hub';

  @override
  String parentGreeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get parentSignOut => 'Sign out';

  @override
  String get familyCreateTitle => 'Create your family';

  @override
  String get familyCreateBody => 'Name your family to start adding children.';

  @override
  String get familyNameLabel => 'Family name';

  @override
  String get familyCreateButton => 'Create family';

  @override
  String get consentSyncFailed =>
      'We couldn\'t save your consent record yet. We\'ll retry next time.';

  @override
  String get childrenTitle => 'Your children';

  @override
  String get childrenEmpty =>
      'No child profiles yet. Add your first child to get started.';

  @override
  String get childrenAdd => 'Add child';

  @override
  String get childStartMode => 'Start child mode';

  @override
  String childModeConfirmTitle(String name) {
    return 'Start child mode for $name?';
  }

  @override
  String childModeConfirmBody(String name) {
    return 'This device will switch to $name\'s missions. To come back, a parent must sign in again.';
  }

  @override
  String get childModeConfirm => 'Start';

  @override
  String get parentMissionsTitle => 'Missions';

  @override
  String get parentMissionsEmpty =>
      'No missions yet. Create the first one for your family.';

  @override
  String get parentMissionsNew => 'New mission';

  @override
  String get missionForEveryone => 'Everyone';

  @override
  String missionAssignedTo(String name) {
    return 'For $name';
  }

  @override
  String get createChildEyebrow => 'PLAYFUL SAFETY';

  @override
  String get createChildTitle => 'Add Your Child\'s Profile';

  @override
  String get createChildSubtitle =>
      'Personalize daily habits, missions, and fun learning.';

  @override
  String get createChildName => 'Child\'s name';

  @override
  String get createChildNameHint => 'Preferred nickname';

  @override
  String get createChildDob => 'Date of birth';

  @override
  String get createChildDobPick => 'Select date';

  @override
  String get createChildDobClear => 'Clear date';

  @override
  String get createChildAvatar => 'Choose Avatar';

  @override
  String get createChildAvatarLocal =>
      'The avatar is saved on this device only.';

  @override
  String get createChildLanguage => 'Child\'s language';

  @override
  String createChildSubmit(String name) {
    return 'Create $name\'s Profile';
  }

  @override
  String get createChildSubmitGeneric => 'Create Profile';

  @override
  String get createChildSuccess => 'Profile created';

  @override
  String get createMissionTitle => 'New mission';

  @override
  String get createMissionName => 'Mission title';

  @override
  String get createMissionDescription => 'What should your child do?';

  @override
  String get createMissionCategory => 'Category';

  @override
  String get createMissionNoCategory => 'No category';

  @override
  String get createMissionAssign => 'Who is it for?';

  @override
  String get createMissionStars => 'Stars';

  @override
  String get createMissionXp => 'XP';

  @override
  String get createMissionSubmit => 'Create mission';

  @override
  String get createMissionSuccess => 'Mission created';

  @override
  String get childHomeTitle => 'Child Home';

  @override
  String get parentGate => 'Parent Gate';

  @override
  String get parentGateTitle => 'Leave child mode?';

  @override
  String get parentGateBody =>
      'A parent will need to sign in again to continue.';

  @override
  String get parentGateLeave => 'Leave';

  @override
  String get parentGateStay => 'Stay';

  @override
  String childHello(String name) {
    return 'Hello $name!';
  }

  @override
  String childLevel(int level) {
    return 'Lv $level';
  }

  @override
  String childLevelName(String name) {
    return '$name • Quest Ready';
  }

  @override
  String get childQuestReady => 'Quest Ready';

  @override
  String get statStars => 'Stars';

  @override
  String get statStreak => 'Streak';

  @override
  String statStreakValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Day',
      one: '1 Day',
    );
    return '$_temp0';
  }

  @override
  String get statXp => 'XP';

  @override
  String get mascotReady => 'Ready for today\'s adventures? 🚀';

  @override
  String mascotMissionsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Complete $count more missions to keep growing!',
      one: 'Complete 1 more mission to keep growing!',
      zero: 'All missions done. Amazing work!',
    );
    return '$_temp0';
  }

  @override
  String get todaysMissions => 'Today\'s Missions';

  @override
  String missionsDone(int done, int total) {
    return '$done of $total Done';
  }

  @override
  String get missionStart => 'Start';

  @override
  String get missionsSeeAll => 'See all missions';

  @override
  String get navHome => 'Home';

  @override
  String get navMissions => 'Missions';

  @override
  String get reviewsUnavailable =>
      'Couldn\'t check for parent reviews right now.';

  @override
  String get missionsTitle => 'Child Missions';

  @override
  String missionsFilterAll(int count) {
    return 'All ($count)';
  }

  @override
  String get missionsEmpty => 'No missions yet. Ask your parent to add one!';

  @override
  String get missionsFilterEmpty => 'No missions in this category.';

  @override
  String get pandaSays => 'Panda Kavach says:';

  @override
  String get pandaEncourage =>
      '\"Every mission you finish makes you stronger. Keep soaring!\"';

  @override
  String get statusPending => 'Pending Approval';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusRejected => 'Not approved';

  @override
  String get statusResubmit => 'Try again';

  @override
  String get missionStartMission => 'Start Mission';

  @override
  String get missionDoAgain => 'Do it again';

  @override
  String missionStarsCount(int count) {
    return '$count Stars';
  }

  @override
  String missionXpCount(int count) {
    return '$count XP';
  }

  @override
  String missionDue(String date) {
    return 'Due $date';
  }

  @override
  String get missionDetailTitle => 'Mission details';

  @override
  String get missionWhatToDo => 'What to do';

  @override
  String get missionNoDescription =>
      'Your parent didn\'t add extra steps. Do your best and tell them about it!';

  @override
  String missionEarn(int stars) {
    return 'Earn $stars stars by finishing this mission.';
  }

  @override
  String get missionWaitingButton => 'Waiting for approval';

  @override
  String get missionNotFound => 'This mission is no longer available.';

  @override
  String get submitTitle => 'Complete Your Mission';

  @override
  String get submitEvidenceTitle => 'Your Mission Evidence';

  @override
  String get submitPhotoUnavailable =>
      'Photo proof isn\'t available yet. Tell your parent what you did instead.';

  @override
  String get submitNoteLabel => 'Tell Mummy & Papa about it';

  @override
  String get submitNoteHint => 'I drew a lion in the jungle!';

  @override
  String get submitPrivacy =>
      'Only visible to your parents in their approval inbox.';

  @override
  String get submitPandaName => 'Kavach Panda';

  @override
  String get submitPandaMessage =>
      'Woohoo! Tap below to send this to Mummy & Papa!';

  @override
  String get submitButton => 'Submit for Parent Approval';

  @override
  String submitFooter(int stars) {
    return 'Once approved, $stars stars will be added to your treasure chest!';
  }

  @override
  String get submitNotAssigned => 'This mission belongs to another child.';

  @override
  String get waitingTitle => 'Sent to your parent!';

  @override
  String get waitingBody =>
      'Waiting for parent approval. You\'ll see the result here when your parent reviews it.';

  @override
  String get waitingApprovedTitle => 'Approved! 🎉';

  @override
  String waitingApprovedBody(int stars) {
    return '+$stars stars added to your treasure chest.';
  }

  @override
  String get waitingRejectedTitle => 'Not approved this time';

  @override
  String get waitingRejectedBody => 'Talk to your parent and try again later.';

  @override
  String get waitingResubmitTitle => 'Let\'s try again';

  @override
  String get waitingResubmitBody =>
      'Your parent asked you to redo this mission.';

  @override
  String get waitingCheckAgain => 'Check again';

  @override
  String get waitingBackToMissions => 'Back to missions';

  @override
  String get serverChecking => 'Checking the Bal Kavach server…';

  @override
  String get serverOnline => 'Server online';

  @override
  String get serverDbDown =>
      'Server is up, but its database is unavailable. Sign-in may fail.';

  @override
  String get serverUnreachable =>
      'Can\'t reach the server. It may be starting up.';

  @override
  String get serverStatusNote =>
      'This only checks the connection, not every feature.';

  @override
  String get familyMissing => 'Create your family first on the Parent Hub.';

  @override
  String get filterAllChildren => 'All children';

  @override
  String get someChild => 'Your child';

  @override
  String get navRewards => 'Rewards';

  @override
  String get navGarden => 'Garden';

  @override
  String get edit => 'Edit';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get approvalsAppBar => 'Parent Missions';

  @override
  String get approvalsTitle => 'Mission Approvals';

  @override
  String get approvalsSubtitle =>
      'Review your child\'s offline triumphs and release star rewards.';

  @override
  String approvalsActions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Actions',
      one: '1 Action',
    );
    return '$_temp0';
  }

  @override
  String get approvalsOpen => 'Review submitted missions';

  @override
  String approvalsPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count waiting for review',
      one: '1 waiting for review',
      zero: 'Nothing waiting for review',
    );
    return '$_temp0';
  }

  @override
  String get approvalsTabPending => 'Pending';

  @override
  String get approvalsTabApproved => 'Approved';

  @override
  String get approvalsTabRetry => 'Retry';

  @override
  String get approvalsTruncated =>
      'Showing the most recently submitted missions only. Older submissions may not appear.';

  @override
  String get approvalsPendingEmpty =>
      'Nothing to review right now. New submissions will appear here.';

  @override
  String get approvalsApprovedEmpty => 'No approved missions yet.';

  @override
  String get approvalsRetryEmpty => 'No missions sent back for a retry.';

  @override
  String approvalsMissionLabel(String title) {
    return 'Mission: $title';
  }

  @override
  String get approvalsMissionRemoved => 'Removed mission';

  @override
  String get approvalsNoNote => 'No note was added.';

  @override
  String approvalsNoteFrom(String name) {
    return '$name\'s Note';
  }

  @override
  String get approvalsPrivacy => 'Visible only to parents in your family.';

  @override
  String get approvalsProofImage => 'Submitted photo';

  @override
  String get approvalsProofUnavailable => 'The photo couldn\'t be loaded.';

  @override
  String approvalsApprove(int stars) {
    return 'Approve & Award +$stars ⭐';
  }

  @override
  String get approvalsAskRetry => 'Ask to Retry ✏️';

  @override
  String get approvalsRetry => 'Ask to retry';

  @override
  String get approvalsDecline => 'Decline';

  @override
  String approvalsRetryTitle(String name) {
    return 'Ask $name to try again?';
  }

  @override
  String approvalsDeclineTitle(String name) {
    return 'Decline $name\'s submission?';
  }

  @override
  String get approvalsNoteLabel => 'Note for your child (optional)';

  @override
  String approvalsApprovedToast(String name, int stars) {
    return 'Approved! $stars stars sent to $name.';
  }

  @override
  String approvalsRetryToast(String name) {
    return '$name will be asked to try again.';
  }

  @override
  String get approvalsDeclinedToast => 'Submission declined.';

  @override
  String get approvalsAlreadyReviewed =>
      'This submission was already reviewed. The list has been refreshed.';

  @override
  String approvalsStarsCredited(int count) {
    return '+$count Stars credited';
  }

  @override
  String get approvalsRetrySent => 'Retry requested';

  @override
  String get approvalsTipTitle => 'Praise Effort over Perfection';

  @override
  String get approvalsTipBody =>
      'A quick cheer or a loving note when you review helps your child feel proud of the effort, not just the result.';

  @override
  String get reportsAppBar => 'Parent Overview';

  @override
  String get reportsEyebrow => 'Weekly Health & Growth';

  @override
  String reportsWelcome(String name) {
    return 'Welcome, $name';
  }

  @override
  String get reportsOpen => 'Stars, streaks and badges this week';

  @override
  String childNameWithAge(String name, int age) {
    return '$name (Age $age)';
  }

  @override
  String get reportsMissionsDone => 'Missions Done';

  @override
  String reportsActiveDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active days this week',
      one: '1 active day this week',
      zero: 'No active days yet',
    );
    return '$_temp0';
  }

  @override
  String get reportsStarsAwarded => 'Stars Awarded';

  @override
  String reportsStarBalance(int count) {
    return 'Balance: $count stars';
  }

  @override
  String get reportsStreak => 'Day Streak';

  @override
  String reportsLongestStreak(int count) {
    return 'Best: $count days';
  }

  @override
  String get reportsXpEarned => 'XP Earned';

  @override
  String reportsTotalXp(int count) {
    return '$count XP in total';
  }

  @override
  String reportsLevel(int level, String name) {
    return 'Level $level $name';
  }

  @override
  String get reportsChartTitle => 'Weekly Missions Completed';

  @override
  String get reportsChartSubtitle => 'Parent-approved missions per day';

  @override
  String get reportsNoActivity => 'No approved missions this week yet.';

  @override
  String reportsBestDay(String day, int count) {
    return 'Best day: $day ($count completed)';
  }

  @override
  String get reportsNoBadges =>
      'No badges yet. They unlock as missions are approved.';

  @override
  String get reportsVerifiedTitle => 'Parent-Verified Logs';

  @override
  String get reportsVerifiedBody =>
      'All statistics reflect parent-approved missions only.';

  @override
  String get reportsCopySummary => 'Copy Weekly Summary';

  @override
  String get reportsSummaryCopied => 'Weekly summary copied';

  @override
  String reportsSummaryText(
    String name,
    String range,
    int missions,
    int stars,
    int xp,
    int streak,
  ) {
    return '$name, $range: $missions missions approved, $stars stars and $xp XP earned, $streak-day streak.';
  }

  @override
  String get badgesTitle => 'Badges & Trophies';

  @override
  String badgesUnlocked(int count) {
    return '$count Unlocked';
  }

  @override
  String get badgesEmpty => 'Finish missions to unlock your first badge!';

  @override
  String badgeUnlockedOn(String date) {
    return 'Unlocked $date';
  }

  @override
  String get familyManageAppBar => 'Family Management';

  @override
  String get familyManageSubtitle =>
      'Manage your child\'s profile, progress and child mode.';

  @override
  String get childProfileMissing => 'This profile is no longer available.';

  @override
  String get backToParentHub => 'Back to Parent Hub';

  @override
  String childOpenProfile(String name) {
    return 'Open $name\'s profile';
  }

  @override
  String availableStars(int count) {
    return '$count Available Stars';
  }

  @override
  String get viewActivityHistory => 'View Activity History';

  @override
  String missionsApprovedRecently(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missions approved in the last 90 days',
      one: '1 mission approved in the last 90 days',
      zero: 'No missions approved in the last 90 days',
    );
    return '$_temp0';
  }

  @override
  String childModeHint(String name) {
    return 'Hand this device to $name';
  }

  @override
  String get addAnotherChild => '+ Add Another Child';

  @override
  String get profileActive => 'Active';

  @override
  String profileAge(int age) {
    return 'Age: $age yrs';
  }

  @override
  String get editProfileTitle => 'Edit profile';

  @override
  String get profileSaved => 'Profile saved';

  @override
  String get removeChildTitle => 'Remove Profile';

  @override
  String removeChildBody(String name) {
    return 'Deactivates $name\'s profile and child mode. Missions, stars and progress stay stored on the server; permanent deletion is not available in the app yet.';
  }

  @override
  String removeChildButton(String name) {
    return 'Remove $name\'s Profile';
  }

  @override
  String removeChildConfirmTitle(String name) {
    return 'Remove $name\'s profile?';
  }

  @override
  String removeChildConfirmBody(String name) {
    return '$name will no longer be able to use child mode, and the profile disappears from your family. Bal Kavach keeps the mission and star records on the server.';
  }

  @override
  String get removeChildConfirm => 'Remove';

  @override
  String removeChildDone(String name) {
    return '$name\'s profile was removed.';
  }

  @override
  String get settingsAppBar => 'Parent Settings';

  @override
  String get settingsFamilyAccount => 'Family Account';

  @override
  String get settingsPrimaryAdmin => 'FAMILY OWNER';

  @override
  String get settingsLinkedChildren => 'Linked Explorers';

  @override
  String get settingsSafety => 'Safety & Approvals';

  @override
  String get settingsApprovalTitle => 'Parent approval required';

  @override
  String get settingsApprovalBody =>
      'Every mission and reward request waits for your review before stars change.';

  @override
  String get settingsAlwaysOn => 'Always on';

  @override
  String get settingsPreferences => 'App & Privacy Preferences';

  @override
  String get settingsLanguage => 'App Language';

  @override
  String get settingsChange => 'Change';

  @override
  String get settingsPush => 'Push notifications';

  @override
  String get settingsPushBody => 'Preference saved to your account';

  @override
  String get settingsEmail => 'Email notifications';

  @override
  String get settingsEmailBody => 'Bal Kavach doesn\'t send emails yet.';

  @override
  String get settingsPrivacyTitle => 'Privacy & Consent';

  @override
  String get settingsPrivacyBody =>
      'Consent you gave for your family, as stored by Bal Kavach.';

  @override
  String get settingsNoConsents => 'No consent records yet.';

  @override
  String settingsConsentRow(String version, String date, String status) {
    return 'Parent & guardian terms • version $version • $date • $status';
  }

  @override
  String get settingsConsentActive => 'Active';

  @override
  String get settingsConsentRevoked => 'Revoked';

  @override
  String get settingsLogOut => 'Log Out';

  @override
  String get settingsFooter => 'Bal Kavach AI • Made for Indian families';

  @override
  String get rewardsTitle => 'Child Rewards';

  @override
  String get rewardsVault => 'Bal Kavach Vault';

  @override
  String get rewardsBalance => 'Current Star Balance';

  @override
  String rewardsBalanceSemantics(int count) {
    return '$count stars in your vault';
  }

  @override
  String rewardsStreak(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Days Streak!',
      one: '1 Day Streak!',
      zero: 'Start a streak today!',
    );
    return '$_temp0';
  }

  @override
  String get rewardsCatalog => 'Treasure Catalog';

  @override
  String get rewardsCatalogSoonTitle => 'The treasure shop is coming soon';

  @override
  String get rewardsCatalogSoonBody =>
      'Keep collecting stars! Ask Mummy or Papa which treats your stars can unlock.';

  @override
  String get rewardsMyRequests => 'My reward requests';

  @override
  String get rewardsRequest => 'Reward request';

  @override
  String get rewardsRequestsUnavailable =>
      'Couldn\'t load your reward requests right now.';

  @override
  String get rewardsFulfilled => 'Ready to enjoy';

  @override
  String get rewardsCancelled => 'Cancelled';

  @override
  String get gardenTitle => 'Mindful Garden';

  @override
  String gardenOwner(String name) {
    return '$name\'s Mindful Garden';
  }

  @override
  String gardenStage(String stage) {
    return 'Stage: $stage';
  }

  @override
  String get gardenStageSeed => 'Little Seed';

  @override
  String get gardenStageSprout => 'Tiny Sprout';

  @override
  String get gardenStageSapling => 'Happy Mango Sapling';

  @override
  String get gardenStageTree => 'Blooming Tree';

  @override
  String gardenNextStage(int count, String stage) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more approved missions to reach $stage',
      one: '1 more approved mission to reach $stage',
    );
    return '$_temp0';
  }

  @override
  String get gardenFullBloom => 'Your garden is in full bloom this week! 🌳';

  @override
  String get gardenGrowsHint =>
      'Grows every time Mummy & Papa approve your missions this week.';

  @override
  String get gardenImageLabel => 'Kavach Panda watering the garden';

  @override
  String gardenWeeklyMissions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Missions',
      one: '1 Mission',
    );
    return '$_temp0';
  }

  @override
  String get gardenWeeklyBody => 'Approved this week to grow your garden';

  @override
  String get gardenMilestones => 'Decorations & Milestones';

  @override
  String gardenMilestonesCount(int done, int total) {
    return '$done / $total Collected';
  }

  @override
  String get milestoneRainbow => 'Rainbow Arch';

  @override
  String get milestoneSunflower => 'Sunflower Patch';

  @override
  String get milestoneBirdhouse => 'Birdhouse';

  @override
  String get milestoneFountain => 'Fairy Fountain';

  @override
  String get milestoneActive => 'ACTIVE';

  @override
  String get milestoneUnlocked => 'Unlocked';

  @override
  String milestoneEarned(int days) {
    return 'Unlocked by a $days-day streak';
  }

  @override
  String milestoneLocked(int days) {
    return 'Reach a $days-day streak to unlock';
  }

  @override
  String get gardenTipTitle => 'Panda\'s Mindful Tip';

  @override
  String get gardenTipBody =>
      '\"Just 30 minutes of outdoor play keeps your mind fresh and happy!\"';

  @override
  String get editMissionTitle => 'Edit mission';

  @override
  String get createMissionDue => 'Due date';

  @override
  String get createMissionDuePick => 'Set due date';

  @override
  String get createMissionDueClear => 'Clear due date';

  @override
  String get missionSaved => 'Mission saved';

  @override
  String get removeMissionButton => 'Remove mission';

  @override
  String get removeMissionConfirmTitle => 'Remove this mission?';

  @override
  String removeMissionConfirmBody(String title) {
    return '\"$title\" will disappear for your children. Missions already sent for review stay on record.';
  }

  @override
  String get removeMissionConfirm => 'Remove';

  @override
  String get removeMissionDone => 'Mission removed';

  @override
  String parentMissionEdit(String title) {
    return 'Edit mission $title';
  }

  @override
  String get showMore => 'Show more';

  @override
  String approvalsPartial(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count missions could not be loaded, so their submissions may be missing.',
      one: '1 mission could not be loaded, so its submissions may be missing.',
    );
    return '$_temp0';
  }

  @override
  String get approvalsUnread =>
      'Some updates are older than the app can load. Older submissions may not appear.';

  @override
  String get submitAddPhoto => 'Add a photo';

  @override
  String get submitTakePhoto => 'Take a photo';

  @override
  String get submitChoosePhoto => 'Choose from gallery';

  @override
  String get submitRemovePhoto => 'Remove photo';

  @override
  String get submitPhotoReady => 'Photo ready to send';

  @override
  String get submitPhotoPreview => 'Preview of your photo';

  @override
  String get submitPhotoHelp =>
      'A photo helps your parent check your mission. You can also just write a note.';

  @override
  String get submitPhotoPickFailed =>
      'We couldn\'t open the camera or gallery. Check the app\'s permission in Settings.';

  @override
  String get submitUploading => 'Sending your photo…';

  @override
  String get errorPhotoTooLarge =>
      'That photo is too large. Try a smaller one.';

  @override
  String get errorPhotoUnsupported => 'Please use a JPEG, PNG or WebP photo.';

  @override
  String get errorPhotoQuota =>
      'You have photos that were not sent yet. Send a mission first.';

  @override
  String get errorPhotoStorage =>
      'Photos can\'t be saved right now. Try again, or send a note instead.';

  @override
  String get errorAlreadyPending =>
      'This mission is already waiting for your parent to check.';

  @override
  String get errorAlreadyCompleted =>
      'You have already completed this mission. Well done!';

  @override
  String get historyTitle => 'Your tries';

  @override
  String historyAttempt(int number) {
    return 'Try $number';
  }

  @override
  String get historyParentNote => 'Note from your parent';

  @override
  String get statusPendingShort => 'Waiting';

  @override
  String get statusApprovedShort => 'Approved';

  @override
  String get statusRejectedShort => 'Try again';

  @override
  String get statusResubmitShort => 'Send again';

  @override
  String get approvalsProofZoom => 'Tap to enlarge';

  @override
  String get close => 'Close';

  @override
  String get rewardsCatalogEmpty =>
      'No rewards yet. Ask your parent to add some!';

  @override
  String get rewardsAsk => 'Ask for this';

  @override
  String rewardsNeedMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more stars to go',
      one: '1 more star to go',
    );
    return '$_temp0';
  }

  @override
  String get rewardsAlreadyAsked => 'Waiting for your parent';

  @override
  String rewardsConfirmTitle(String name) {
    return 'Ask for $name?';
  }

  @override
  String rewardsConfirmBody(int count) {
    return 'This uses $count stars if your parent says yes. Nothing is taken until then.';
  }

  @override
  String get rewardsConfirmYes => 'Yes, ask';

  @override
  String get rewardsAsked => 'Request sent to your parent!';

  @override
  String get rewardsCancelRequest => 'Cancel request';

  @override
  String get rewardsRequestCancelled => 'Request cancelled';

  @override
  String rewardsParentNote(String note) {
    return 'Parent\'s note: $note';
  }

  @override
  String rewardsRequestNamed(String name) {
    return 'Request for $name';
  }

  @override
  String get errorNotEnoughStars => 'There aren\'t enough stars for this.';

  @override
  String get errorRewardPending => 'That reward was already asked for.';

  @override
  String get errorRewardUnavailable => 'That reward isn\'t available any more.';

  @override
  String get parentRewardsTitle => 'Rewards';

  @override
  String get parentRewardsSubtitle => 'Choose rewards and answer requests';

  @override
  String parentRewardsRequestsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count requests waiting',
      one: '1 request waiting',
      zero: 'No requests waiting',
    );
    return '$_temp0';
  }

  @override
  String get rewardsTabCatalog => 'Rewards';

  @override
  String get rewardsTabRequests => 'Requests';

  @override
  String get rewardsRequestsEmpty => 'No requests waiting.';

  @override
  String get rewardsAddReward => 'Add reward';

  @override
  String get rewardsEditReward => 'Edit reward';

  @override
  String get rewardsFormName => 'Reward name';

  @override
  String get rewardsFormDescription => 'Description';

  @override
  String get rewardsFormCost => 'Star cost';

  @override
  String get rewardsFormType => 'Type';

  @override
  String get rewardTypeCustom => 'Something special';

  @override
  String get rewardTypeGift => 'Gift';

  @override
  String get rewardTypeBook => 'Book';

  @override
  String get rewardTypeOutdoor => 'Outdoor activity';

  @override
  String get rewardTypeScreenTime => 'Screen time';

  @override
  String get rewardsRemove => 'Remove reward';

  @override
  String rewardsRemoveConfirm(String name) {
    return 'Remove $name? Children will no longer see it.';
  }

  @override
  String get rewardsSaved => 'Reward saved';

  @override
  String get rewardsRemoved => 'Reward removed';

  @override
  String rewardsAskedBy(String child, String reward) {
    return '$child asked for $reward';
  }

  @override
  String rewardsApprove(int count) {
    return 'Approve ($count stars)';
  }

  @override
  String get rewardsDecline => 'Decline';

  @override
  String get rewardsMarkGiven => 'Mark as given';

  @override
  String get rewardsCancelRefund => 'Cancel and return stars';

  @override
  String rewardsApprovedToast(int count) {
    return 'Approved. $count stars were taken.';
  }

  @override
  String get rewardsDeclinedToast => 'Request declined';

  @override
  String get rewardsGivenToast => 'Marked as given';

  @override
  String get rewardsRefundedToast => 'Cancelled and stars returned';

  @override
  String get rewardsAlreadyReviewed => 'This request was already handled.';

  @override
  String get rewardsNoteOptional => 'Note for your child (optional)';

  @override
  String get rewardsDeclineTitle => 'Decline this request?';

  @override
  String get save => 'Save';

  @override
  String get reportsPreviousWeek => 'Previous week';

  @override
  String get reportsNextWeek => 'Next week';

  @override
  String get reportsThisWeek => 'This week';

  @override
  String get reportsCategoriesTitle => 'By activity';

  @override
  String get reportsCategoriesEmpty => 'No approved missions this week yet.';

  @override
  String reportsCategoryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missions',
      one: '1 mission',
    );
    return '$_temp0';
  }

  @override
  String get reportsUncategorised => 'Other';

  @override
  String reportsPendingNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missions waiting for your review',
      one: '1 mission waiting for your review',
    );
    return '$_temp0';
  }

  @override
  String reportsRetryNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count missions need another try',
      one: '1 mission needs another try',
    );
    return '$_temp0';
  }

  @override
  String reportsTimezoneNote(String zone) {
    return 'Days follow $zone time.';
  }

  @override
  String get reportsShare => 'Share progress';

  @override
  String reportsShareSubject(String name) {
    return '$name\'s weekly progress';
  }

  @override
  String get reportsShareFailed => 'Couldn\'t open sharing. Try Copy instead.';

  @override
  String get maintenanceDefault =>
      'Bal Kavach is being updated. Some things may not work for a while.';

  @override
  String get settingsTimezone => 'Time zone';

  @override
  String get settingsTimezoneBody =>
      'Decides which day a mission counts for in reports and streaks. Saved to your family.';

  @override
  String settingsTimezoneUseDevice(String zone) {
    return 'Use this phone\'s time zone ($zone)';
  }

  @override
  String get settingsTimezoneSaved => 'Time zone saved';

  @override
  String get settingsSavedWhereTitle => 'What is saved where';

  @override
  String get settingsSavedAccount =>
      'Saved to your account: language, push choice, family time zone, consent.';

  @override
  String get settingsSavedDevice =>
      'Saved on this phone only: each child\'s avatar picture.';

  @override
  String get settingsPrivacySafetyTitle => 'Privacy & safety';

  @override
  String get safetyPointFamilyOnly =>
      'Missions, photos and progress can only be seen by your family\'s parents and by the child they belong to.';

  @override
  String get safetyPointPhotos =>
      'Photos are checked, resized and stripped of location details before they are saved.';

  @override
  String get safetyPointChildMode =>
      'Child mode never has your email or password and cannot open parent screens.';

  @override
  String get safetyPointApprovals =>
      'Stars, XP and rewards only change after a parent decides.';

  @override
  String get safetyPointNotifications =>
      'Notifications never show your child\'s name or mission details.';

  @override
  String get safetyPointNoAds => 'Bal Kavach shows no ads.';

  @override
  String get childSignOutDevices => 'Sign out on all devices';

  @override
  String childSignOutDevicesBody(String name) {
    return 'Ends $name\'s sign-in everywhere, for example on a lost tablet.';
  }

  @override
  String get childSignOutDevicesDone => 'Signed out on all devices';

  @override
  String get childSignOutDevicesConfirm => 'Sign out';

  @override
  String get navLearn => 'Learn';

  @override
  String get learnTitle => 'Learn & Watch';

  @override
  String get learnAll => 'All';

  @override
  String get learnEmpty => 'Nothing to learn here yet. Check back soon!';

  @override
  String get learnOpen => 'Open';

  @override
  String get learnOpensOutside => 'Opens in your browser or the video app.';

  @override
  String get learnOpenFailed => 'We couldn\'t open that link.';

  @override
  String get learnLocked => 'Ask your parent to unlock this with a reward.';

  @override
  String get learnNotReady => 'This one isn\'t ready to play yet.';

  @override
  String get learnTypeVideo => 'Video';

  @override
  String get learnTypeArticle => 'Article';

  @override
  String get learnTypeLink => 'Link';

  @override
  String get learnTypeDocument => 'Document';

  @override
  String get learnTypeActivity => 'Activity';

  @override
  String get learnCategoryLearning => 'Learning';

  @override
  String get learnCategoryStories => 'Stories';

  @override
  String get learnCategoryScience => 'Science';

  @override
  String get learnCategoryCreativity => 'Creativity';

  @override
  String get learnCategoryHealthyHabits => 'Healthy Habits';

  @override
  String get learnMore => 'Load more';

  @override
  String get gardenCollection => 'Garden collection';

  @override
  String gardenCollectionCount(int unlocked, int total) {
    return '$unlocked of $total unlocked';
  }

  @override
  String gardenServerStage(String name) {
    return 'Garden size: $name';
  }

  @override
  String gardenXpToNext(int count) {
    return '$count XP until it grows again';
  }

  @override
  String get gardenStageYoungTree => 'Young tree';

  @override
  String get gardenStageBlossom => 'In blossom';

  @override
  String get gardenStageOrchard => 'Orchard';

  @override
  String get gardenItemFirstMission => 'Little fence';

  @override
  String get gardenItemMissionMaster => 'Garden gate';

  @override
  String get gardenItemStarCollector => 'Star lantern';

  @override
  String get gardenItemXpClimber => 'Flower bed';

  @override
  String get gardenItemThreeDayStreak => 'Rainbow';

  @override
  String get gardenItemWeekWarrior => 'Fountain';

  @override
  String gardenItemLocked(String badge) {
    return 'Earn the “$badge” badge to unlock';
  }

  @override
  String get gardenItemUnknown => 'Garden surprise';

  @override
  String get createMissionIdeas => 'Choose from ideas';

  @override
  String get createMissionIdeasTitle => 'Mission ideas';

  @override
  String get createMissionIdeasEmpty => 'No ideas available right now.';

  @override
  String get createMissionIdeasHint => 'You can change anything before saving.';
}
