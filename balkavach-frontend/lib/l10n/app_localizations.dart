import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach AI'**
  String get appTitle;

  /// No description provided for @brandEyebrow.
  ///
  /// In en, this message translates to:
  /// **'KIDS DIGITAL GUARDIAN'**
  String get brandEyebrow;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach'**
  String get brandName;

  /// No description provided for @brandSuffix.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get brandSuffix;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach Bal Kavach. Check your internet connection.'**
  String get errorNetwork;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The server is taking a while. It may be waking up, so please try again.'**
  String get errorTimeout;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have access to this.'**
  String get errorForbidden;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find that.'**
  String get errorNotFound;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem. Please try again soon.'**
  String get errorServer;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Safe Childhood, Smart Future • Play • Learn • Grow Together'**
  String get welcomeTagline;

  /// No description provided for @welcomeMascotLabel.
  ///
  /// In en, this message translates to:
  /// **'Kavach Panda'**
  String get welcomeMascotLabel;

  /// No description provided for @welcomeBuddyLabel.
  ///
  /// In en, this message translates to:
  /// **'AI Buddy'**
  String get welcomeBuddyLabel;

  /// No description provided for @welcomeBubble.
  ///
  /// In en, this message translates to:
  /// **'Namaste! Choose your language'**
  String get welcomeBubble;

  /// No description provided for @welcomeSelectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select App Language'**
  String get welcomeSelectLanguage;

  /// No description provided for @welcomeChangeAnytime.
  ///
  /// In en, this message translates to:
  /// **'You can change anytime'**
  String get welcomeChangeAnytime;

  /// No description provided for @welcomeGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get welcomeGetStarted;

  /// No description provided for @welcomeFooter.
  ///
  /// In en, this message translates to:
  /// **'Private • Ad-Free • 100% Parent Controlled'**
  String get welcomeFooter;

  /// No description provided for @consentEyebrow.
  ///
  /// In en, this message translates to:
  /// **'BAL KAVACH ECOSYSTEM'**
  String get consentEyebrow;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent Safety First'**
  String get consentTitle;

  /// No description provided for @consentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your child\'s digital wellbeing and safety are our highest priorities.'**
  String get consentSubtitle;

  /// No description provided for @consentApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent Approval Required'**
  String get consentApprovalTitle;

  /// No description provided for @consentApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'All child mission submissions and star reward redemptions require your explicit tap.'**
  String get consentApprovalBody;

  /// No description provided for @consentAdsTitle.
  ///
  /// In en, this message translates to:
  /// **'Zero Advertisements'**
  String get consentAdsTitle;

  /// No description provided for @consentAdsBody.
  ///
  /// In en, this message translates to:
  /// **'100% ad-free environment. No commercial trackers, marketing profiling, or third-party retargeting.'**
  String get consentAdsBody;

  /// No description provided for @consentPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Private Family Sanctuary'**
  String get consentPrivateTitle;

  /// No description provided for @consentPrivateBody.
  ///
  /// In en, this message translates to:
  /// **'No public child directories and zero stranger communication.'**
  String get consentPrivateBody;

  /// No description provided for @consentGoalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent-Controlled Goals'**
  String get consentGoalsTitle;

  /// No description provided for @consentGoalsBody.
  ///
  /// In en, this message translates to:
  /// **'You set everyday missions and review every submission before stars are awarded.'**
  String get consentGoalsBody;

  /// No description provided for @consentCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I confirm I am the parent or legal guardian and agree to the Terms of Service & Child Data Protection Policy.'**
  String get consentCheckbox;

  /// No description provided for @consentCheckboxRequired.
  ///
  /// In en, this message translates to:
  /// **'Please confirm you are the parent or legal guardian to continue.'**
  String get consentCheckboxRequired;

  /// No description provided for @consentContinue.
  ///
  /// In en, this message translates to:
  /// **'I Agree & Continue'**
  String get consentContinue;

  /// No description provided for @roleTitle.
  ///
  /// In en, this message translates to:
  /// **'Who is using Bal Kavach?'**
  String get roleTitle;

  /// No description provided for @roleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Parents set up the family first. Children join through a parent.'**
  String get roleSubtitle;

  /// No description provided for @roleParent.
  ///
  /// In en, this message translates to:
  /// **'I\'m a Parent'**
  String get roleParent;

  /// No description provided for @roleParentBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in, add your children, create missions and approve progress.'**
  String get roleParentBody;

  /// No description provided for @roleChild.
  ///
  /// In en, this message translates to:
  /// **'I\'m a Child'**
  String get roleChild;

  /// No description provided for @roleChildBody.
  ///
  /// In en, this message translates to:
  /// **'Play missions after a parent starts child mode for you.'**
  String get roleChildBody;

  /// No description provided for @childStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask a parent to help'**
  String get childStartTitle;

  /// No description provided for @childStartBody.
  ///
  /// In en, this message translates to:
  /// **'Child mode is started from a parent account. Ask your parent to sign in, choose your profile and tap “Start child mode”.'**
  String get childStartBody;

  /// No description provided for @childStartParentSignIn.
  ///
  /// In en, this message translates to:
  /// **'Parent sign in'**
  String get childStartParentSignIn;

  /// No description provided for @authHeroEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PARENTAL SAFESPHERE GATE'**
  String get authHeroEyebrow;

  /// No description provided for @authHeroCaption.
  ///
  /// In en, this message translates to:
  /// **'Dual-perspective guardianship & child well-being'**
  String get authHeroCaption;

  /// No description provided for @authTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent Login / Register'**
  String get authTitle;

  /// No description provided for @authSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Secure access to your family\'s safety hub'**
  String get authSubtitle;

  /// No description provided for @authTabSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authTabSignIn;

  /// No description provided for @authTabRegister.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authTabRegister;

  /// No description provided for @authFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get authFullName;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'At least 12 characters'**
  String get authPasswordHint;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authSignInButton.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInButton;

  /// No description provided for @authRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterButton;

  /// No description provided for @authUnavailableMethods.
  ///
  /// In en, this message translates to:
  /// **'Phone OTP and Google sign-in are not available yet. Please use email and password.'**
  String get authUnavailableMethods;

  /// No description provided for @authInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get authInvalidCredentials;

  /// No description provided for @authEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Try signing in.'**
  String get authEmailInUse;

  /// No description provided for @validationNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name.'**
  String get validationNameRequired;

  /// No description provided for @validationNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 2 characters.'**
  String get validationNameTooShort;

  /// No description provided for @validationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get validationEmailInvalid;

  /// No description provided for @validationPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password.'**
  String get validationPasswordRequired;

  /// No description provided for @validationPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 12 characters.'**
  String get validationPasswordTooShort;

  /// No description provided for @validationTooLong.
  ///
  /// In en, this message translates to:
  /// **'Use at most {max} characters.'**
  String validationTooLong(int max);

  /// No description provided for @validationNumberRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a number from {min} to {max}.'**
  String validationNumberRange(int min, int max);

  /// No description provided for @parentHubTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent Hub'**
  String get parentHubTitle;

  /// No description provided for @parentGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String parentGreeting(String name);

  /// No description provided for @parentSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get parentSignOut;

  /// No description provided for @familyCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your family'**
  String get familyCreateTitle;

  /// No description provided for @familyCreateBody.
  ///
  /// In en, this message translates to:
  /// **'Name your family to start adding children.'**
  String get familyCreateBody;

  /// No description provided for @familyNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Family name'**
  String get familyNameLabel;

  /// No description provided for @familyCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create family'**
  String get familyCreateButton;

  /// No description provided for @consentSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your consent record yet. We\'ll retry next time.'**
  String get consentSyncFailed;

  /// No description provided for @childrenTitle.
  ///
  /// In en, this message translates to:
  /// **'Your children'**
  String get childrenTitle;

  /// No description provided for @childrenEmpty.
  ///
  /// In en, this message translates to:
  /// **'No child profiles yet. Add your first child to get started.'**
  String get childrenEmpty;

  /// No description provided for @childrenAdd.
  ///
  /// In en, this message translates to:
  /// **'Add child'**
  String get childrenAdd;

  /// No description provided for @childStartMode.
  ///
  /// In en, this message translates to:
  /// **'Start child mode'**
  String get childStartMode;

  /// No description provided for @childModeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Start child mode for {name}?'**
  String childModeConfirmTitle(String name);

  /// No description provided for @childModeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This device will switch to {name}\'s missions. To come back, a parent must sign in again.'**
  String childModeConfirmBody(String name);

  /// No description provided for @childModeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get childModeConfirm;

  /// No description provided for @parentMissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get parentMissionsTitle;

  /// No description provided for @parentMissionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No missions yet. Create the first one for your family.'**
  String get parentMissionsEmpty;

  /// No description provided for @parentMissionsNew.
  ///
  /// In en, this message translates to:
  /// **'New mission'**
  String get parentMissionsNew;

  /// No description provided for @missionForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get missionForEveryone;

  /// No description provided for @missionAssignedTo.
  ///
  /// In en, this message translates to:
  /// **'For {name}'**
  String missionAssignedTo(String name);

  /// No description provided for @createChildEyebrow.
  ///
  /// In en, this message translates to:
  /// **'PLAYFUL SAFETY'**
  String get createChildEyebrow;

  /// No description provided for @createChildTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Your Child\'s Profile'**
  String get createChildTitle;

  /// No description provided for @createChildSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personalize daily habits, missions, and fun learning.'**
  String get createChildSubtitle;

  /// No description provided for @createChildName.
  ///
  /// In en, this message translates to:
  /// **'Child\'s name'**
  String get createChildName;

  /// No description provided for @createChildNameHint.
  ///
  /// In en, this message translates to:
  /// **'Preferred nickname'**
  String get createChildNameHint;

  /// No description provided for @createChildDob.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get createChildDob;

  /// No description provided for @createChildDobPick.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get createChildDobPick;

  /// No description provided for @createChildDobClear.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get createChildDobClear;

  /// No description provided for @createChildAvatar.
  ///
  /// In en, this message translates to:
  /// **'Choose Avatar'**
  String get createChildAvatar;

  /// No description provided for @createChildAvatarLocal.
  ///
  /// In en, this message translates to:
  /// **'The avatar is saved on this device only.'**
  String get createChildAvatarLocal;

  /// No description provided for @createChildLanguage.
  ///
  /// In en, this message translates to:
  /// **'Child\'s language'**
  String get createChildLanguage;

  /// No description provided for @createChildSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create {name}\'s Profile'**
  String createChildSubmit(String name);

  /// No description provided for @createChildSubmitGeneric.
  ///
  /// In en, this message translates to:
  /// **'Create Profile'**
  String get createChildSubmitGeneric;

  /// No description provided for @createChildSuccess.
  ///
  /// In en, this message translates to:
  /// **'Profile created'**
  String get createChildSuccess;

  /// No description provided for @createMissionTitle.
  ///
  /// In en, this message translates to:
  /// **'New mission'**
  String get createMissionTitle;

  /// No description provided for @createMissionName.
  ///
  /// In en, this message translates to:
  /// **'Mission title'**
  String get createMissionName;

  /// No description provided for @createMissionDescription.
  ///
  /// In en, this message translates to:
  /// **'What should your child do?'**
  String get createMissionDescription;

  /// No description provided for @createMissionCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get createMissionCategory;

  /// No description provided for @createMissionNoCategory.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get createMissionNoCategory;

  /// No description provided for @createMissionAssign.
  ///
  /// In en, this message translates to:
  /// **'Who is it for?'**
  String get createMissionAssign;

  /// No description provided for @createMissionStars.
  ///
  /// In en, this message translates to:
  /// **'Stars'**
  String get createMissionStars;

  /// No description provided for @createMissionXp.
  ///
  /// In en, this message translates to:
  /// **'XP'**
  String get createMissionXp;

  /// No description provided for @createMissionSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create mission'**
  String get createMissionSubmit;

  /// No description provided for @createMissionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Mission created'**
  String get createMissionSuccess;

  /// No description provided for @childHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Home'**
  String get childHomeTitle;

  /// No description provided for @parentGate.
  ///
  /// In en, this message translates to:
  /// **'Parent Gate'**
  String get parentGate;

  /// No description provided for @parentGateTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave child mode?'**
  String get parentGateTitle;

  /// No description provided for @parentGateBody.
  ///
  /// In en, this message translates to:
  /// **'A parent will need to sign in again to continue.'**
  String get parentGateBody;

  /// No description provided for @parentGateLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get parentGateLeave;

  /// No description provided for @parentGateStay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get parentGateStay;

  /// No description provided for @childHello.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}!'**
  String childHello(String name);

  /// No description provided for @childLevel.
  ///
  /// In en, this message translates to:
  /// **'Lv {level}'**
  String childLevel(int level);

  /// No description provided for @childLevelName.
  ///
  /// In en, this message translates to:
  /// **'{name} • Quest Ready'**
  String childLevelName(String name);

  /// No description provided for @childQuestReady.
  ///
  /// In en, this message translates to:
  /// **'Quest Ready'**
  String get childQuestReady;

  /// No description provided for @statStars.
  ///
  /// In en, this message translates to:
  /// **'Stars'**
  String get statStars;

  /// No description provided for @statStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get statStreak;

  /// No description provided for @statStreakValue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Day} other{{count} Day}}'**
  String statStreakValue(int count);

  /// No description provided for @statXp.
  ///
  /// In en, this message translates to:
  /// **'XP'**
  String get statXp;

  /// No description provided for @mascotReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for today\'s adventures? 🚀'**
  String get mascotReady;

  /// No description provided for @mascotMissionsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{All missions done. Amazing work!} =1{Complete 1 more mission to keep growing!} other{Complete {count} more missions to keep growing!}}'**
  String mascotMissionsLeft(int count);

  /// No description provided for @todaysMissions.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Missions'**
  String get todaysMissions;

  /// No description provided for @missionsDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} Done'**
  String missionsDone(int done, int total);

  /// No description provided for @missionStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get missionStart;

  /// No description provided for @missionsSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all missions'**
  String get missionsSeeAll;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get navMissions;

  /// No description provided for @reviewsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check for parent reviews right now.'**
  String get reviewsUnavailable;

  /// No description provided for @missionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Missions'**
  String get missionsTitle;

  /// No description provided for @missionsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String missionsFilterAll(int count);

  /// No description provided for @missionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No missions yet. Ask your parent to add one!'**
  String get missionsEmpty;

  /// No description provided for @missionsFilterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No missions in this category.'**
  String get missionsFilterEmpty;

  /// No description provided for @pandaSays.
  ///
  /// In en, this message translates to:
  /// **'Panda Kavach says:'**
  String get pandaSays;

  /// No description provided for @pandaEncourage.
  ///
  /// In en, this message translates to:
  /// **'\"Every mission you finish makes you stronger. Keep soaring!\"'**
  String get pandaEncourage;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending Approval'**
  String get statusPending;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Not approved'**
  String get statusRejected;

  /// No description provided for @statusResubmit.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get statusResubmit;

  /// No description provided for @missionStartMission.
  ///
  /// In en, this message translates to:
  /// **'Start Mission'**
  String get missionStartMission;

  /// No description provided for @missionDoAgain.
  ///
  /// In en, this message translates to:
  /// **'Do it again'**
  String get missionDoAgain;

  /// No description provided for @missionStarsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Stars'**
  String missionStarsCount(int count);

  /// No description provided for @missionXpCount.
  ///
  /// In en, this message translates to:
  /// **'{count} XP'**
  String missionXpCount(int count);

  /// No description provided for @missionDue.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String missionDue(String date);

  /// No description provided for @missionDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Mission details'**
  String get missionDetailTitle;

  /// No description provided for @missionWhatToDo.
  ///
  /// In en, this message translates to:
  /// **'What to do'**
  String get missionWhatToDo;

  /// No description provided for @missionNoDescription.
  ///
  /// In en, this message translates to:
  /// **'Your parent didn\'t add extra steps. Do your best and tell them about it!'**
  String get missionNoDescription;

  /// No description provided for @missionEarn.
  ///
  /// In en, this message translates to:
  /// **'Earn {stars} stars by finishing this mission.'**
  String missionEarn(int stars);

  /// No description provided for @missionWaitingButton.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get missionWaitingButton;

  /// No description provided for @missionNotFound.
  ///
  /// In en, this message translates to:
  /// **'This mission is no longer available.'**
  String get missionNotFound;

  /// No description provided for @submitTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Mission'**
  String get submitTitle;

  /// No description provided for @submitEvidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Mission Evidence'**
  String get submitEvidenceTitle;

  /// No description provided for @submitPhotoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Photo proof isn\'t available yet. Tell your parent what you did instead.'**
  String get submitPhotoUnavailable;

  /// No description provided for @submitNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Tell Mummy & Papa about it'**
  String get submitNoteLabel;

  /// No description provided for @submitNoteHint.
  ///
  /// In en, this message translates to:
  /// **'I drew a lion in the jungle!'**
  String get submitNoteHint;

  /// No description provided for @submitPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only visible to your parents in their approval inbox.'**
  String get submitPrivacy;

  /// No description provided for @submitPandaName.
  ///
  /// In en, this message translates to:
  /// **'Kavach Panda'**
  String get submitPandaName;

  /// No description provided for @submitPandaMessage.
  ///
  /// In en, this message translates to:
  /// **'Woohoo! Tap below to send this to Mummy & Papa!'**
  String get submitPandaMessage;

  /// No description provided for @submitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit for Parent Approval'**
  String get submitButton;

  /// No description provided for @submitFooter.
  ///
  /// In en, this message translates to:
  /// **'Once approved, {stars} stars will be added to your treasure chest!'**
  String submitFooter(int stars);

  /// No description provided for @submitNotAssigned.
  ///
  /// In en, this message translates to:
  /// **'This mission belongs to another child.'**
  String get submitNotAssigned;

  /// No description provided for @waitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent to your parent!'**
  String get waitingTitle;

  /// No description provided for @waitingBody.
  ///
  /// In en, this message translates to:
  /// **'Waiting for parent approval. You\'ll see the result here when your parent reviews it.'**
  String get waitingBody;

  /// No description provided for @waitingApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Approved! 🎉'**
  String get waitingApprovedTitle;

  /// No description provided for @waitingApprovedBody.
  ///
  /// In en, this message translates to:
  /// **'+{stars} stars added to your treasure chest.'**
  String waitingApprovedBody(int stars);

  /// No description provided for @waitingRejectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not approved this time'**
  String get waitingRejectedTitle;

  /// No description provided for @waitingRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'Talk to your parent and try again later.'**
  String get waitingRejectedBody;

  /// No description provided for @waitingResubmitTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s try again'**
  String get waitingResubmitTitle;

  /// No description provided for @waitingResubmitBody.
  ///
  /// In en, this message translates to:
  /// **'Your parent asked you to redo this mission.'**
  String get waitingResubmitBody;

  /// No description provided for @waitingCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get waitingCheckAgain;

  /// No description provided for @waitingBackToMissions.
  ///
  /// In en, this message translates to:
  /// **'Back to missions'**
  String get waitingBackToMissions;

  /// No description provided for @serverChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking the Bal Kavach server…'**
  String get serverChecking;

  /// No description provided for @serverOnline.
  ///
  /// In en, this message translates to:
  /// **'Server online'**
  String get serverOnline;

  /// No description provided for @serverDbDown.
  ///
  /// In en, this message translates to:
  /// **'Server is up, but its database is unavailable. Sign-in may fail.'**
  String get serverDbDown;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. It may be starting up.'**
  String get serverUnreachable;

  /// No description provided for @serverStatusNote.
  ///
  /// In en, this message translates to:
  /// **'This only checks the connection, not every feature.'**
  String get serverStatusNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'gu', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'gu':
      return AppLocalizationsGu();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
