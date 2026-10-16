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

  /// No description provided for @authEmailOrUsername.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get authEmailOrUsername;

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
  /// **'Email, username, or password is incorrect.'**
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

  /// No description provided for @validationUsernameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Use 3-32 characters: start with a letter, then use letters, numbers, dots, underscores, or hyphens.'**
  String get validationUsernameInvalid;

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

  /// No description provided for @createChildUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get createChildUsername;

  /// No description provided for @createChildPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get createChildPassword;

  /// No description provided for @createChildCredentialsButton.
  ///
  /// In en, this message translates to:
  /// **'Show Username & Password'**
  String get createChildCredentialsButton;

  /// No description provided for @createChildCredentialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Child sign-in details'**
  String get createChildCredentialsTitle;

  /// No description provided for @createChildCredentialsMissing.
  ///
  /// In en, this message translates to:
  /// **'This child does not have sign-in details yet. Set them up now.'**
  String get createChildCredentialsMissing;

  /// No description provided for @createChildCredentialsSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up credentials'**
  String get createChildCredentialsSetup;

  /// No description provided for @createChildCredentialsSave.
  ///
  /// In en, this message translates to:
  /// **'Save credentials'**
  String get createChildCredentialsSave;

  /// No description provided for @createChildCredentialsSaved.
  ///
  /// In en, this message translates to:
  /// **'Child credentials updated'**
  String get createChildCredentialsSaved;

  /// No description provided for @createChildCredentialsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Credentials could not be loaded. Please try again.'**
  String get createChildCredentialsUnavailable;

  /// No description provided for @createChildCredentialsClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get createChildCredentialsClose;

  /// No description provided for @createChildCredentialsUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get createChildCredentialsUsername;

  /// No description provided for @createChildCredentialsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get createChildCredentialsPassword;

  /// No description provided for @createChildCredentialsShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get createChildCredentialsShowPassword;

  /// No description provided for @createChildCredentialsHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get createChildCredentialsHidePassword;

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

  /// No description provided for @familyMissing.
  ///
  /// In en, this message translates to:
  /// **'Create your family first on the Parent Hub.'**
  String get familyMissing;

  /// No description provided for @filterAllChildren.
  ///
  /// In en, this message translates to:
  /// **'All children'**
  String get filterAllChildren;

  /// No description provided for @someChild.
  ///
  /// In en, this message translates to:
  /// **'Your child'**
  String get someChild;

  /// No description provided for @navRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get navRewards;

  /// No description provided for @navGarden.
  ///
  /// In en, this message translates to:
  /// **'Garden'**
  String get navGarden;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @approvalsAppBar.
  ///
  /// In en, this message translates to:
  /// **'Parent Missions'**
  String get approvalsAppBar;

  /// No description provided for @approvalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Mission Approvals'**
  String get approvalsTitle;

  /// No description provided for @approvalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review your child\'s offline triumphs and release star rewards.'**
  String get approvalsSubtitle;

  /// No description provided for @approvalsActions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Action} other{{count} Actions}}'**
  String approvalsActions(int count);

  /// No description provided for @approvalsOpen.
  ///
  /// In en, this message translates to:
  /// **'Review submitted missions'**
  String get approvalsOpen;

  /// No description provided for @approvalsPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing waiting for review} =1{1 waiting for review} other{{count} waiting for review}}'**
  String approvalsPendingCount(int count);

  /// No description provided for @approvalsTabPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalsTabPending;

  /// No description provided for @approvalsTabApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvalsTabApproved;

  /// No description provided for @approvalsTabRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get approvalsTabRetry;

  /// No description provided for @approvalsTruncated.
  ///
  /// In en, this message translates to:
  /// **'Showing the most recently submitted missions only. Older submissions may not appear.'**
  String get approvalsTruncated;

  /// No description provided for @approvalsPendingEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to review right now. New submissions will appear here.'**
  String get approvalsPendingEmpty;

  /// No description provided for @approvalsApprovedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No approved missions yet.'**
  String get approvalsApprovedEmpty;

  /// No description provided for @approvalsRetryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No missions sent back for a retry.'**
  String get approvalsRetryEmpty;

  /// No description provided for @approvalsMissionLabel.
  ///
  /// In en, this message translates to:
  /// **'Mission: {title}'**
  String approvalsMissionLabel(String title);

  /// No description provided for @approvalsMissionRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed mission'**
  String get approvalsMissionRemoved;

  /// No description provided for @approvalsNoNote.
  ///
  /// In en, this message translates to:
  /// **'No note was added.'**
  String get approvalsNoNote;

  /// No description provided for @approvalsNoteFrom.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s Note'**
  String approvalsNoteFrom(String name);

  /// No description provided for @approvalsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Visible only to parents in your family.'**
  String get approvalsPrivacy;

  /// No description provided for @approvalsProofImage.
  ///
  /// In en, this message translates to:
  /// **'Submitted photo'**
  String get approvalsProofImage;

  /// No description provided for @approvalsProofUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The photo couldn\'t be loaded.'**
  String get approvalsProofUnavailable;

  /// No description provided for @approvalsApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve & Award +{stars} ⭐'**
  String approvalsApprove(int stars);

  /// No description provided for @approvalsAskRetry.
  ///
  /// In en, this message translates to:
  /// **'Ask to Retry ✏️'**
  String get approvalsAskRetry;

  /// No description provided for @approvalsRetry.
  ///
  /// In en, this message translates to:
  /// **'Ask to retry'**
  String get approvalsRetry;

  /// No description provided for @approvalsDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get approvalsDecline;

  /// No description provided for @approvalsRetryTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask {name} to try again?'**
  String approvalsRetryTitle(String name);

  /// No description provided for @approvalsDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline {name}\'s submission?'**
  String approvalsDeclineTitle(String name);

  /// No description provided for @approvalsNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note for your child (optional)'**
  String get approvalsNoteLabel;

  /// No description provided for @approvalsApprovedToast.
  ///
  /// In en, this message translates to:
  /// **'Approved! {stars} stars sent to {name}.'**
  String approvalsApprovedToast(String name, int stars);

  /// No description provided for @approvalsRetryToast.
  ///
  /// In en, this message translates to:
  /// **'{name} will be asked to try again.'**
  String approvalsRetryToast(String name);

  /// No description provided for @approvalsDeclinedToast.
  ///
  /// In en, this message translates to:
  /// **'Submission declined.'**
  String get approvalsDeclinedToast;

  /// No description provided for @approvalsAlreadyReviewed.
  ///
  /// In en, this message translates to:
  /// **'This submission was already reviewed. The list has been refreshed.'**
  String get approvalsAlreadyReviewed;

  /// No description provided for @approvalsStarsCredited.
  ///
  /// In en, this message translates to:
  /// **'+{count} Stars credited'**
  String approvalsStarsCredited(int count);

  /// No description provided for @approvalsRetrySent.
  ///
  /// In en, this message translates to:
  /// **'Retry requested'**
  String get approvalsRetrySent;

  /// No description provided for @approvalsTipTitle.
  ///
  /// In en, this message translates to:
  /// **'Praise Effort over Perfection'**
  String get approvalsTipTitle;

  /// No description provided for @approvalsTipBody.
  ///
  /// In en, this message translates to:
  /// **'A quick cheer or a loving note when you review helps your child feel proud of the effort, not just the result.'**
  String get approvalsTipBody;

  /// No description provided for @reportsAppBar.
  ///
  /// In en, this message translates to:
  /// **'Parent Overview'**
  String get reportsAppBar;

  /// No description provided for @reportsEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Weekly Health & Growth'**
  String get reportsEyebrow;

  /// No description provided for @reportsWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String reportsWelcome(String name);

  /// No description provided for @reportsOpen.
  ///
  /// In en, this message translates to:
  /// **'Stars, streaks and badges this week'**
  String get reportsOpen;

  /// No description provided for @childNameWithAge.
  ///
  /// In en, this message translates to:
  /// **'{name} (Age {age})'**
  String childNameWithAge(String name, int age);

  /// No description provided for @reportsMissionsDone.
  ///
  /// In en, this message translates to:
  /// **'Missions Done'**
  String get reportsMissionsDone;

  /// No description provided for @reportsActiveDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No active days yet} =1{1 active day this week} other{{count} active days this week}}'**
  String reportsActiveDays(int count);

  /// No description provided for @reportsStarsAwarded.
  ///
  /// In en, this message translates to:
  /// **'Stars Awarded'**
  String get reportsStarsAwarded;

  /// No description provided for @reportsStarBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {count} stars'**
  String reportsStarBalance(int count);

  /// No description provided for @reportsStreak.
  ///
  /// In en, this message translates to:
  /// **'Day Streak'**
  String get reportsStreak;

  /// No description provided for @reportsLongestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best: {count} days'**
  String reportsLongestStreak(int count);

  /// No description provided for @reportsXpEarned.
  ///
  /// In en, this message translates to:
  /// **'XP Earned'**
  String get reportsXpEarned;

  /// No description provided for @reportsTotalXp.
  ///
  /// In en, this message translates to:
  /// **'{count} XP in total'**
  String reportsTotalXp(int count);

  /// No description provided for @reportsLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level} {name}'**
  String reportsLevel(int level, String name);

  /// No description provided for @reportsChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly Missions Completed'**
  String get reportsChartTitle;

  /// No description provided for @reportsChartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Parent-approved missions per day'**
  String get reportsChartSubtitle;

  /// No description provided for @reportsNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No approved missions this week yet.'**
  String get reportsNoActivity;

  /// No description provided for @reportsBestDay.
  ///
  /// In en, this message translates to:
  /// **'Best day: {day} ({count} completed)'**
  String reportsBestDay(String day, int count);

  /// No description provided for @reportsNoBadges.
  ///
  /// In en, this message translates to:
  /// **'No badges yet. They unlock as missions are approved.'**
  String get reportsNoBadges;

  /// No description provided for @reportsVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent-Verified Logs'**
  String get reportsVerifiedTitle;

  /// No description provided for @reportsVerifiedBody.
  ///
  /// In en, this message translates to:
  /// **'All statistics reflect parent-approved missions only.'**
  String get reportsVerifiedBody;

  /// No description provided for @reportsCopySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy Weekly Summary'**
  String get reportsCopySummary;

  /// No description provided for @reportsSummaryCopied.
  ///
  /// In en, this message translates to:
  /// **'Weekly summary copied'**
  String get reportsSummaryCopied;

  /// No description provided for @reportsSummaryText.
  ///
  /// In en, this message translates to:
  /// **'{name}, {range}: {missions} missions approved, {stars} stars and {xp} XP earned, {streak}-day streak.'**
  String reportsSummaryText(
    String name,
    String range,
    int missions,
    int stars,
    int xp,
    int streak,
  );

  /// No description provided for @badgesTitle.
  ///
  /// In en, this message translates to:
  /// **'Badges & Trophies'**
  String get badgesTitle;

  /// No description provided for @badgesUnlocked.
  ///
  /// In en, this message translates to:
  /// **'{count} Unlocked'**
  String badgesUnlocked(int count);

  /// No description provided for @badgesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Finish missions to unlock your first badge!'**
  String get badgesEmpty;

  /// No description provided for @badgeUnlockedOn.
  ///
  /// In en, this message translates to:
  /// **'Unlocked {date}'**
  String badgeUnlockedOn(String date);

  /// No description provided for @familyManageAppBar.
  ///
  /// In en, this message translates to:
  /// **'Family Management'**
  String get familyManageAppBar;

  /// No description provided for @familyManageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your child\'s profile, progress and child mode.'**
  String get familyManageSubtitle;

  /// No description provided for @childProfileMissing.
  ///
  /// In en, this message translates to:
  /// **'This profile is no longer available.'**
  String get childProfileMissing;

  /// No description provided for @backToParentHub.
  ///
  /// In en, this message translates to:
  /// **'Back to Parent Hub'**
  String get backToParentHub;

  /// No description provided for @childOpenProfile.
  ///
  /// In en, this message translates to:
  /// **'Open {name}\'s profile'**
  String childOpenProfile(String name);

  /// No description provided for @availableStars.
  ///
  /// In en, this message translates to:
  /// **'{count} Available Stars'**
  String availableStars(int count);

  /// No description provided for @viewActivityHistory.
  ///
  /// In en, this message translates to:
  /// **'View Activity History'**
  String get viewActivityHistory;

  /// No description provided for @missionsApprovedRecently.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No missions approved in the last 90 days} =1{1 mission approved in the last 90 days} other{{count} missions approved in the last 90 days}}'**
  String missionsApprovedRecently(int count);

  /// No description provided for @childModeHint.
  ///
  /// In en, this message translates to:
  /// **'Hand this device to {name}'**
  String childModeHint(String name);

  /// No description provided for @addAnotherChild.
  ///
  /// In en, this message translates to:
  /// **'+ Add Another Child'**
  String get addAnotherChild;

  /// No description provided for @profileActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profileActive;

  /// No description provided for @profileAge.
  ///
  /// In en, this message translates to:
  /// **'Age: {age} yrs'**
  String profileAge(int age);

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfileTitle;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSaved;

  /// No description provided for @removeChildTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Profile'**
  String get removeChildTitle;

  /// No description provided for @removeChildBody.
  ///
  /// In en, this message translates to:
  /// **'Deactivates {name}\'s profile and child mode. Missions, stars and progress stay stored on the server; permanent deletion is not available in the app yet.'**
  String removeChildBody(String name);

  /// No description provided for @removeChildButton.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}\'s Profile'**
  String removeChildButton(String name);

  /// No description provided for @removeChildConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}\'s profile?'**
  String removeChildConfirmTitle(String name);

  /// No description provided for @removeChildConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will no longer be able to use child mode, and the profile disappears from your family. Bal Kavach keeps the mission and star records on the server.'**
  String removeChildConfirmBody(String name);

  /// No description provided for @removeChildConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeChildConfirm;

  /// No description provided for @removeChildDone.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s profile was removed.'**
  String removeChildDone(String name);

  /// No description provided for @settingsAppBar.
  ///
  /// In en, this message translates to:
  /// **'Parent Settings'**
  String get settingsAppBar;

  /// No description provided for @settingsFamilyAccount.
  ///
  /// In en, this message translates to:
  /// **'Family Account'**
  String get settingsFamilyAccount;

  /// No description provided for @settingsPrimaryAdmin.
  ///
  /// In en, this message translates to:
  /// **'FAMILY OWNER'**
  String get settingsPrimaryAdmin;

  /// No description provided for @settingsLinkedChildren.
  ///
  /// In en, this message translates to:
  /// **'Linked Explorers'**
  String get settingsLinkedChildren;

  /// No description provided for @settingsSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety & Approvals'**
  String get settingsSafety;

  /// No description provided for @settingsApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent approval required'**
  String get settingsApprovalTitle;

  /// No description provided for @settingsApprovalBody.
  ///
  /// In en, this message translates to:
  /// **'Every mission and reward request waits for your review before stars change.'**
  String get settingsApprovalBody;

  /// No description provided for @settingsAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get settingsAlwaysOn;

  /// No description provided for @settingsPreferences.
  ///
  /// In en, this message translates to:
  /// **'App & Privacy Preferences'**
  String get settingsPreferences;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settingsLanguage;

  /// No description provided for @settingsChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get settingsChange;

  /// No description provided for @settingsPush.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get settingsPush;

  /// No description provided for @settingsPushBody.
  ///
  /// In en, this message translates to:
  /// **'Preference saved to your account'**
  String get settingsPushBody;

  /// No description provided for @settingsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email notifications'**
  String get settingsEmail;

  /// No description provided for @settingsEmailBody.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach doesn\'t send emails yet.'**
  String get settingsEmailBody;

  /// No description provided for @settingsPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Consent'**
  String get settingsPrivacyTitle;

  /// No description provided for @settingsPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Consent you gave for your family, as stored by Bal Kavach.'**
  String get settingsPrivacyBody;

  /// No description provided for @settingsNoConsents.
  ///
  /// In en, this message translates to:
  /// **'No consent records yet.'**
  String get settingsNoConsents;

  /// No description provided for @settingsConsentRow.
  ///
  /// In en, this message translates to:
  /// **'Parent & guardian terms • version {version} • {date} • {status}'**
  String settingsConsentRow(String version, String date, String status);

  /// No description provided for @settingsConsentActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsConsentActive;

  /// No description provided for @settingsConsentRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get settingsConsentRevoked;

  /// No description provided for @settingsLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get settingsLogOut;

  /// No description provided for @settingsFooter.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach AI • Made for Indian families'**
  String get settingsFooter;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Rewards'**
  String get rewardsTitle;

  /// No description provided for @rewardsVault.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach Vault'**
  String get rewardsVault;

  /// No description provided for @rewardsBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Star Balance'**
  String get rewardsBalance;

  /// No description provided for @rewardsBalanceSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count} stars in your vault'**
  String rewardsBalanceSemantics(int count);

  /// No description provided for @rewardsStreak.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Start a streak today!} =1{1 Day Streak!} other{{count} Days Streak!}}'**
  String rewardsStreak(int count);

  /// No description provided for @rewardsCatalog.
  ///
  /// In en, this message translates to:
  /// **'Treasure Catalog'**
  String get rewardsCatalog;

  /// No description provided for @rewardsCatalogSoonTitle.
  ///
  /// In en, this message translates to:
  /// **'The treasure shop is coming soon'**
  String get rewardsCatalogSoonTitle;

  /// No description provided for @rewardsCatalogSoonBody.
  ///
  /// In en, this message translates to:
  /// **'Keep collecting stars! Ask Mummy or Papa which treats your stars can unlock.'**
  String get rewardsCatalogSoonBody;

  /// No description provided for @rewardsMyRequests.
  ///
  /// In en, this message translates to:
  /// **'My reward requests'**
  String get rewardsMyRequests;

  /// No description provided for @rewardsRequest.
  ///
  /// In en, this message translates to:
  /// **'Reward request'**
  String get rewardsRequest;

  /// No description provided for @rewardsRequestsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your reward requests right now.'**
  String get rewardsRequestsUnavailable;

  /// No description provided for @rewardsFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Ready to enjoy'**
  String get rewardsFulfilled;

  /// No description provided for @rewardsCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get rewardsCancelled;

  /// No description provided for @gardenTitle.
  ///
  /// In en, this message translates to:
  /// **'Mindful Garden'**
  String get gardenTitle;

  /// No description provided for @gardenOwner.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s Mindful Garden'**
  String gardenOwner(String name);

  /// No description provided for @gardenStage.
  ///
  /// In en, this message translates to:
  /// **'Stage: {stage}'**
  String gardenStage(String stage);

  /// No description provided for @gardenStageSeed.
  ///
  /// In en, this message translates to:
  /// **'Little Seed'**
  String get gardenStageSeed;

  /// No description provided for @gardenStageSprout.
  ///
  /// In en, this message translates to:
  /// **'Tiny Sprout'**
  String get gardenStageSprout;

  /// No description provided for @gardenStageSapling.
  ///
  /// In en, this message translates to:
  /// **'Happy Mango Sapling'**
  String get gardenStageSapling;

  /// No description provided for @gardenStageTree.
  ///
  /// In en, this message translates to:
  /// **'Blooming Tree'**
  String get gardenStageTree;

  /// No description provided for @gardenNextStage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more approved mission to reach {stage}} other{{count} more approved missions to reach {stage}}}'**
  String gardenNextStage(int count, String stage);

  /// No description provided for @gardenFullBloom.
  ///
  /// In en, this message translates to:
  /// **'Your garden is in full bloom this week! 🌳'**
  String get gardenFullBloom;

  /// No description provided for @gardenGrowsHint.
  ///
  /// In en, this message translates to:
  /// **'Grows every time Mummy & Papa approve your missions this week.'**
  String get gardenGrowsHint;

  /// No description provided for @gardenImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Kavach Panda watering the garden'**
  String get gardenImageLabel;

  /// No description provided for @gardenWeeklyMissions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Mission} other{{count} Missions}}'**
  String gardenWeeklyMissions(int count);

  /// No description provided for @gardenWeeklyBody.
  ///
  /// In en, this message translates to:
  /// **'Approved this week to grow your garden'**
  String get gardenWeeklyBody;

  /// No description provided for @gardenMilestones.
  ///
  /// In en, this message translates to:
  /// **'Decorations & Milestones'**
  String get gardenMilestones;

  /// No description provided for @gardenMilestonesCount.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} Collected'**
  String gardenMilestonesCount(int done, int total);

  /// No description provided for @milestoneRainbow.
  ///
  /// In en, this message translates to:
  /// **'Rainbow Arch'**
  String get milestoneRainbow;

  /// No description provided for @milestoneSunflower.
  ///
  /// In en, this message translates to:
  /// **'Sunflower Patch'**
  String get milestoneSunflower;

  /// No description provided for @milestoneBirdhouse.
  ///
  /// In en, this message translates to:
  /// **'Birdhouse'**
  String get milestoneBirdhouse;

  /// No description provided for @milestoneFountain.
  ///
  /// In en, this message translates to:
  /// **'Fairy Fountain'**
  String get milestoneFountain;

  /// No description provided for @milestoneActive.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get milestoneActive;

  /// No description provided for @milestoneUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get milestoneUnlocked;

  /// No description provided for @milestoneEarned.
  ///
  /// In en, this message translates to:
  /// **'Unlocked by a {days}-day streak'**
  String milestoneEarned(int days);

  /// No description provided for @milestoneLocked.
  ///
  /// In en, this message translates to:
  /// **'Reach a {days}-day streak to unlock'**
  String milestoneLocked(int days);

  /// No description provided for @gardenTipTitle.
  ///
  /// In en, this message translates to:
  /// **'Panda\'s Mindful Tip'**
  String get gardenTipTitle;

  /// No description provided for @gardenTipBody.
  ///
  /// In en, this message translates to:
  /// **'\"Just 30 minutes of outdoor play keeps your mind fresh and happy!\"'**
  String get gardenTipBody;

  /// No description provided for @editMissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit mission'**
  String get editMissionTitle;

  /// No description provided for @createMissionDue.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get createMissionDue;

  /// No description provided for @createMissionDuePick.
  ///
  /// In en, this message translates to:
  /// **'Set due date'**
  String get createMissionDuePick;

  /// No description provided for @createMissionDueClear.
  ///
  /// In en, this message translates to:
  /// **'Clear due date'**
  String get createMissionDueClear;

  /// No description provided for @missionSaved.
  ///
  /// In en, this message translates to:
  /// **'Mission saved'**
  String get missionSaved;

  /// No description provided for @removeMissionButton.
  ///
  /// In en, this message translates to:
  /// **'Remove mission'**
  String get removeMissionButton;

  /// No description provided for @removeMissionConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this mission?'**
  String get removeMissionConfirmTitle;

  /// No description provided for @removeMissionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will disappear for your children. Missions already sent for review stay on record.'**
  String removeMissionConfirmBody(String title);

  /// No description provided for @removeMissionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeMissionConfirm;

  /// No description provided for @removeMissionDone.
  ///
  /// In en, this message translates to:
  /// **'Mission removed'**
  String get removeMissionDone;

  /// No description provided for @parentMissionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit mission {title}'**
  String parentMissionEdit(String title);

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @approvalsPartial.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mission could not be loaded, so its submissions may be missing.} other{{count} missions could not be loaded, so their submissions may be missing.}}'**
  String approvalsPartial(int count);

  /// No description provided for @approvalsUnread.
  ///
  /// In en, this message translates to:
  /// **'Some updates are older than the app can load. Older submissions may not appear.'**
  String get approvalsUnread;

  /// No description provided for @submitAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get submitAddPhoto;

  /// No description provided for @submitTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get submitTakePhoto;

  /// No description provided for @submitChoosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get submitChoosePhoto;

  /// No description provided for @submitRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get submitRemovePhoto;

  /// No description provided for @submitPhotoReady.
  ///
  /// In en, this message translates to:
  /// **'Photo ready to send'**
  String get submitPhotoReady;

  /// No description provided for @submitPhotoPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview of your photo'**
  String get submitPhotoPreview;

  /// No description provided for @submitPhotoHelp.
  ///
  /// In en, this message translates to:
  /// **'A photo helps your parent check your mission. You can also just write a note.'**
  String get submitPhotoHelp;

  /// No description provided for @submitPhotoPickFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open the camera or gallery. Check the app\'s permission in Settings.'**
  String get submitPhotoPickFailed;

  /// No description provided for @submitUploading.
  ///
  /// In en, this message translates to:
  /// **'Sending your photo…'**
  String get submitUploading;

  /// No description provided for @errorPhotoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That photo is too large. Try a smaller one.'**
  String get errorPhotoTooLarge;

  /// No description provided for @errorPhotoUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Please use a JPEG, PNG or WebP photo.'**
  String get errorPhotoUnsupported;

  /// No description provided for @errorPhotoQuota.
  ///
  /// In en, this message translates to:
  /// **'You have photos that were not sent yet. Send a mission first.'**
  String get errorPhotoQuota;

  /// No description provided for @errorPhotoStorage.
  ///
  /// In en, this message translates to:
  /// **'Photos can\'t be saved right now. Try again, or send a note instead.'**
  String get errorPhotoStorage;

  /// No description provided for @errorAlreadyPending.
  ///
  /// In en, this message translates to:
  /// **'This mission is already waiting for your parent to check.'**
  String get errorAlreadyPending;

  /// No description provided for @errorAlreadyCompleted.
  ///
  /// In en, this message translates to:
  /// **'You have already completed this mission. Well done!'**
  String get errorAlreadyCompleted;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your tries'**
  String get historyTitle;

  /// No description provided for @historyAttempt.
  ///
  /// In en, this message translates to:
  /// **'Try {number}'**
  String historyAttempt(int number);

  /// No description provided for @historyParentNote.
  ///
  /// In en, this message translates to:
  /// **'Note from your parent'**
  String get historyParentNote;

  /// No description provided for @statusPendingShort.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get statusPendingShort;

  /// No description provided for @statusApprovedShort.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApprovedShort;

  /// No description provided for @statusRejectedShort.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get statusRejectedShort;

  /// No description provided for @statusResubmitShort.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get statusResubmitShort;

  /// No description provided for @approvalsProofZoom.
  ///
  /// In en, this message translates to:
  /// **'Tap to enlarge'**
  String get approvalsProofZoom;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @rewardsCatalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rewards yet. Ask your parent to add some!'**
  String get rewardsCatalogEmpty;

  /// No description provided for @rewardsAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask for this'**
  String get rewardsAsk;

  /// No description provided for @rewardsNeedMore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 more star to go} other{{count} more stars to go}}'**
  String rewardsNeedMore(int count);

  /// No description provided for @rewardsAlreadyAsked.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your parent'**
  String get rewardsAlreadyAsked;

  /// No description provided for @rewardsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for {name}?'**
  String rewardsConfirmTitle(String name);

  /// No description provided for @rewardsConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This uses {count} stars if your parent says yes. Nothing is taken until then.'**
  String rewardsConfirmBody(int count);

  /// No description provided for @rewardsConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, ask'**
  String get rewardsConfirmYes;

  /// No description provided for @rewardsAsked.
  ///
  /// In en, this message translates to:
  /// **'Request sent to your parent!'**
  String get rewardsAsked;

  /// No description provided for @rewardsCancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get rewardsCancelRequest;

  /// No description provided for @rewardsRequestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get rewardsRequestCancelled;

  /// No description provided for @rewardsParentNote.
  ///
  /// In en, this message translates to:
  /// **'Parent\'s note: {note}'**
  String rewardsParentNote(String note);

  /// No description provided for @rewardsRequestNamed.
  ///
  /// In en, this message translates to:
  /// **'Request for {name}'**
  String rewardsRequestNamed(String name);

  /// No description provided for @errorNotEnoughStars.
  ///
  /// In en, this message translates to:
  /// **'There aren\'t enough stars for this.'**
  String get errorNotEnoughStars;

  /// No description provided for @errorRewardPending.
  ///
  /// In en, this message translates to:
  /// **'That reward was already asked for.'**
  String get errorRewardPending;

  /// No description provided for @errorRewardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'That reward isn\'t available any more.'**
  String get errorRewardUnavailable;

  /// No description provided for @parentRewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get parentRewardsTitle;

  /// No description provided for @parentRewardsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose rewards and answer requests'**
  String get parentRewardsSubtitle;

  /// No description provided for @parentRewardsRequestsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No requests waiting} =1{1 request waiting} other{{count} requests waiting}}'**
  String parentRewardsRequestsCount(int count);

  /// No description provided for @rewardsTabCatalog.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get rewardsTabCatalog;

  /// No description provided for @rewardsTabRequests.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get rewardsTabRequests;

  /// No description provided for @rewardsRequestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No requests waiting.'**
  String get rewardsRequestsEmpty;

  /// No description provided for @rewardsAddReward.
  ///
  /// In en, this message translates to:
  /// **'Add reward'**
  String get rewardsAddReward;

  /// No description provided for @rewardsEditReward.
  ///
  /// In en, this message translates to:
  /// **'Edit reward'**
  String get rewardsEditReward;

  /// No description provided for @rewardsFormName.
  ///
  /// In en, this message translates to:
  /// **'Reward name'**
  String get rewardsFormName;

  /// No description provided for @rewardsFormDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get rewardsFormDescription;

  /// No description provided for @rewardsFormCost.
  ///
  /// In en, this message translates to:
  /// **'Star cost'**
  String get rewardsFormCost;

  /// No description provided for @rewardsFormType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get rewardsFormType;

  /// No description provided for @rewardTypeCustom.
  ///
  /// In en, this message translates to:
  /// **'Something special'**
  String get rewardTypeCustom;

  /// No description provided for @rewardTypeGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get rewardTypeGift;

  /// No description provided for @rewardTypeBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get rewardTypeBook;

  /// No description provided for @rewardTypeOutdoor.
  ///
  /// In en, this message translates to:
  /// **'Outdoor activity'**
  String get rewardTypeOutdoor;

  /// No description provided for @rewardTypeScreenTime.
  ///
  /// In en, this message translates to:
  /// **'Screen time'**
  String get rewardTypeScreenTime;

  /// No description provided for @rewardsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove reward'**
  String get rewardsRemove;

  /// No description provided for @rewardsRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}? Children will no longer see it.'**
  String rewardsRemoveConfirm(String name);

  /// No description provided for @rewardsSaved.
  ///
  /// In en, this message translates to:
  /// **'Reward saved'**
  String get rewardsSaved;

  /// No description provided for @rewardsRemoved.
  ///
  /// In en, this message translates to:
  /// **'Reward removed'**
  String get rewardsRemoved;

  /// No description provided for @rewardsAskedBy.
  ///
  /// In en, this message translates to:
  /// **'{child} asked for {reward}'**
  String rewardsAskedBy(String child, String reward);

  /// No description provided for @rewardsApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve ({count} stars)'**
  String rewardsApprove(int count);

  /// No description provided for @rewardsDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get rewardsDecline;

  /// No description provided for @rewardsMarkGiven.
  ///
  /// In en, this message translates to:
  /// **'Mark as given'**
  String get rewardsMarkGiven;

  /// No description provided for @rewardsCancelRefund.
  ///
  /// In en, this message translates to:
  /// **'Cancel and return stars'**
  String get rewardsCancelRefund;

  /// No description provided for @rewardsApprovedToast.
  ///
  /// In en, this message translates to:
  /// **'Approved. {count} stars were taken.'**
  String rewardsApprovedToast(int count);

  /// No description provided for @rewardsDeclinedToast.
  ///
  /// In en, this message translates to:
  /// **'Request declined'**
  String get rewardsDeclinedToast;

  /// No description provided for @rewardsGivenToast.
  ///
  /// In en, this message translates to:
  /// **'Marked as given'**
  String get rewardsGivenToast;

  /// No description provided for @rewardsRefundedToast.
  ///
  /// In en, this message translates to:
  /// **'Cancelled and stars returned'**
  String get rewardsRefundedToast;

  /// No description provided for @rewardsAlreadyReviewed.
  ///
  /// In en, this message translates to:
  /// **'This request was already handled.'**
  String get rewardsAlreadyReviewed;

  /// No description provided for @rewardsNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note for your child (optional)'**
  String get rewardsNoteOptional;

  /// No description provided for @rewardsDeclineTitle.
  ///
  /// In en, this message translates to:
  /// **'Decline this request?'**
  String get rewardsDeclineTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @reportsPreviousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get reportsPreviousWeek;

  /// No description provided for @reportsNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get reportsNextWeek;

  /// No description provided for @reportsThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get reportsThisWeek;

  /// No description provided for @reportsCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'By activity'**
  String get reportsCategoriesTitle;

  /// No description provided for @reportsCategoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No approved missions this week yet.'**
  String get reportsCategoriesEmpty;

  /// No description provided for @reportsCategoryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mission} other{{count} missions}}'**
  String reportsCategoryCount(int count);

  /// No description provided for @reportsUncategorised.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportsUncategorised;

  /// No description provided for @reportsPendingNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mission waiting for your review} other{{count} missions waiting for your review}}'**
  String reportsPendingNote(int count);

  /// No description provided for @reportsRetryNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 mission needs another try} other{{count} missions need another try}}'**
  String reportsRetryNote(int count);

  /// No description provided for @reportsTimezoneNote.
  ///
  /// In en, this message translates to:
  /// **'Days follow {zone} time.'**
  String reportsTimezoneNote(String zone);

  /// No description provided for @reportsShare.
  ///
  /// In en, this message translates to:
  /// **'Share progress'**
  String get reportsShare;

  /// No description provided for @reportsShareSubject.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s weekly progress'**
  String reportsShareSubject(String name);

  /// No description provided for @reportsShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open sharing. Try Copy instead.'**
  String get reportsShareFailed;

  /// No description provided for @maintenanceDefault.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach is being updated. Some things may not work for a while.'**
  String get maintenanceDefault;

  /// No description provided for @settingsTimezone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get settingsTimezone;

  /// No description provided for @settingsTimezoneBody.
  ///
  /// In en, this message translates to:
  /// **'Decides which day a mission counts for in reports and streaks. Saved to your family.'**
  String get settingsTimezoneBody;

  /// No description provided for @settingsTimezoneUseDevice.
  ///
  /// In en, this message translates to:
  /// **'Use this phone\'s time zone ({zone})'**
  String settingsTimezoneUseDevice(String zone);

  /// No description provided for @settingsTimezoneSaved.
  ///
  /// In en, this message translates to:
  /// **'Time zone saved'**
  String get settingsTimezoneSaved;

  /// No description provided for @settingsSavedWhereTitle.
  ///
  /// In en, this message translates to:
  /// **'What is saved where'**
  String get settingsSavedWhereTitle;

  /// No description provided for @settingsSavedAccount.
  ///
  /// In en, this message translates to:
  /// **'Saved to your account: language, push choice, family time zone, consent.'**
  String get settingsSavedAccount;

  /// No description provided for @settingsSavedDevice.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone only: each child\'s avatar picture.'**
  String get settingsSavedDevice;

  /// No description provided for @settingsPrivacySafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & safety'**
  String get settingsPrivacySafetyTitle;

  /// No description provided for @safetyPointFamilyOnly.
  ///
  /// In en, this message translates to:
  /// **'Missions, photos and progress can only be seen by your family\'s parents and by the child they belong to.'**
  String get safetyPointFamilyOnly;

  /// No description provided for @safetyPointPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos are checked, resized and stripped of location details before they are saved.'**
  String get safetyPointPhotos;

  /// No description provided for @safetyPointChildMode.
  ///
  /// In en, this message translates to:
  /// **'Child mode never has your email or password and cannot open parent screens.'**
  String get safetyPointChildMode;

  /// No description provided for @safetyPointApprovals.
  ///
  /// In en, this message translates to:
  /// **'Stars, XP and rewards only change after a parent decides.'**
  String get safetyPointApprovals;

  /// No description provided for @safetyPointNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications never show your child\'s name or mission details.'**
  String get safetyPointNotifications;

  /// No description provided for @safetyPointNoAds.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach shows no ads.'**
  String get safetyPointNoAds;

  /// No description provided for @childSignOutDevices.
  ///
  /// In en, this message translates to:
  /// **'Sign out on all devices'**
  String get childSignOutDevices;

  /// No description provided for @childSignOutDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'Ends {name}\'s sign-in everywhere, for example on a lost tablet.'**
  String childSignOutDevicesBody(String name);

  /// No description provided for @childSignOutDevicesDone.
  ///
  /// In en, this message translates to:
  /// **'Signed out on all devices'**
  String get childSignOutDevicesDone;

  /// No description provided for @childSignOutDevicesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get childSignOutDevicesConfirm;

  /// No description provided for @navLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get navLearn;

  /// No description provided for @learnTitle.
  ///
  /// In en, this message translates to:
  /// **'Learn & Watch'**
  String get learnTitle;

  /// No description provided for @learnAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get learnAll;

  /// No description provided for @learnEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to learn here yet. Check back soon!'**
  String get learnEmpty;

  /// No description provided for @learnOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get learnOpen;

  /// No description provided for @learnOpensOutside.
  ///
  /// In en, this message translates to:
  /// **'Opens in your browser or the video app.'**
  String get learnOpensOutside;

  /// No description provided for @learnOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open that link.'**
  String get learnOpenFailed;

  /// No description provided for @learnLocked.
  ///
  /// In en, this message translates to:
  /// **'Ask your parent to unlock this with a reward.'**
  String get learnLocked;

  /// No description provided for @learnNotReady.
  ///
  /// In en, this message translates to:
  /// **'This one isn\'t ready to play yet.'**
  String get learnNotReady;

  /// No description provided for @learnTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get learnTypeVideo;

  /// No description provided for @learnTypeArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get learnTypeArticle;

  /// No description provided for @learnTypeLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get learnTypeLink;

  /// No description provided for @learnTypeDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get learnTypeDocument;

  /// No description provided for @learnTypeActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get learnTypeActivity;

  /// No description provided for @learnCategoryLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get learnCategoryLearning;

  /// No description provided for @learnCategoryStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get learnCategoryStories;

  /// No description provided for @learnCategoryScience.
  ///
  /// In en, this message translates to:
  /// **'Science'**
  String get learnCategoryScience;

  /// No description provided for @learnCategoryCreativity.
  ///
  /// In en, this message translates to:
  /// **'Creativity'**
  String get learnCategoryCreativity;

  /// No description provided for @learnCategoryHealthyHabits.
  ///
  /// In en, this message translates to:
  /// **'Healthy Habits'**
  String get learnCategoryHealthyHabits;

  /// No description provided for @learnMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get learnMore;

  /// No description provided for @gardenCollection.
  ///
  /// In en, this message translates to:
  /// **'Garden collection'**
  String get gardenCollection;

  /// No description provided for @gardenCollectionCount.
  ///
  /// In en, this message translates to:
  /// **'{unlocked} of {total} unlocked'**
  String gardenCollectionCount(int unlocked, int total);

  /// No description provided for @gardenServerStage.
  ///
  /// In en, this message translates to:
  /// **'Garden size: {name}'**
  String gardenServerStage(String name);

  /// No description provided for @gardenXpToNext.
  ///
  /// In en, this message translates to:
  /// **'{count} XP until it grows again'**
  String gardenXpToNext(int count);

  /// No description provided for @gardenStageYoungTree.
  ///
  /// In en, this message translates to:
  /// **'Young tree'**
  String get gardenStageYoungTree;

  /// No description provided for @gardenStageBlossom.
  ///
  /// In en, this message translates to:
  /// **'In blossom'**
  String get gardenStageBlossom;

  /// No description provided for @gardenStageOrchard.
  ///
  /// In en, this message translates to:
  /// **'Orchard'**
  String get gardenStageOrchard;

  /// No description provided for @gardenItemFirstMission.
  ///
  /// In en, this message translates to:
  /// **'Little fence'**
  String get gardenItemFirstMission;

  /// No description provided for @gardenItemMissionMaster.
  ///
  /// In en, this message translates to:
  /// **'Garden gate'**
  String get gardenItemMissionMaster;

  /// No description provided for @gardenItemStarCollector.
  ///
  /// In en, this message translates to:
  /// **'Star lantern'**
  String get gardenItemStarCollector;

  /// No description provided for @gardenItemXpClimber.
  ///
  /// In en, this message translates to:
  /// **'Flower bed'**
  String get gardenItemXpClimber;

  /// No description provided for @gardenItemThreeDayStreak.
  ///
  /// In en, this message translates to:
  /// **'Rainbow'**
  String get gardenItemThreeDayStreak;

  /// No description provided for @gardenItemWeekWarrior.
  ///
  /// In en, this message translates to:
  /// **'Fountain'**
  String get gardenItemWeekWarrior;

  /// No description provided for @gardenItemLocked.
  ///
  /// In en, this message translates to:
  /// **'Earn the “{badge}” badge to unlock'**
  String gardenItemLocked(String badge);

  /// No description provided for @gardenItemUnknown.
  ///
  /// In en, this message translates to:
  /// **'Garden surprise'**
  String get gardenItemUnknown;

  /// No description provided for @createMissionIdeas.
  ///
  /// In en, this message translates to:
  /// **'Choose from ideas'**
  String get createMissionIdeas;

  /// No description provided for @createMissionIdeasTitle.
  ///
  /// In en, this message translates to:
  /// **'Mission ideas'**
  String get createMissionIdeasTitle;

  /// No description provided for @createMissionIdeasEmpty.
  ///
  /// In en, this message translates to:
  /// **'No ideas available right now.'**
  String get createMissionIdeasEmpty;

  /// No description provided for @createMissionIdeasHint.
  ///
  /// In en, this message translates to:
  /// **'You can change anything before saving.'**
  String get createMissionIdeasHint;
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
