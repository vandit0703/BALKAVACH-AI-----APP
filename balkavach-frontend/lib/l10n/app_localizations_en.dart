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
}
