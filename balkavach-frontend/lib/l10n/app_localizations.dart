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
  /// **'BALKAVACH'**
  String get appTitle;

  /// No description provided for @brandEyebrow.
  ///
  /// In en, this message translates to:
  /// **'KIDS DIGITAL GUARDIAN'**
  String get brandEyebrow;

  /// No description provided for @brandName.
  ///
  /// In en, this message translates to:
  /// **'BALKAVACH'**
  String get brandName;

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
  /// **'Can\'t reach BALKAVACH. Check your internet connection.'**
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
  /// **'Panda'**
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
  /// **'BALKAVACH ECOSYSTEM'**
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
  /// **'Who is using BALKAVACH?'**
  String get roleTitle;

  /// No description provided for @roleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Parents manage the family. Children sign in with their own credentials.'**
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
  /// **'Sign in with the username and password your parent created.'**
  String get roleChildBody;

  /// No description provided for @childLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Login'**
  String get childLoginTitle;

  /// No description provided for @childLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the username and password your parent created for you.'**
  String get childLoginSubtitle;

  /// No description provided for @childLoginButton.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get childLoginButton;

  /// No description provided for @childLoginInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Username or password is incorrect.'**
  String get childLoginInvalidCredentials;

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

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get authForgotPassword;

  /// No description provided for @authResetSent.
  ///
  /// In en, this message translates to:
  /// **'If an account exists, a reset link has been sent.'**
  String get authResetSent;

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

  /// No description provided for @createChildCredentialsConfigMissing.
  ///
  /// In en, this message translates to:
  /// **'Credential retrieval is not configured on the server. Please contact your parent.'**
  String get createChildCredentialsConfigMissing;

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
  /// **'My Missions'**
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
  /// **'Panda says:'**
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

  /// No description provided for @missionGuideLearn.
  ///
  /// In en, this message translates to:
  /// **'What you will learn'**
  String get missionGuideLearn;

  /// No description provided for @missionGuideNeed.
  ///
  /// In en, this message translates to:
  /// **'What you need'**
  String get missionGuideNeed;

  /// No description provided for @missionGuideTime.
  ///
  /// In en, this message translates to:
  /// **'Time needed'**
  String get missionGuideTime;

  /// No description provided for @missionGuideTimeValue.
  ///
  /// In en, this message translates to:
  /// **'About {minutes} minutes'**
  String missionGuideTimeValue(int minutes);

  /// No description provided for @missionGuideSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get missionGuideSteps;

  /// No description provided for @missionGuideObserve.
  ///
  /// In en, this message translates to:
  /// **'What to observe'**
  String get missionGuideObserve;

  /// No description provided for @missionGuideSubmit.
  ///
  /// In en, this message translates to:
  /// **'What to submit'**
  String get missionGuideSubmit;

  /// No description provided for @missionGuideSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get missionGuideSafety;

  /// No description provided for @missionGuideIncompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'These instructions are not ready yet'**
  String get missionGuideIncompleteTitle;

  /// No description provided for @missionGuideIncompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Ask a trusted grown-up to look at this mission with you, or choose a different mission.'**
  String get missionGuideIncompleteBody;

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
  /// **'Panda'**
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
  /// **'Checking the BALKAVACH server…'**
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

  /// No description provided for @approvalsVideoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min video'**
  String approvalsVideoMinutes(int minutes);

  /// No description provided for @approvalsApprovedToastFull.
  ///
  /// In en, this message translates to:
  /// **'Approved! {name} earned {stars} stars, {xp} XP and {minutes} minutes of video time.'**
  String approvalsApprovedToastFull(
    String name,
    int stars,
    int xp,
    int minutes,
  );

  /// No description provided for @errorApprovalFailed.
  ///
  /// In en, this message translates to:
  /// **'The approval could not be saved. Nothing was awarded. Please try again.'**
  String get errorApprovalFailed;

  /// No description provided for @errorVideoAllowanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video time can\'t be granted right now, so this mission wasn\'t approved. Nothing was awarded. Please try again later.'**
  String get errorVideoAllowanceUnavailable;

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
  /// **'🌟 *BALKAVACH Weekly Progress Report* 🌟\n👤 *Child:* {name}\n📅 *Period:* {range}\n\n━━━━━━━━━━━━━━━━━━━━━\n✅ *Achievements This Week:*\n• {missions} missions approved\n• {stars} stars and {xp} XP earned\n• {streak}-day streak maintained!\n━━━━━━━━━━━━━━━━━━━━━\n\n🛡️ Safe childhood, smart digital future with BALKAVACH.'**
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
  /// **'{name} will no longer be able to use child mode, and the profile disappears from your family. BALKAVACH keeps the mission and star records on the server.'**
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
  /// **'BALKAVACH doesn\'t send emails yet.'**
  String get settingsEmailBody;

  /// No description provided for @settingsPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Consent'**
  String get settingsPrivacyTitle;

  /// No description provided for @settingsPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Consent you gave for your family, as stored by BALKAVACH.'**
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
  /// **'BALKAVACH • Made for Indian families'**
  String get settingsFooter;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Child Rewards'**
  String get rewardsTitle;

  /// No description provided for @rewardsVault.
  ///
  /// In en, this message translates to:
  /// **'BALKAVACH Vault'**
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
  /// **'Panda watering the garden'**
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

  /// No description provided for @missionStars.
  ///
  /// In en, this message translates to:
  /// **'Star reward'**
  String get missionStars;

  /// No description provided for @missionXp.
  ///
  /// In en, this message translates to:
  /// **'XP reward'**
  String get missionXp;

  /// No description provided for @missionRequireVideo.
  ///
  /// In en, this message translates to:
  /// **'Require verified video watching'**
  String get missionRequireVideo;

  /// No description provided for @missionRequiredVideoMinutes.
  ///
  /// In en, this message translates to:
  /// **'Required watched minutes'**
  String get missionRequiredVideoMinutes;

  /// No description provided for @missionAmountValidation.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {minimum} to {maximum}.'**
  String missionAmountValidation(int minimum, int maximum);

  /// No description provided for @missionVideoHeader.
  ///
  /// In en, this message translates to:
  /// **'Mission video'**
  String get missionVideoHeader;

  /// No description provided for @missionVideoProgress.
  ///
  /// In en, this message translates to:
  /// **'Verified {watched} of {required} minutes'**
  String missionVideoProgress(int watched, int required);

  /// No description provided for @missionVideoComplete.
  ///
  /// In en, this message translates to:
  /// **'Video requirement complete'**
  String get missionVideoComplete;

  /// No description provided for @missionVideoIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Watch the required time before submitting.'**
  String get missionVideoIncomplete;

  /// No description provided for @missionVideoInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Playback stopped. Your verified progress was saved.'**
  String get missionVideoInterrupted;

  /// No description provided for @missionVideoChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a video'**
  String get missionVideoChoose;

  /// No description provided for @missionVideoNoVideos.
  ///
  /// In en, this message translates to:
  /// **'No eligible videos are available right now.'**
  String get missionVideoNoVideos;

  /// No description provided for @missionVideoLoadError.
  ///
  /// In en, this message translates to:
  /// **'Mission video progress could not be loaded.'**
  String get missionVideoLoadError;

  /// No description provided for @approvalVideoProgress.
  ///
  /// In en, this message translates to:
  /// **'Video requirement: {required} min required, {watched} min verified'**
  String approvalVideoProgress(int required, int watched);

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

  /// No description provided for @rewardsShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get rewardsShareAction;

  /// No description provided for @rewardsShareSubject.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s BALKAVACH Achievement Report ⭐'**
  String rewardsShareSubject(String name);

  /// No description provided for @rewardsShareText.
  ///
  /// In en, this message translates to:
  /// **'🌟 *{name} is thriving on BALKAVACH!*\n\n━━━━━━━━━━━━━━━━━━━━━\n⭐  *Star Balance:*  {stars} stars\n🔥  *Current Streak:*  {streak} days in a row!\n🏆  *Badges Earned:*  {badges} achievements unlocked\n━━━━━━━━━━━━━━━━━━━━━\n\n{name} is learning, growing and earning rewards on BALKAVACH — the safe, ad-free kids learning app! 📚✨'**
  String rewardsShareText(String name, int stars, int streak, int badges);

  /// No description provided for @rewardsShareBadgeText.
  ///
  /// In en, this message translates to:
  /// **'🏆 *Achievement Unlocked on BALKAVACH!*\n\n🎖️  *\"{badge}\"*\n\nI earned this badge on BALKAVACH — the safe, ad-free kids learning app! 📚⭐'**
  String rewardsShareBadgeText(String badge);

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
  /// **'BALKAVACH is being updated. Some things may not work for a while.'**
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
  /// **'BALKAVACH shows no ads.'**
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

  /// No description provided for @validationFieldInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please check this field and try again.'**
  String get validationFieldInvalid;

  /// No description provided for @errorUsernameTaken.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken.'**
  String get errorUsernameTaken;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @watchTitle.
  ///
  /// In en, this message translates to:
  /// **'Watch & Learn'**
  String get watchTitle;

  /// No description provided for @navWatch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get navWatch;

  /// No description provided for @watchSessionFirst.
  ///
  /// In en, this message translates to:
  /// **'Warm-up watch'**
  String get watchSessionFirst;

  /// No description provided for @watchSessionSecond.
  ///
  /// In en, this message translates to:
  /// **'Bonus watch'**
  String get watchSessionSecond;

  /// No description provided for @watchUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Videos aren\'t ready yet'**
  String get watchUnavailableTitle;

  /// No description provided for @watchUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Your grown-ups are still setting up videos. Your missions are open in the meantime!'**
  String get watchUnavailableBody;

  /// No description provided for @watchDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Videos are switched off'**
  String get watchDisabledTitle;

  /// No description provided for @watchDisabledBody.
  ///
  /// In en, this message translates to:
  /// **'A parent turned off videos for now. You can still do your missions.'**
  String get watchDisabledBody;

  /// No description provided for @watchMissionsOpen.
  ///
  /// In en, this message translates to:
  /// **'Go to missions'**
  String get watchMissionsOpen;

  /// No description provided for @watchBrowseLearn.
  ///
  /// In en, this message translates to:
  /// **'Browse learning'**
  String get watchBrowseLearn;

  /// No description provided for @watchGateMissionsLocked.
  ///
  /// In en, this message translates to:
  /// **'Watch {minutes} min to unlock today\'s missions'**
  String watchGateMissionsLocked(int minutes);

  /// No description provided for @watchGateMissionsUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Missions unlocked. Nice work!'**
  String get watchGateMissionsUnlocked;

  /// No description provided for @watchGateAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Your grown-up is checking your missions'**
  String get watchGateAwaitingApproval;

  /// No description provided for @watchGateSecondLocked.
  ///
  /// In en, this message translates to:
  /// **'Finish today\'s missions to unlock bonus videos'**
  String get watchGateSecondLocked;

  /// No description provided for @watchGateSecondUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Bonus videos unlocked!'**
  String get watchGateSecondUnlocked;

  /// No description provided for @watchGateComplete.
  ///
  /// In en, this message translates to:
  /// **'All done for today. Amazing!'**
  String get watchGateComplete;

  /// No description provided for @watchMinutesLeft.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min to go'**
  String watchMinutesLeft(int minutes);

  /// No description provided for @watchTimeToday.
  ///
  /// In en, this message translates to:
  /// **'{watched} of {total} min watched today'**
  String watchTimeToday(int watched, int total);

  /// No description provided for @watchNoVideos.
  ///
  /// In en, this message translates to:
  /// **'No videos here yet. Check back soon!'**
  String get watchNoVideos;

  /// No description provided for @learnOpenLearn.
  ///
  /// In en, this message translates to:
  /// **'Open Learn & Watch'**
  String get learnOpenLearn;

  /// No description provided for @profileLanguageHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes the app language on this phone.'**
  String get profileLanguageHelp;

  /// No description provided for @videoPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get videoPlay;

  /// No description provided for @videoPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get videoPause;

  /// No description provided for @videoRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get videoRetry;

  /// No description provided for @videoPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t play this video.'**
  String get videoPlaybackFailed;

  /// No description provided for @videoProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Video progress'**
  String get videoProgressLabel;

  /// No description provided for @videoWatchInApp.
  ///
  /// In en, this message translates to:
  /// **'Watch now'**
  String get videoWatchInApp;

  /// No description provided for @videoNotPlayableInApp.
  ///
  /// In en, this message translates to:
  /// **'This one opens outside the app.'**
  String get videoNotPlayableInApp;

  /// No description provided for @videoFeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get videoFeedTitle;

  /// No description provided for @videoFeedOpen.
  ///
  /// In en, this message translates to:
  /// **'More videos'**
  String get videoFeedOpen;

  /// No description provided for @videoFeedLearnTab.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get videoFeedLearnTab;

  /// No description provided for @videoFeedShortsTab.
  ///
  /// In en, this message translates to:
  /// **'Shorts'**
  String get videoFeedShortsTab;

  /// No description provided for @videoFeedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No videos here yet. New videos appear after our team checks they are right for kids.'**
  String get videoFeedEmpty;

  /// No description provided for @videoFeedAdsNotice.
  ///
  /// In en, this message translates to:
  /// **'Videos from YouTube play in YouTube\'s own player and may show ads.'**
  String get videoFeedAdsNotice;

  /// No description provided for @youtubeLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave BALKAVACH?'**
  String get youtubeLeaveTitle;

  /// No description provided for @youtubeLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'This opens YouTube outside the app. Ask a grown-up before you continue.'**
  String get youtubeLeaveBody;

  /// No description provided for @youtubeLeaveOpen.
  ///
  /// In en, this message translates to:
  /// **'Open YouTube'**
  String get youtubeLeaveOpen;

  /// No description provided for @youtubeLeaveStay.
  ///
  /// In en, this message translates to:
  /// **'Stay here'**
  String get youtubeLeaveStay;

  /// No description provided for @youtubeLeaveBlocked.
  ///
  /// In en, this message translates to:
  /// **'Videos play only inside BALKAVACH, so this link stays closed.'**
  String get youtubeLeaveBlocked;

  /// No description provided for @videoShareBlocked.
  ///
  /// In en, this message translates to:
  /// **'Sharing videos is turned off for children.'**
  String get videoShareBlocked;

  /// No description provided for @youtubeOtherVideoBlocked.
  ///
  /// In en, this message translates to:
  /// **'That video isn\'t in BALKAVACH, so it can\'t play here.'**
  String get youtubeOtherVideoBlocked;

  /// No description provided for @youtubePlayerError.
  ///
  /// In en, this message translates to:
  /// **'This video can\'t play right now.'**
  String get youtubePlayerError;

  /// No description provided for @videoReport.
  ///
  /// In en, this message translates to:
  /// **'Report this video'**
  String get videoReport;

  /// No description provided for @videoReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report this video'**
  String get videoReportTitle;

  /// No description provided for @videoReportBody.
  ///
  /// In en, this message translates to:
  /// **'For grown-ups: tell us what\'s wrong. The video is hidden while our team checks it.'**
  String get videoReportBody;

  /// No description provided for @videoReportDetails.
  ///
  /// In en, this message translates to:
  /// **'Anything else? (optional)'**
  String get videoReportDetails;

  /// No description provided for @videoReportSend.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get videoReportSend;

  /// No description provided for @videoReportCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get videoReportCancel;

  /// No description provided for @videoReportSent.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Our team will review this video.'**
  String get videoReportSent;

  /// No description provided for @videoReportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send the report. Please try again.'**
  String get videoReportFailed;

  /// No description provided for @videoReportReasonInappropriate.
  ///
  /// In en, this message translates to:
  /// **'Not suitable for children'**
  String get videoReportReasonInappropriate;

  /// No description provided for @videoReportReasonScary.
  ///
  /// In en, this message translates to:
  /// **'Scary'**
  String get videoReportReasonScary;

  /// No description provided for @videoReportReasonViolent.
  ///
  /// In en, this message translates to:
  /// **'Violent'**
  String get videoReportReasonViolent;

  /// No description provided for @videoReportReasonMisleading.
  ///
  /// In en, this message translates to:
  /// **'Misleading'**
  String get videoReportReasonMisleading;

  /// No description provided for @videoReportReasonAdvertising.
  ///
  /// In en, this message translates to:
  /// **'Ads or selling'**
  String get videoReportReasonAdvertising;

  /// No description provided for @videoReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get videoReportReasonOther;

  /// Title of the full-screen vertical Shorts feed.
  ///
  /// In en, this message translates to:
  /// **'Shorts'**
  String get shortsTitle;

  /// Opens the full Shorts feed from Home.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get shortsSeeAll;

  /// Hint under the first Short.
  ///
  /// In en, this message translates to:
  /// **'Swipe up for the next video'**
  String get shortsSwipeHint;

  /// Shown after the last Short.
  ///
  /// In en, this message translates to:
  /// **'You\'ve seen all the shorts for now!'**
  String get shortsEnd;

  /// Back button tooltip on video screens.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get videoBack;

  /// Turns the video's sound off.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get videoMute;

  /// Turns the video's sound back on.
  ///
  /// In en, this message translates to:
  /// **'Turn sound on'**
  String get videoUnmute;

  /// Share button on a video.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get videoShare;

  /// Grown-up check before the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Share this video?'**
  String get videoShareTitle;

  /// Grown-up check body.
  ///
  /// In en, this message translates to:
  /// **'Sharing opens another app. Ask a grown-up first.'**
  String get videoShareBody;

  /// Cancels sharing.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get videoShareCancel;

  /// The share sheet could not open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open sharing.'**
  String get videoShareFailed;

  /// Hosted videos need an approved reward; they are not played from a list.
  ///
  /// In en, this message translates to:
  /// **'This video unlocks with a reward from your grown-up.'**
  String get videoNeedsGrownUp;

  /// YouTube refused to embed this video.
  ///
  /// In en, this message translates to:
  /// **'This video can\'t play inside BALKAVACH. Try another one!'**
  String get videoNotEmbeddable;

  /// Video is buffering.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get videoLoading;

  /// Related videos heading.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get videoUpNext;

  /// Plays the next related video.
  ///
  /// In en, this message translates to:
  /// **'Next video'**
  String get videoPlayNext;

  /// Enters full screen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get videoFullscreen;

  /// Leaves full screen.
  ///
  /// In en, this message translates to:
  /// **'Exit full screen'**
  String get videoExitFullscreen;

  /// Badge on a Short video card.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get videoBadgeShort;

  /// Badge on a video from YouTube.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get videoBadgeYouTube;

  /// Watch & Learn home heading.
  ///
  /// In en, this message translates to:
  /// **'What shall we watch today?'**
  String get watchGreeting;

  /// Watch & Learn home subheading.
  ///
  /// In en, this message translates to:
  /// **'Every video here was checked to be right for kids.'**
  String get watchGreetingBody;

  /// Shorts row heading on Home.
  ///
  /// In en, this message translates to:
  /// **'Quick videos'**
  String get watchShortsSection;

  /// Section title for unfinished long videos.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get watchContinue;

  /// No description provided for @parentWatchHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Video history'**
  String get parentWatchHistoryTitle;

  /// No description provided for @parentWatchHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review watched videos and allow replay'**
  String get parentWatchHistorySubtitle;

  /// No description provided for @parentWatchHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No video history yet.'**
  String get parentWatchHistoryEmpty;

  /// No description provided for @videoAllowReplay.
  ///
  /// In en, this message translates to:
  /// **'Allow replay'**
  String get videoAllowReplay;

  /// No description provided for @videoReplayEnabled.
  ///
  /// In en, this message translates to:
  /// **'Replay allowed'**
  String get videoReplayEnabled;

  /// No description provided for @videoWatchProgress.
  ///
  /// In en, this message translates to:
  /// **'Video watch progress'**
  String get videoWatchProgress;

  /// Category chips heading on Home.
  ///
  /// In en, this message translates to:
  /// **'Explore topics'**
  String get watchTopicsSection;

  /// Regular videos heading on Home.
  ///
  /// In en, this message translates to:
  /// **'Videos to learn from'**
  String get watchVideosSection;

  /// Curated Learn & Watch videos heading on Home.
  ///
  /// In en, this message translates to:
  /// **'Picked by grown-ups'**
  String get watchPickedSection;

  /// Home empty state when no section has content.
  ///
  /// In en, this message translates to:
  /// **'No videos here right now. Check back soon, or try a mission!'**
  String get watchNothingYet;

  /// Expands a Short's description.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get shortsMore;

  /// Collapses a Short's description.
  ///
  /// In en, this message translates to:
  /// **'less'**
  String get shortsLess;

  /// Short label under the mute button in Shorts.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get shortsActionSound;

  /// Short label under the report button in Shorts.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get shortsActionReport;

  /// No description provided for @streakTitle.
  ///
  /// In en, this message translates to:
  /// **'My Streak'**
  String get streakTitle;

  /// No description provided for @streakActive.
  ///
  /// In en, this message translates to:
  /// **'Active Streak'**
  String get streakActive;

  /// No description provided for @streakAtRisk.
  ///
  /// In en, this message translates to:
  /// **'Streak at Risk'**
  String get streakAtRisk;

  /// No description provided for @streakBroken.
  ///
  /// In en, this message translates to:
  /// **'Streak Broken'**
  String get streakBroken;

  /// No description provided for @streakRecovered.
  ///
  /// In en, this message translates to:
  /// **'Streak Recovered!'**
  String get streakRecovered;

  /// No description provided for @streakDaysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}} {hours, plural, =1{1 hour} other{{hours} hours}} remaining'**
  String streakDaysRemaining(int days, int hours);

  /// No description provided for @streakHoursRemaining.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour} other{{hours} hours}} remaining'**
  String streakHoursRemaining(int hours);

  /// No description provided for @streakComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete a mission to keep your streak going!'**
  String get streakComplete;

  /// No description provided for @streakLongest.
  ///
  /// In en, this message translates to:
  /// **'Longest: {count} days'**
  String streakLongest(int count);

  /// No description provided for @streakStartNew.
  ///
  /// In en, this message translates to:
  /// **'Complete a mission to start your streak!'**
  String get streakStartNew;

  /// No description provided for @streakNoActivity.
  ///
  /// In en, this message translates to:
  /// **'No activity recorded yet'**
  String get streakNoActivity;

  /// No description provided for @videoAllowanceRemaining.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m video time left today'**
  String videoAllowanceRemaining(int minutes);

  /// No description provided for @videoAllowanceLocked.
  ///
  /// In en, this message translates to:
  /// **'Video time locked'**
  String get videoAllowanceLocked;

  /// No description provided for @videoAllowanceUnlockHint.
  ///
  /// In en, this message translates to:
  /// **'Your free time is used. Ask a grown-up about more.'**
  String get videoAllowanceUnlockHint;

  /// No description provided for @videoFreeRemaining.
  ///
  /// In en, this message translates to:
  /// **'Daily free video: {remaining} of {total} minutes left'**
  String videoFreeRemaining(int remaining, int total);

  /// No description provided for @videoMissionRemaining.
  ///
  /// In en, this message translates to:
  /// **'Mission video: {minutes} extra minutes'**
  String videoMissionRemaining(int minutes);

  /// No description provided for @videoTimeExhaustedTitle.
  ///
  /// In en, this message translates to:
  /// **'Video time is done for today'**
  String get videoTimeExhaustedTitle;

  /// No description provided for @videoTimeExhaustedBody.
  ///
  /// In en, this message translates to:
  /// **'You’ve used today’s video time. Finish a mission and ask your grown-up to approve it to earn more.'**
  String get videoTimeExhaustedBody;

  /// No description provided for @videoGoToMissions.
  ///
  /// In en, this message translates to:
  /// **'Go to Missions'**
  String get videoGoToMissions;

  /// No description provided for @videoBackToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get videoBackToHome;

  /// No description provided for @parentGateScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Parent sign-in'**
  String get parentGateScreenTitle;

  /// No description provided for @parentGateScreenBody.
  ///
  /// In en, this message translates to:
  /// **'To leave child mode, sign in with the email and password of a parent in this family.'**
  String get parentGateScreenBody;

  /// No description provided for @parentGateContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get parentGateContinue;

  /// No description provided for @parentGateBackToChild.
  ///
  /// In en, this message translates to:
  /// **'Back to child mode'**
  String get parentGateBackToChild;

  /// No description provided for @parentGateAttemptsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attempt left} other{{count} attempts left}}'**
  String parentGateAttemptsLeft(int count);

  /// No description provided for @parentGateLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many incorrect attempts. Try again in {minutes, plural, =1{1 minute} other{{minutes} minutes}}.'**
  String parentGateLocked(int minutes);

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a new password for your parent account.'**
  String get resetPasswordBody;

  /// No description provided for @resetPasswordNew.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get resetPasswordNew;

  /// No description provided for @resetPasswordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get resetPasswordConfirm;

  /// No description provided for @resetPasswordMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two passwords do not match.'**
  String get resetPasswordMismatch;

  /// No description provided for @resetPasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save new password'**
  String get resetPasswordSubmit;

  /// No description provided for @resetPasswordDone.
  ///
  /// In en, this message translates to:
  /// **'Your password was changed. Sign in with your new password.'**
  String get resetPasswordDone;

  /// No description provided for @resetPasswordInvalid.
  ///
  /// In en, this message translates to:
  /// **'This reset link is invalid or has expired. Request a new one.'**
  String get resetPasswordInvalid;

  /// No description provided for @resetPasswordToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Go to sign in'**
  String get resetPasswordToSignIn;

  /// No description provided for @videoOfflinePaused.
  ///
  /// In en, this message translates to:
  /// **'Video paused: we can’t reach the internet.'**
  String get videoOfflinePaused;

  /// No description provided for @videoTimeCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t check your video time. Please try again.'**
  String get videoTimeCheckFailed;

  /// No description provided for @videoLockSummary.
  ///
  /// In en, this message translates to:
  /// **'You watched {watched} of {earned} minutes today.'**
  String videoLockSummary(int watched, int earned);

  /// No description provided for @parentVideoSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s video time'**
  String get parentVideoSummaryTitle;

  /// No description provided for @parentVideoEarned.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get parentVideoEarned;

  /// No description provided for @parentVideoWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get parentVideoWatched;

  /// No description provided for @parentVideoLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get parentVideoLeft;

  /// No description provided for @parentVideoCap.
  ///
  /// In en, this message translates to:
  /// **'Daily cap: {minutes} min'**
  String parentVideoCap(int minutes);

  /// No description provided for @parentVideoFree.
  ///
  /// In en, this message translates to:
  /// **'Includes {minutes} free minutes'**
  String parentVideoFree(int minutes);

  /// No description provided for @parentVideoMissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Missions that earned time'**
  String get parentVideoMissionsTitle;

  /// No description provided for @parentVideoNoMissions.
  ///
  /// In en, this message translates to:
  /// **'No mission has earned video time yet today.'**
  String get parentVideoNoMissions;

  /// No description provided for @parentVideoMissionUsed.
  ///
  /// In en, this message translates to:
  /// **'{used} of {granted} min used'**
  String parentVideoMissionUsed(int used, int granted);

  /// No description provided for @parentVideoSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load video time.'**
  String get parentVideoSummaryFailed;

  /// No description provided for @videoUpNextEmpty.
  ///
  /// In en, this message translates to:
  /// **'No more videos right now. Check back soon!'**
  String get videoUpNextEmpty;

  /// No description provided for @videoUpNextFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t load more videos.'**
  String get videoUpNextFailed;

  /// No description provided for @videoWatchNext.
  ///
  /// In en, this message translates to:
  /// **'Watch next'**
  String get videoWatchNext;

  /// No description provided for @videoWatchAgain.
  ///
  /// In en, this message translates to:
  /// **'Watch again'**
  String get videoWatchAgain;

  /// No description provided for @notifTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifTitle;

  /// No description provided for @notifCatAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notifCatAll;

  /// No description provided for @notifCatMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get notifCatMissions;

  /// No description provided for @notifCatRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get notifCatRewards;

  /// No description provided for @notifCatVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get notifCatVideos;

  /// No description provided for @notifCatStreaks.
  ///
  /// In en, this message translates to:
  /// **'Streaks'**
  String get notifCatStreaks;

  /// No description provided for @notifCatOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get notifCatOther;

  /// No description provided for @notifEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing new yet. Check back soon!'**
  String get notifEmpty;

  /// No description provided for @notifEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this group.'**
  String get notifEmptyFiltered;

  /// No description provided for @notifMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notifMarkAllRead;

  /// No description provided for @notifUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notifUnread;

  /// No description provided for @inviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite other parents'**
  String get inviteTitle;

  /// No description provided for @inviteCardPanda.
  ///
  /// In en, this message translates to:
  /// **'Panda, the BALKAVACH guide'**
  String get inviteCardPanda;

  /// No description provided for @inviteCardHeadline.
  ///
  /// In en, this message translates to:
  /// **'Missions first, then videos'**
  String get inviteCardHeadline;

  /// No description provided for @inviteCardBody.
  ///
  /// In en, this message translates to:
  /// **'Daily missions, a parent in charge, and safe video time that children earn.'**
  String get inviteCardBody;

  /// No description provided for @inviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Try BALKAVACH with your child: daily missions first, then safe video time, with a parent in charge.'**
  String get inviteMessage;

  /// No description provided for @inviteWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Share on WhatsApp'**
  String get inviteWhatsApp;

  /// No description provided for @inviteShare.
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get inviteShare;

  /// No description provided for @inviteShareImage.
  ///
  /// In en, this message translates to:
  /// **'Share the card as a picture'**
  String get inviteShareImage;

  /// No description provided for @inviteShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t open sharing.'**
  String get inviteShareFailed;

  /// No description provided for @invitePrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'This card has no information about your child.'**
  String get invitePrivacyNote;

  /// No description provided for @settingsInviteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share BALKAVACH with another family'**
  String get settingsInviteSubtitle;

  /// No description provided for @pandaName.
  ///
  /// In en, this message translates to:
  /// **'Panda'**
  String get pandaName;

  /// No description provided for @pandaGreeting1.
  ///
  /// In en, this message translates to:
  /// **'Hi! Ready for today’s missions?'**
  String get pandaGreeting1;

  /// No description provided for @pandaGreeting2.
  ///
  /// In en, this message translates to:
  /// **'Hello, friend! Let’s do something great today.'**
  String get pandaGreeting2;

  /// No description provided for @pandaMissionsReady1.
  ///
  /// In en, this message translates to:
  /// **'Your missions are ready. Pick the one you like!'**
  String get pandaMissionsReady1;

  /// No description provided for @pandaMissionsReady2.
  ///
  /// In en, this message translates to:
  /// **'New missions are waiting. Which one will you try?'**
  String get pandaMissionsReady2;

  /// No description provided for @pandaMissionSubmitted1.
  ///
  /// In en, this message translates to:
  /// **'Well done! Your grown-up will take a look.'**
  String get pandaMissionSubmitted1;

  /// No description provided for @pandaMissionSubmitted2.
  ///
  /// In en, this message translates to:
  /// **'Sent! Now we wait for your grown-up to check it.'**
  String get pandaMissionSubmitted2;

  /// No description provided for @pandaMissionApproved1.
  ///
  /// In en, this message translates to:
  /// **'Your mission was approved. Great job!'**
  String get pandaMissionApproved1;

  /// No description provided for @pandaMissionApproved2.
  ///
  /// In en, this message translates to:
  /// **'Approved! You did it. I’m so proud of you!'**
  String get pandaMissionApproved2;

  /// No description provided for @pandaVideoUnlocked1.
  ///
  /// In en, this message translates to:
  /// **'You unlocked {minutes} minutes of video time!'**
  String pandaVideoUnlocked1(int minutes);

  /// No description provided for @pandaVideoUnlocked2.
  ///
  /// In en, this message translates to:
  /// **'Yay! {minutes} minutes of videos are yours.'**
  String pandaVideoUnlocked2(int minutes);

  /// No description provided for @pandaVideoLow1.
  ///
  /// In en, this message translates to:
  /// **'Only a little video time is left. Finish up soon!'**
  String get pandaVideoLow1;

  /// No description provided for @pandaVideoLow2.
  ///
  /// In en, this message translates to:
  /// **'Almost time to stop. Pick a good ending spot!'**
  String get pandaVideoLow2;

  /// No description provided for @pandaVideoUp1.
  ///
  /// In en, this message translates to:
  /// **'Video time is done for now. Let’s rest our eyes and pick a mission!'**
  String get pandaVideoUp1;

  /// No description provided for @pandaVideoUp2.
  ///
  /// In en, this message translates to:
  /// **'That’s all the video time for today. Let’s try a mission!'**
  String get pandaVideoUp2;

  /// No description provided for @pandaGreetingNamed1.
  ///
  /// In en, this message translates to:
  /// **'Hi {name}! Ready for today’s missions?'**
  String pandaGreetingNamed1(String name);

  /// No description provided for @pandaGreetingNamed2.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}! Let’s do something great today.'**
  String pandaGreetingNamed2(String name);

  /// No description provided for @pandaMissionIntro1.
  ///
  /// In en, this message translates to:
  /// **'Today’s mission: {title}. Want to try it?'**
  String pandaMissionIntro1(String title);

  /// No description provided for @pandaMissionIntro2.
  ///
  /// In en, this message translates to:
  /// **'Here’s one for you: {title}. You can do it!'**
  String pandaMissionIntro2(String title);

  /// No description provided for @pandaRewardExplain1.
  ///
  /// In en, this message translates to:
  /// **'Finish it, get it approved, and you earn {stars, plural, =1{1 star} other{{stars} stars}} plus video time!'**
  String pandaRewardExplain1(int stars);

  /// No description provided for @pandaRewardExplain2.
  ///
  /// In en, this message translates to:
  /// **'Your reward: {stars, plural, =1{1 star} other{{stars} stars}} and more video time once a grown-up approves.'**
  String pandaRewardExplain2(int stars);

  /// No description provided for @pandaTalkOpen.
  ///
  /// In en, this message translates to:
  /// **'Talk to Panda'**
  String get pandaTalkOpen;

  /// No description provided for @pandaTalkClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get pandaTalkClose;

  /// No description provided for @pandaStateIdle.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic and talk to me!'**
  String get pandaStateIdle;

  /// No description provided for @pandaStateListening.
  ///
  /// In en, this message translates to:
  /// **'I’m listening…'**
  String get pandaStateListening;

  /// No description provided for @pandaStateThinking.
  ///
  /// In en, this message translates to:
  /// **'Hmm, let me think…'**
  String get pandaStateThinking;

  /// No description provided for @pandaStateSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Panda is talking'**
  String get pandaStateSpeaking;

  /// No description provided for @pandaStateHappy.
  ///
  /// In en, this message translates to:
  /// **'Yay!'**
  String get pandaStateHappy;

  /// No description provided for @pandaStateCurious.
  ///
  /// In en, this message translates to:
  /// **'Your turn! Tap the mic to answer.'**
  String get pandaStateCurious;

  /// No description provided for @pandaStateSleepy.
  ///
  /// In en, this message translates to:
  /// **'Panda is a little sleepy'**
  String get pandaStateSleepy;

  /// No description provided for @pandaMicButton.
  ///
  /// In en, this message translates to:
  /// **'Talk'**
  String get pandaMicButton;

  /// No description provided for @pandaStopButton.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get pandaStopButton;

  /// No description provided for @pandaTypeButton.
  ///
  /// In en, this message translates to:
  /// **'Type instead'**
  String get pandaTypeButton;

  /// No description provided for @pandaTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Type to Panda…'**
  String get pandaTypeHint;

  /// No description provided for @pandaSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get pandaSend;

  /// No description provided for @pandaYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get pandaYou;

  /// No description provided for @pandaMicExplainTitle.
  ///
  /// In en, this message translates to:
  /// **'Can Panda use the microphone?'**
  String get pandaMicExplainTitle;

  /// No description provided for @pandaMicExplainBody.
  ///
  /// In en, this message translates to:
  /// **'Panda only listens after you tap the mic, and stops when you finish talking. Your phone’s speech service turns your words into text. On many phones this is a Google service that may use the internet. BALKAVACH does not keep any recording. You can always type instead.'**
  String get pandaMicExplainBody;

  /// No description provided for @pandaMicAllow.
  ///
  /// In en, this message translates to:
  /// **'Yes, use the mic'**
  String get pandaMicAllow;

  /// No description provided for @pandaMicNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pandaMicNotNow;

  /// No description provided for @pandaErrorMicDenied.
  ///
  /// In en, this message translates to:
  /// **'I can’t use the microphone. That’s okay, you can type to me!'**
  String get pandaErrorMicDenied;

  /// No description provided for @pandaErrorMicUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Listening doesn’t work on this device. You can type to me!'**
  String get pandaErrorMicUnavailable;

  /// No description provided for @pandaErrorNotHeard.
  ///
  /// In en, this message translates to:
  /// **'I couldn’t hear you. Try again or type to me!'**
  String get pandaErrorNotHeard;

  /// No description provided for @pandaErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Oops, I can’t reach my home right now. Check the internet and try again.'**
  String get pandaErrorNetwork;

  /// No description provided for @pandaErrorBusy.
  ///
  /// In en, this message translates to:
  /// **'Let’s take a little break. Try again in a minute!'**
  String get pandaErrorBusy;

  /// No description provided for @pandaListenLanguageMissing.
  ///
  /// In en, this message translates to:
  /// **'This device can’t hear this language yet. Please type to me!'**
  String get pandaListenLanguageMissing;

  /// No description provided for @pandaVoiceMissing.
  ///
  /// In en, this message translates to:
  /// **'Panda’s voice isn’t available in this language on this device. Read along!'**
  String get pandaVoiceMissing;

  /// No description provided for @pandaSuggestMission.
  ///
  /// In en, this message translates to:
  /// **'My mission'**
  String get pandaSuggestMission;

  /// No description provided for @pandaSuggestVideo.
  ///
  /// In en, this message translates to:
  /// **'Video time'**
  String get pandaSuggestVideo;

  /// No description provided for @pandaSuggestJoke.
  ///
  /// In en, this message translates to:
  /// **'Tell a joke'**
  String get pandaSuggestJoke;

  /// No description provided for @pandaSuggestFact.
  ///
  /// In en, this message translates to:
  /// **'Fun fact'**
  String get pandaSuggestFact;

  /// No description provided for @pandaSuggestDraw.
  ///
  /// In en, this message translates to:
  /// **'Drawing idea'**
  String get pandaSuggestDraw;

  /// No description provided for @pandaSuggestStars.
  ///
  /// In en, this message translates to:
  /// **'My stars'**
  String get pandaSuggestStars;

  /// No description provided for @videoLockStepsTitle.
  ///
  /// In en, this message translates to:
  /// **'How to get more video time'**
  String get videoLockStepsTitle;

  /// No description provided for @videoLockStep1.
  ///
  /// In en, this message translates to:
  /// **'Pick a mission'**
  String get videoLockStep1;

  /// No description provided for @videoLockStep2.
  ///
  /// In en, this message translates to:
  /// **'Finish it and send it'**
  String get videoLockStep2;

  /// No description provided for @videoLockStep3.
  ///
  /// In en, this message translates to:
  /// **'Your grown-up checks it and approves'**
  String get videoLockStep3;

  /// No description provided for @videoLockStepsNote.
  ///
  /// In en, this message translates to:
  /// **'New video time shows up here by itself once it is approved.'**
  String get videoLockStepsNote;

  /// No description provided for @videoLockChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your video time…'**
  String get videoLockChecking;

  /// No description provided for @videoLockCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get videoLockCheckAgain;

  /// No description provided for @videoLockTimeBackTitle.
  ///
  /// In en, this message translates to:
  /// **'Video time is back!'**
  String get videoLockTimeBackTitle;

  /// No description provided for @videoLockTimeBackBody.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{You have 1 minute of video time.} other{You have {minutes} minutes of video time.}}'**
  String videoLockTimeBackBody(int minutes);

  /// No description provided for @videoLockWatchNow.
  ///
  /// In en, this message translates to:
  /// **'Watch videos'**
  String get videoLockWatchNow;

  /// No description provided for @videoLowTimeNotice.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{About 1 minute of video time left. Time to finish up your video!} other{About {minutes} minutes of video time left. Time to finish up your video!}}'**
  String videoLowTimeNotice(int minutes);

  /// No description provided for @notifPrefsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get notifPrefsTitle;

  /// No description provided for @notifPrefsEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose which alerts reach your family\'s phones, and set quiet hours'**
  String get notifPrefsEntrySubtitle;

  /// No description provided for @notifPrefsParentOnly.
  ///
  /// In en, this message translates to:
  /// **'Only a parent can change notification preferences.'**
  String get notifPrefsParentOnly;

  /// No description provided for @notifPrefsIntro.
  ///
  /// In en, this message translates to:
  /// **'These choices decide which alerts pop up on your family\'s phones. Everything still appears in the app\'s notification list, so nothing is lost.'**
  String get notifPrefsIntro;

  /// No description provided for @notifPrefsPushOff.
  ///
  /// In en, this message translates to:
  /// **'Push notifications are turned off for your account on this phone, so alerts will only appear inside the app.'**
  String get notifPrefsPushOff;

  /// No description provided for @notifPrefsPushDenied.
  ///
  /// In en, this message translates to:
  /// **'This phone is not allowed to show notifications. Allow them in the phone\'s settings to receive alerts.'**
  String get notifPrefsPushDenied;

  /// No description provided for @notifPrefsPushUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This version of the app cannot receive push alerts yet. Your choices are still saved for the family.'**
  String get notifPrefsPushUnavailable;

  /// No description provided for @notifPrefsGroupMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get notifPrefsGroupMissions;

  /// No description provided for @notifPrefsGroupStreaks.
  ///
  /// In en, this message translates to:
  /// **'Streaks'**
  String get notifPrefsGroupStreaks;

  /// No description provided for @notifPrefsGroupVideos.
  ///
  /// In en, this message translates to:
  /// **'Video time'**
  String get notifPrefsGroupVideos;

  /// No description provided for @notifPrefsGroupRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards and badges'**
  String get notifPrefsGroupRewards;

  /// No description provided for @notifPrefsGroupSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety'**
  String get notifPrefsGroupSafety;

  /// No description provided for @notifPrefsNewMissions.
  ///
  /// In en, this message translates to:
  /// **'New missions'**
  String get notifPrefsNewMissions;

  /// No description provided for @notifPrefsNewMissionsBody.
  ///
  /// In en, this message translates to:
  /// **'Tell your child when a new mission is ready for them.'**
  String get notifPrefsNewMissionsBody;

  /// No description provided for @notifPrefsMissionReviews.
  ///
  /// In en, this message translates to:
  /// **'Mission approvals'**
  String get notifPrefsMissionReviews;

  /// No description provided for @notifPrefsMissionReviewsBody.
  ///
  /// In en, this message translates to:
  /// **'Tell you when a mission is waiting for review, and your child when it is approved or needs another try.'**
  String get notifPrefsMissionReviewsBody;

  /// No description provided for @notifPrefsStreaks.
  ///
  /// In en, this message translates to:
  /// **'Streak reminders and milestones'**
  String get notifPrefsStreaks;

  /// No description provided for @notifPrefsStreaksBody.
  ///
  /// In en, this message translates to:
  /// **'Remind your child when a streak is at risk and celebrate new milestones.'**
  String get notifPrefsStreaksBody;

  /// No description provided for @notifPrefsVideoAllowance.
  ///
  /// In en, this message translates to:
  /// **'Video time updates'**
  String get notifPrefsVideoAllowance;

  /// No description provided for @notifPrefsVideoAllowanceBody.
  ///
  /// In en, this message translates to:
  /// **'Tell your child when they earn video time and when only a little is left.'**
  String get notifPrefsVideoAllowanceBody;

  /// No description provided for @notifPrefsVideoTimeUp.
  ///
  /// In en, this message translates to:
  /// **'Video time finished'**
  String get notifPrefsVideoTimeUp;

  /// No description provided for @notifPrefsVideoTimeUpBody.
  ///
  /// In en, this message translates to:
  /// **'Tell your child when today\'s video time has run out.'**
  String get notifPrefsVideoTimeUpBody;

  /// No description provided for @notifPrefsRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards and badges'**
  String get notifPrefsRewards;

  /// No description provided for @notifPrefsRewardsBody.
  ///
  /// In en, this message translates to:
  /// **'Reward requests, approvals and new badges.'**
  String get notifPrefsRewardsBody;

  /// No description provided for @notifPrefsSafety.
  ///
  /// In en, this message translates to:
  /// **'Safety alerts'**
  String get notifPrefsSafety;

  /// No description provided for @notifPrefsSafetyBody.
  ///
  /// In en, this message translates to:
  /// **'For example, several wrong parent sign-in attempts on a child\'s device.'**
  String get notifPrefsSafetyBody;

  /// No description provided for @notifPrefsAlwaysOnNote.
  ///
  /// In en, this message translates to:
  /// **'Always on for your child\'s safety.'**
  String get notifPrefsAlwaysOnNote;

  /// No description provided for @notifPrefsQuietTitle.
  ///
  /// In en, this message translates to:
  /// **'Quiet hours'**
  String get notifPrefsQuietTitle;

  /// No description provided for @notifPrefsQuietSwitch.
  ///
  /// In en, this message translates to:
  /// **'Pause alerts during quiet hours'**
  String get notifPrefsQuietSwitch;

  /// No description provided for @notifPrefsQuietBody.
  ///
  /// In en, this message translates to:
  /// **'No alerts pop up during this time. They wait in the app\'s notification list instead.'**
  String get notifPrefsQuietBody;

  /// No description provided for @notifPrefsQuietStart.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get notifPrefsQuietStart;

  /// No description provided for @notifPrefsQuietEnd.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get notifPrefsQuietEnd;

  /// No description provided for @notifPrefsQuietOvernight.
  ///
  /// In en, this message translates to:
  /// **'Runs overnight, from {start} until {end} the next morning.'**
  String notifPrefsQuietOvernight(String start, String end);

  /// No description provided for @notifPrefsQuietZone.
  ///
  /// In en, this message translates to:
  /// **'Times are in your family\'s time zone: {zone}'**
  String notifPrefsQuietZone(String zone);

  /// No description provided for @notifPrefsQuietZoneDefault.
  ///
  /// In en, this message translates to:
  /// **'Your family has no time zone saved yet, so UTC is used. Open Settings on a parent\'s phone to save it automatically.'**
  String get notifPrefsQuietZoneDefault;

  /// No description provided for @notifPrefsQuietSafetyNote.
  ///
  /// In en, this message translates to:
  /// **'Safety alerts are still sent during quiet hours.'**
  String get notifPrefsQuietSafetyNote;

  /// No description provided for @notifPrefsQuietSame.
  ///
  /// In en, this message translates to:
  /// **'Start and end times must be different.'**
  String get notifPrefsQuietSame;

  /// No description provided for @videoTicketStarting.
  ///
  /// In en, this message translates to:
  /// **'Getting your video ready…'**
  String get videoTicketStarting;

  /// No description provided for @videoTicketSuperseded.
  ///
  /// In en, this message translates to:
  /// **'This video started playing on another device, so it stopped here. Tap Try again to watch here instead.'**
  String get videoTicketSuperseded;

  /// No description provided for @videoTicketStopped.
  ///
  /// In en, this message translates to:
  /// **'The video stopped. Tap Try again to keep watching.'**
  String get videoTicketStopped;

  /// No description provided for @videoTicketRevoked.
  ///
  /// In en, this message translates to:
  /// **'This video isn’t available right now.'**
  String get videoTicketRevoked;

  /// No description provided for @videoUpdateRequired.
  ///
  /// In en, this message translates to:
  /// **'This version of BALKAVACH can’t play videos any more. Ask a grown-up to update the app.'**
  String get videoUpdateRequired;

  /// No description provided for @pandaVoiceNeedsParent.
  ///
  /// In en, this message translates to:
  /// **'Talking out loud to Panda needs a grown-up’s OK first. You can type to Panda instead!'**
  String get pandaVoiceNeedsParent;

  /// No description provided for @pandaVoiceTurnedOff.
  ///
  /// In en, this message translates to:
  /// **'A grown-up has turned off talking out loud to Panda. You can type to Panda instead!'**
  String get pandaVoiceTurnedOff;

  /// No description provided for @pandaMicExplainBodyOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Panda only listens after you tap the mic, and stops when you finish talking. Your phone turns your words into text right here on the phone, so your voice is not sent anywhere. BALKAVACH does not keep any recording. You can always type instead.'**
  String get pandaMicExplainBodyOnDevice;

  /// No description provided for @pandaConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Talk to Panda: microphone'**
  String get pandaConsentTitle;

  /// No description provided for @pandaConsentEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose which children may talk to Panda out loud'**
  String get pandaConsentEntrySubtitle;

  /// No description provided for @pandaConsentParentOnly.
  ///
  /// In en, this message translates to:
  /// **'Only a parent can change this.'**
  String get pandaConsentParentOnly;

  /// No description provided for @pandaConsentIntro.
  ///
  /// In en, this message translates to:
  /// **'The microphone stays off until you agree, child by child. Typing to Panda always works.'**
  String get pandaConsentIntro;

  /// No description provided for @pandaConsentDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Panda listens only after your child taps the microphone, and stops when they finish talking. Your phone’s speech service turns the words into text. On many Android phones this is a Google service that may process the audio over the internet under Google’s terms. BALKAVACH keeps no recording and does not store what your child says; Panda’s reply is chosen from lines we wrote. Panda’s voice also comes from your phone’s text-to-speech service. You can turn the microphone off again at any time.'**
  String get pandaConsentDisclosure;

  /// No description provided for @pandaConsentOn.
  ///
  /// In en, this message translates to:
  /// **'Allowed to talk out loud'**
  String get pandaConsentOn;

  /// No description provided for @pandaConsentOff.
  ///
  /// In en, this message translates to:
  /// **'Microphone off (typing only)'**
  String get pandaConsentOff;

  /// No description provided for @pandaConsentDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Let {name} talk to Panda out loud?'**
  String pandaConsentDialogTitle(String name);

  /// No description provided for @pandaConsentAgree.
  ///
  /// In en, this message translates to:
  /// **'I agree'**
  String get pandaConsentAgree;

  /// No description provided for @pandaConsentCancel.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pandaConsentCancel;

  /// No description provided for @pandaConsentWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Microphone turned off for {name}.'**
  String pandaConsentWithdrawn(String name);

  /// No description provided for @pandaConsentSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t save that. Please try again.'**
  String get pandaConsentSaveFailed;

  /// No description provided for @pandaConsentOutdated.
  ///
  /// In en, this message translates to:
  /// **'This explanation has changed. Please update the app, then try again.'**
  String get pandaConsentOutdated;

  /// No description provided for @missionsUnfinishedTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue Your Missions'**
  String get missionsUnfinishedTitle;

  /// No description provided for @missionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get missionContinue;

  /// No description provided for @missionFromDay.
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String missionFromDay(String date);

  /// No description provided for @missionsHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready for an adventure?'**
  String get missionsHeroTitle;

  /// No description provided for @missionsHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Finish a mission, earn stars and help your garden grow. You\'ve got this!'**
  String get missionsHeroSubtitle;

  /// No description provided for @missionsProgressStart.
  ///
  /// In en, this message translates to:
  /// **'Let\'s finish your first mission!'**
  String get missionsProgressStart;

  /// No description provided for @missionsProgressKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Great start! Keep going!'**
  String get missionsProgressKeepGoing;

  /// No description provided for @missionsProgressAllDone.
  ///
  /// In en, this message translates to:
  /// **'All done! Amazing work!'**
  String get missionsProgressAllDone;

  /// No description provided for @missionsStarsEarned.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star earned} other{{count} stars earned}}'**
  String missionsStarsEarned(int count);

  /// No description provided for @missionsUnfinishedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick up right where you left off.'**
  String get missionsUnfinishedSubtitle;

  /// No description provided for @missionsChoosePrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a mission to begin.'**
  String get missionsChoosePrompt;

  /// No description provided for @missionsForYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Missions for You'**
  String get missionsForYouTitle;

  /// No description provided for @missionsCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get missionsCompletedTitle;

  /// No description provided for @missionMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String missionMinutes(int count);

  /// No description provided for @missionTrackStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get missionTrackStart;

  /// No description provided for @missionTrackSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get missionTrackSent;

  /// No description provided for @missionTrackDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get missionTrackDone;

  /// No description provided for @missionCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Mission complete!'**
  String get missionCompleteTitle;

  /// No description provided for @missionStepLabel.
  ///
  /// In en, this message translates to:
  /// **'Step {number}'**
  String missionStepLabel(int number);

  /// No description provided for @missionsChoiceTaken.
  ///
  /// In en, this message translates to:
  /// **'You picked another mission today.'**
  String get missionsChoiceTaken;

  /// No description provided for @missionsStatDone.
  ///
  /// In en, this message translates to:
  /// **'Done today'**
  String get missionsStatDone;

  /// No description provided for @missionsStatStars.
  ///
  /// In en, this message translates to:
  /// **'Stars today'**
  String get missionsStatStars;

  /// No description provided for @missionsStatXp.
  ///
  /// In en, this message translates to:
  /// **'XP today'**
  String get missionsStatXp;

  /// No description provided for @missionEarnBoth.
  ///
  /// In en, this message translates to:
  /// **'Finish this mission to earn {stars} stars and {xp} XP.'**
  String missionEarnBoth(int stars, int xp);

  /// No description provided for @missionEarnedBoth.
  ///
  /// In en, this message translates to:
  /// **'You earned {stars} stars and {xp} XP!'**
  String missionEarnedBoth(int stars, int xp);

  /// No description provided for @errorDailyAlreadySelected.
  ///
  /// In en, this message translates to:
  /// **'You already picked today\'s mission. Finish that one first!'**
  String get errorDailyAlreadySelected;

  /// No description provided for @errorBirthDateRequired.
  ///
  /// In en, this message translates to:
  /// **'Ask a grown-up to add your birthday to get daily missions.'**
  String get errorBirthDateRequired;

  /// No description provided for @errorBirthDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Your birthday looks wrong. Ask a grown-up to fix it.'**
  String get errorBirthDateInvalid;

  /// No description provided for @errorAgeRange.
  ///
  /// In en, this message translates to:
  /// **'Daily missions are for ages 4 to 15.'**
  String get errorAgeRange;

  /// No description provided for @errorMissionNotForAge.
  ///
  /// In en, this message translates to:
  /// **'This mission was made for a different age. Pick one of today\'s missions!'**
  String get errorMissionNotForAge;

  /// No description provided for @createMissionRewardTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward for every approved mission'**
  String get createMissionRewardTitle;

  /// No description provided for @createMissionRewardStars.
  ///
  /// In en, this message translates to:
  /// **'Approval reward: {count} Stars'**
  String createMissionRewardStars(int count);

  /// No description provided for @createMissionRewardXp.
  ///
  /// In en, this message translates to:
  /// **'Approval reward: {count} XP'**
  String createMissionRewardXp(int count);

  /// No description provided for @createMissionRewardFixed.
  ///
  /// In en, this message translates to:
  /// **'The reward is the same for every mission and is set by the app, so it cannot be changed here.'**
  String get createMissionRewardFixed;

  /// No description provided for @hubTabVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get hubTabVideos;

  /// No description provided for @hubTabQuizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get hubTabQuizzes;

  /// No description provided for @hubTabStories.
  ///
  /// In en, this message translates to:
  /// **'Stories'**
  String get hubTabStories;

  /// No description provided for @hubTabShorts.
  ///
  /// In en, this message translates to:
  /// **'Shorts'**
  String get hubTabShorts;

  /// No description provided for @hubShortsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No Shorts to watch right now. Check back soon!'**
  String get hubShortsEmpty;

  /// No description provided for @learnHubEntryTitle.
  ///
  /// In en, this message translates to:
  /// **'Learn & play'**
  String get learnHubEntryTitle;

  /// No description provided for @quizzesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Quizzes aren\'t ready yet. Please try again later.'**
  String get quizzesUnavailable;

  /// No description provided for @interestsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Video interests aren\'t ready yet. Please try again later.'**
  String get interestsUnavailable;

  /// No description provided for @interestsActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Your topics (approved by your parent)'**
  String get interestsActiveTitle;

  /// No description provided for @interestsActiveNone.
  ///
  /// In en, this message translates to:
  /// **'No topics chosen yet.'**
  String get interestsActiveNone;

  /// No description provided for @interestsPendingChildTitle.
  ///
  /// In en, this message translates to:
  /// **'You asked for (waiting for your parent)'**
  String get interestsPendingChildTitle;

  /// No description provided for @interestsAskTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for changes'**
  String get interestsAskTitle;

  /// No description provided for @hubMoreToExplore.
  ///
  /// In en, this message translates to:
  /// **'More to explore'**
  String get hubMoreToExplore;

  /// No description provided for @storiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No stories yet. Check back soon!'**
  String get storiesEmpty;

  /// No description provided for @storyReadingTime.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 min read} other{{minutes} min read}}'**
  String storyReadingTime(int minutes);

  /// No description provided for @quizzesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No quizzes yet. Check back soon!'**
  String get quizzesEmpty;

  /// No description provided for @quizQuestionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 question} other{{count} questions}}'**
  String quizQuestionCount(int count);

  /// No description provided for @quizDifficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get quizDifficultyEasy;

  /// No description provided for @quizDifficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get quizDifficultyMedium;

  /// No description provided for @quizDifficultyHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get quizDifficultyHard;

  /// No description provided for @quizStatusPending.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get quizStatusPending;

  /// No description provided for @quizStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get quizStatusInProgress;

  /// No description provided for @quizStatusAttempted.
  ///
  /// In en, this message translates to:
  /// **'Tried'**
  String get quizStatusAttempted;

  /// No description provided for @quizStatusPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get quizStatusPassed;

  /// No description provided for @quizBestScore.
  ///
  /// In en, this message translates to:
  /// **'Best: {percent}%'**
  String quizBestScore(int percent);

  /// No description provided for @quizPassMark.
  ///
  /// In en, this message translates to:
  /// **'Pass mark: {percent}%'**
  String quizPassMark(int percent);

  /// No description provided for @quizRewardPrefix.
  ///
  /// In en, this message translates to:
  /// **'First pass earns'**
  String get quizRewardPrefix;

  /// No description provided for @quizRewardStars.
  ///
  /// In en, this message translates to:
  /// **'{count} Stars'**
  String quizRewardStars(int count);

  /// No description provided for @quizRewardXp.
  ///
  /// In en, this message translates to:
  /// **'{count} XP'**
  String quizRewardXp(int count);

  /// No description provided for @quizStart.
  ///
  /// In en, this message translates to:
  /// **'Start quiz'**
  String get quizStart;

  /// No description provided for @quizResume.
  ///
  /// In en, this message translates to:
  /// **'Continue quiz'**
  String get quizResume;

  /// No description provided for @quizTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get quizTryAgain;

  /// No description provided for @quizOnlyOnce.
  ///
  /// In en, this message translates to:
  /// **'You have already taken this quiz.'**
  String get quizOnlyOnce;

  /// No description provided for @quizHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your tries'**
  String get quizHistoryTitle;

  /// No description provided for @quizQuestionOf.
  ///
  /// In en, this message translates to:
  /// **'Question {current} of {total}'**
  String quizQuestionOf(int current, int total);

  /// No description provided for @quizPickOne.
  ///
  /// In en, this message translates to:
  /// **'Choose one answer'**
  String get quizPickOne;

  /// No description provided for @quizPickMany.
  ///
  /// In en, this message translates to:
  /// **'Choose all the right answers'**
  String get quizPickMany;

  /// No description provided for @quizNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get quizNext;

  /// No description provided for @quizPrevious.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get quizPrevious;

  /// No description provided for @quizSubmit.
  ///
  /// In en, this message translates to:
  /// **'Finish quiz'**
  String get quizSubmit;

  /// No description provided for @quizLeaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave the quiz?'**
  String get quizLeaveTitle;

  /// No description provided for @quizLeaveBody.
  ///
  /// In en, this message translates to:
  /// **'Your answers on this try will be lost.'**
  String get quizLeaveBody;

  /// No description provided for @quizLeaveStay.
  ///
  /// In en, this message translates to:
  /// **'Keep going'**
  String get quizLeaveStay;

  /// No description provided for @quizLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get quizLeaveConfirm;

  /// No description provided for @quizChanged.
  ///
  /// In en, this message translates to:
  /// **'This quiz was updated. Please start it again.'**
  String get quizChanged;

  /// No description provided for @quizResultPassed.
  ///
  /// In en, this message translates to:
  /// **'Great job!'**
  String get quizResultPassed;

  /// No description provided for @quizResultTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Good try!'**
  String get quizResultTryAgain;

  /// No description provided for @quizScoreLine.
  ///
  /// In en, this message translates to:
  /// **'You got {correct} of {total} right'**
  String quizScoreLine(int correct, int total);

  /// No description provided for @quizCorrectLabel.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get quizCorrectLabel;

  /// No description provided for @quizIncorrectLabel.
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get quizIncorrectLabel;

  /// No description provided for @quizScoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get quizScoreLabel;

  /// No description provided for @quizEarned.
  ///
  /// In en, this message translates to:
  /// **'You earned {stars} Stars and {xp} XP!'**
  String quizEarned(int stars, int xp);

  /// No description provided for @quizRewardOnce.
  ///
  /// In en, this message translates to:
  /// **'Rewards are given once, the first time you pass.'**
  String get quizRewardOnce;

  /// No description provided for @quizNeedMore.
  ///
  /// In en, this message translates to:
  /// **'You need {percent}% to pass. You can try again!'**
  String quizNeedMore(int percent);

  /// No description provided for @quizReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review your answers'**
  String get quizReviewTitle;

  /// No description provided for @quizYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get quizYourAnswer;

  /// No description provided for @quizRightAnswer.
  ///
  /// In en, this message translates to:
  /// **'Right answer'**
  String get quizRightAnswer;

  /// No description provided for @quizReviewUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The quiz was updated, so the review is not available.'**
  String get quizReviewUnavailable;

  /// No description provided for @quizBackToLearn.
  ///
  /// In en, this message translates to:
  /// **'Back to Learn'**
  String get quizBackToLearn;

  /// No description provided for @quizHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get quizHome;

  /// No description provided for @celebrationMission.
  ///
  /// In en, this message translates to:
  /// **'Mission complete!'**
  String get celebrationMission;

  /// No description provided for @celebrationQuiz.
  ///
  /// In en, this message translates to:
  /// **'Quiz complete!'**
  String get celebrationQuiz;

  /// No description provided for @celebrationVideo.
  ///
  /// In en, this message translates to:
  /// **'Video done!'**
  String get celebrationVideo;

  /// No description provided for @celebrationStory.
  ///
  /// In en, this message translates to:
  /// **'Story finished!'**
  String get celebrationStory;

  /// No description provided for @celebrationGarden.
  ///
  /// In en, this message translates to:
  /// **'Your garden is growing!'**
  String get celebrationGarden;

  /// No description provided for @celebrationCheer.
  ///
  /// In en, this message translates to:
  /// **'Great job! Keep going!'**
  String get celebrationCheer;

  /// No description provided for @celebrationMissionPending.
  ///
  /// In en, this message translates to:
  /// **'Your parent will check it, then your rewards arrive.'**
  String get celebrationMissionPending;

  /// No description provided for @celebrationContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get celebrationContinue;

  /// No description provided for @celebrationHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get celebrationHome;

  /// No description provided for @celebrationMissionApproved.
  ///
  /// In en, this message translates to:
  /// **'Mission approved!'**
  String get celebrationMissionApproved;

  /// No description provided for @celebrationMissionApprovedNote.
  ///
  /// In en, this message translates to:
  /// **'Your parent approved it. Here are your rewards!'**
  String get celebrationMissionApprovedNote;

  /// No description provided for @levelXpToNext.
  ///
  /// In en, this message translates to:
  /// **'{xp} XP to Level {level}'**
  String levelXpToNext(int xp, int level);

  /// No description provided for @levelMaxReached.
  ///
  /// In en, this message translates to:
  /// **'You reached the top level!'**
  String get levelMaxReached;

  /// No description provided for @achievementsLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep going!'**
  String get achievementsLockedTitle;

  /// No description provided for @achievementsProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} of {target}'**
  String achievementsProgress(int current, int target);

  /// No description provided for @celebrationLevelUp.
  ///
  /// In en, this message translates to:
  /// **'Level up!'**
  String get celebrationLevelUp;

  /// No description provided for @celebrationBadge.
  ///
  /// In en, this message translates to:
  /// **'New badge!'**
  String get celebrationBadge;

  /// No description provided for @rewardsTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get rewardsTabHistory;

  /// No description provided for @rewardsHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No finished requests yet.'**
  String get rewardsHistoryEmpty;

  /// No description provided for @rewardStatusFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Handed over'**
  String get rewardStatusFulfilled;

  /// No description provided for @rewardStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get rewardStatusRejected;

  /// No description provided for @rewardStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get rewardStatusCancelled;

  /// No description provided for @rewardHistoryRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested {date}'**
  String rewardHistoryRequested(String date);

  /// No description provided for @rewardHistoryDecided.
  ///
  /// In en, this message translates to:
  /// **'Decided {date}'**
  String rewardHistoryDecided(String date);

  /// No description provided for @rewardHistoryFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Handed over {date}'**
  String rewardHistoryFulfilled(String date);

  /// No description provided for @rewardHistoryNote.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String rewardHistoryNote(String note);

  /// No description provided for @rewardHistoryUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Reward'**
  String get rewardHistoryUnnamed;

  /// No description provided for @parentAchievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Level and badges'**
  String get parentAchievementsTitle;

  /// No description provided for @parentBadgesEarnedTitle.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get parentBadgesEarnedTitle;

  /// No description provided for @parentNoBadgesEarned.
  ///
  /// In en, this message translates to:
  /// **'No badges earned yet.'**
  String get parentNoBadgesEarned;

  /// No description provided for @parentNoBadgesDefined.
  ///
  /// In en, this message translates to:
  /// **'There are no badges to earn yet.'**
  String get parentNoBadgesDefined;

  /// No description provided for @parentBadgeEarnedOn.
  ///
  /// In en, this message translates to:
  /// **'Earned {date}'**
  String parentBadgeEarnedOn(String date);

  /// No description provided for @parentQuizHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get parentQuizHistoryTitle;

  /// No description provided for @parentQuizHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No quizzes taken yet.'**
  String get parentQuizHistoryEmpty;

  /// No description provided for @parentQuizNotPassed.
  ///
  /// In en, this message translates to:
  /// **'Not passed'**
  String get parentQuizNotPassed;

  /// No description provided for @parentLevelUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No level yet.'**
  String get parentLevelUnavailable;

  /// No description provided for @parentQuizScoreLine.
  ///
  /// In en, this message translates to:
  /// **'{correct} of {total} right'**
  String parentQuizScoreLine(int correct, int total);

  /// No description provided for @settingsHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get settingsHelpTitle;

  /// No description provided for @settingsHelpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently asked questions and safety guide'**
  String get settingsHelpSubtitle;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsDeleteAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove personal data and sign out permanently'**
  String get settingsDeleteAccountSubtitle;

  /// No description provided for @settingsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get settingsDeleteConfirmTitle;

  /// No description provided for @settingsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently signs out your family and anonymizes personal details and child profiles. Financial/star ledgers and audit history are retained in anonymized form.'**
  String get settingsDeleteConfirmBody;

  /// No description provided for @settingsDeletePasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to confirm'**
  String get settingsDeletePasswordLabel;

  /// No description provided for @settingsDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get settingsDeleteAction;

  /// No description provided for @interestsTitle.
  ///
  /// In en, this message translates to:
  /// **'Video interests'**
  String get interestsTitle;

  /// No description provided for @interestsParentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approved topics personalize this child\'s video feed.'**
  String get interestsParentSubtitle;

  /// No description provided for @interestsChildSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Active topics chosen by your parent. You can request changes below.'**
  String get interestsChildSubtitle;

  /// No description provided for @interestsPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending child requests'**
  String get interestsPendingTitle;

  /// No description provided for @interestsPendingBadge.
  ///
  /// In en, this message translates to:
  /// **'Waiting for parent approval'**
  String get interestsPendingBadge;

  /// No description provided for @interestsApproveAll.
  ///
  /// In en, this message translates to:
  /// **'Approve requests'**
  String get interestsApproveAll;

  /// No description provided for @interestsRejectAll.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get interestsRejectAll;

  /// No description provided for @interestsSave.
  ///
  /// In en, this message translates to:
  /// **'Save interests'**
  String get interestsSave;

  /// No description provided for @interestsRequestSave.
  ///
  /// In en, this message translates to:
  /// **'Request these interests'**
  String get interestsRequestSave;

  /// No description provided for @interestsSaved.
  ///
  /// In en, this message translates to:
  /// **'Interests updated'**
  String get interestsSaved;

  /// No description provided for @interestsRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Interest request sent to parent'**
  String get interestsRequestSent;

  /// No description provided for @interestsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No topics available yet.'**
  String get interestsEmpty;

  /// No description provided for @interestsChildNotLinked.
  ///
  /// In en, this message translates to:
  /// **'This child isn\'t linked to your account, so their topics can\'t be changed here.'**
  String get interestsChildNotLinked;

  /// No description provided for @interestsApproveHint.
  ///
  /// In en, this message translates to:
  /// **'Approving replaces the current topics with the ones your child asked for.'**
  String get interestsApproveHint;

  /// No description provided for @interestsRequestPickOne.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one topic to ask for.'**
  String get interestsRequestPickOne;

  /// No description provided for @interestsParentActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Approved topics'**
  String get interestsParentActiveTitle;

  /// No description provided for @interestsParentChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose topics'**
  String get interestsParentChooseTitle;

  /// No description provided for @childLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Link child device'**
  String get childLinkTitle;

  /// No description provided for @childLinkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generate a short-lived, single-use code or QR payload for the child\'s device.'**
  String get childLinkSubtitle;

  /// No description provided for @childLinkGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate link code'**
  String get childLinkGenerate;

  /// No description provided for @childLinkCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get childLinkCopy;

  /// No description provided for @childLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link code copied'**
  String get childLinkCopied;

  /// No description provided for @childLinkExpires.
  ///
  /// In en, this message translates to:
  /// **'Expires in {minutes}m {seconds}s'**
  String childLinkExpires(int minutes, int seconds);

  /// No description provided for @childLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'Code expired. Generate a new one.'**
  String get childLinkExpired;

  /// No description provided for @childLinkEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Or link with a parent code'**
  String get childLinkEnterTitle;

  /// No description provided for @childLinkCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Enter 8-character code or QR link'**
  String get childLinkCodeHint;

  /// No description provided for @childLinkConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Link this device?'**
  String get childLinkConfirmTitle;

  /// No description provided for @childLinkConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This connects this device to your child profile using the single-use code.'**
  String get childLinkConfirmBody;

  /// No description provided for @childLinkAction.
  ///
  /// In en, this message translates to:
  /// **'Link device'**
  String get childLinkAction;
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
