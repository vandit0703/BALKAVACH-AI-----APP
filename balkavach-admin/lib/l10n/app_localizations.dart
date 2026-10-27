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

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Bal Kavach Admin'**
  String get appName;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get navUsers;

  /// No description provided for @navFamilies.
  ///
  /// In en, this message translates to:
  /// **'Families'**
  String get navFamilies;

  /// No description provided for @navMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get navMissions;

  /// No description provided for @navCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// No description provided for @navPresets.
  ///
  /// In en, this message translates to:
  /// **'Preset missions'**
  String get navPresets;

  /// No description provided for @navRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get navRewards;

  /// No description provided for @navRedemptions.
  ///
  /// In en, this message translates to:
  /// **'Reward requests'**
  String get navRedemptions;

  /// No description provided for @navContent.
  ///
  /// In en, this message translates to:
  /// **'Learning content'**
  String get navContent;

  /// No description provided for @navYoutubeReviews.
  ///
  /// In en, this message translates to:
  /// **'YouTube review'**
  String get navYoutubeReviews;

  /// No description provided for @navBadges.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get navBadges;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get navAudit;

  /// No description provided for @navGroupOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navGroupOverview;

  /// No description provided for @navGroupPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get navGroupPeople;

  /// No description provided for @navGroupMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions & rewards'**
  String get navGroupMissions;

  /// No description provided for @navGroupLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get navGroupLearning;

  /// No description provided for @navGroupSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get navGroupSystem;

  /// No description provided for @breadcrumbLabel.
  ///
  /// In en, this message translates to:
  /// **'You are here'**
  String get breadcrumbLabel;

  /// No description provided for @noAccess.
  ///
  /// In en, this message translates to:
  /// **'Your role does not include access to this section.'**
  String get noAccess;

  /// No description provided for @accountTooltip.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTooltip;

  /// No description provided for @accountRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles: {roles}'**
  String accountRoles(String roles);

  /// No description provided for @languageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTooltip;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionTryAgain;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get actionDeactivate;

  /// No description provided for @actionReactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get actionReactivate;

  /// No description provided for @actionSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get actionSignIn;

  /// No description provided for @actionSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get actionSignOut;

  /// No description provided for @actionApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get actionApply;

  /// No description provided for @actionChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get actionChange;

  /// No description provided for @actionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get actionDetails;

  /// No description provided for @actionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get actionHide;

  /// No description provided for @actionShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get actionShow;

  /// No description provided for @actionRoles.
  ///
  /// In en, this message translates to:
  /// **'Roles'**
  String get actionRoles;

  /// No description provided for @validationRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get validationRequired;

  /// No description provided for @validationMaxLength.
  ///
  /// In en, this message translates to:
  /// **'At most {max} characters'**
  String validationMaxLength(String max);

  /// No description provided for @validationWholeNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number'**
  String get validationWholeNumber;

  /// No description provided for @validationAtLeast.
  ///
  /// In en, this message translates to:
  /// **'At least {min}'**
  String validationAtLeast(String min);

  /// No description provided for @validationAtMost.
  ///
  /// In en, this message translates to:
  /// **'At most {max}'**
  String validationAtMost(String max);

  /// No description provided for @validationHttps.
  ///
  /// In en, this message translates to:
  /// **'Enter a full https:// link'**
  String get validationHttps;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check the connection.'**
  String get errorNetwork;

  /// No description provided for @errorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do this.'**
  String get errorForbidden;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'That item no longer exists.'**
  String get errorNotFound;

  /// No description provided for @errorConflict.
  ///
  /// In en, this message translates to:
  /// **'That conflicts with something that already exists.'**
  String get errorConflict;

  /// No description provided for @errorValidation.
  ///
  /// In en, this message translates to:
  /// **'Some of the values are not valid. Check them and try again.'**
  String get errorValidation;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem. Please try again in a moment.'**
  String get errorServer;

  /// No description provided for @errorLastSuperAdmin.
  ///
  /// In en, this message translates to:
  /// **'The last super administrator cannot be removed or deactivated.'**
  String get errorLastSuperAdmin;

  /// No description provided for @errorEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'That email address is already in use.'**
  String get errorEmailInUse;

  /// No description provided for @errorUsernameInUse.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken.'**
  String get errorUsernameInUse;

  /// No description provided for @errorCategoryConflict.
  ///
  /// In en, this message translates to:
  /// **'A category with that name already exists.'**
  String get errorCategoryConflict;

  /// No description provided for @errorInvalidSetting.
  ///
  /// In en, this message translates to:
  /// **'That setting value is not valid.'**
  String get errorInvalidSetting;

  /// No description provided for @errorInvalidAgeRange.
  ///
  /// In en, this message translates to:
  /// **'The youngest age cannot be above the oldest age.'**
  String get errorInvalidAgeRange;

  /// No description provided for @errorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please wait a moment and try again.'**
  String get errorTooManyRequests;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Administrators only'**
  String get loginSubtitle;

  /// No description provided for @loginEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginEmail;

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get loginEmailRequired;

  /// No description provided for @loginPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get loginPasswordRequired;

  /// No description provided for @loginWrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get loginWrongCredentials;

  /// No description provided for @loginNotAdmin.
  ///
  /// In en, this message translates to:
  /// **'This account is not an administrator.'**
  String get loginNotAdmin;

  /// No description provided for @tableEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show.'**
  String get tableEmpty;

  /// No description provided for @tablePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get tablePrevious;

  /// No description provided for @tableNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get tableNext;

  /// No description provided for @tablePage.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String tablePage(String page);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get statusDeactivated;

  /// No description provided for @statusHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get statusHidden;

  /// No description provided for @statusVisible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get statusVisible;

  /// No description provided for @statusShown.
  ///
  /// In en, this message translates to:
  /// **'Shown'**
  String get statusShown;

  /// No description provided for @statusOffered.
  ///
  /// In en, this message translates to:
  /// **'Offered'**
  String get statusOffered;

  /// No description provided for @statusOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get statusOff;

  /// No description provided for @colName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get colName;

  /// No description provided for @colEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get colEmail;

  /// No description provided for @colRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get colRole;

  /// No description provided for @colStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get colStatus;

  /// No description provided for @colLastSignIn.
  ///
  /// In en, this message translates to:
  /// **'Last sign-in'**
  String get colLastSignIn;

  /// No description provided for @colFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get colFamily;

  /// No description provided for @colParents.
  ///
  /// In en, this message translates to:
  /// **'Parents'**
  String get colParents;

  /// No description provided for @colChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get colChildren;

  /// No description provided for @colActiveMissions.
  ///
  /// In en, this message translates to:
  /// **'Active missions'**
  String get colActiveMissions;

  /// No description provided for @colCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get colCreated;

  /// No description provided for @colMission.
  ///
  /// In en, this message translates to:
  /// **'Mission'**
  String get colMission;

  /// No description provided for @colCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get colCategory;

  /// No description provided for @colChild.
  ///
  /// In en, this message translates to:
  /// **'Child'**
  String get colChild;

  /// No description provided for @colStarsXp.
  ///
  /// In en, this message translates to:
  /// **'Stars / XP'**
  String get colStarsXp;

  /// No description provided for @colDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get colDescription;

  /// No description provided for @colIcon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get colIcon;

  /// No description provided for @colReward.
  ///
  /// In en, this message translates to:
  /// **'Reward'**
  String get colReward;

  /// No description provided for @colType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get colType;

  /// No description provided for @colStarCost.
  ///
  /// In en, this message translates to:
  /// **'Star cost'**
  String get colStarCost;

  /// No description provided for @colStars.
  ///
  /// In en, this message translates to:
  /// **'Stars'**
  String get colStars;

  /// No description provided for @colRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get colRequested;

  /// No description provided for @colAges.
  ///
  /// In en, this message translates to:
  /// **'Ages'**
  String get colAges;

  /// No description provided for @colLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get colLink;

  /// No description provided for @colAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get colAmount;

  /// No description provided for @colWhen.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get colWhen;

  /// No description provided for @colAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get colAction;

  /// No description provided for @colItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get colItem;

  /// No description provided for @colAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get colAdmin;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get fieldName;

  /// No description provided for @fieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get fieldTitle;

  /// No description provided for @fieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get fieldDescription;

  /// No description provided for @fieldCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get fieldCategory;

  /// No description provided for @fieldLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get fieldLanguage;

  /// No description provided for @fieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get fieldType;

  /// No description provided for @fieldRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get fieldRole;

  /// No description provided for @fieldIconName.
  ///
  /// In en, this message translates to:
  /// **'Icon name'**
  String get fieldIconName;

  /// No description provided for @fieldIconNameHelp.
  ///
  /// In en, this message translates to:
  /// **'For example book-open or palette'**
  String get fieldIconNameHelp;

  /// No description provided for @dashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboardTitle;

  /// No description provided for @dashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A snapshot of how Bal Kavach is being used'**
  String get dashboardSubtitle;

  /// No description provided for @range7.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get range7;

  /// No description provided for @range30.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get range30;

  /// No description provided for @range90.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get range90;

  /// No description provided for @tileUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get tileUsers;

  /// No description provided for @tileFamilies.
  ///
  /// In en, this message translates to:
  /// **'Families'**
  String get tileFamilies;

  /// No description provided for @tileChildren.
  ///
  /// In en, this message translates to:
  /// **'Active children'**
  String get tileChildren;

  /// No description provided for @tileMissions.
  ///
  /// In en, this message translates to:
  /// **'Active missions'**
  String get tileMissions;

  /// No description provided for @tileVideos.
  ///
  /// In en, this message translates to:
  /// **'Published videos'**
  String get tileVideos;

  /// No description provided for @youtubeReviewsTitle.
  ///
  /// In en, this message translates to:
  /// **'YouTube video review'**
  String get youtubeReviewsTitle;

  /// No description provided for @youtubeReviewsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review candidates before they can appear in a child video feed.'**
  String get youtubeReviewsSubtitle;

  /// No description provided for @youtubeDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover candidates'**
  String get youtubeDiscover;

  /// No description provided for @youtubeRecheck.
  ///
  /// In en, this message translates to:
  /// **'Recheck approved videos'**
  String get youtubeRecheck;

  /// No description provided for @youtubeStatus.
  ///
  /// In en, this message translates to:
  /// **'Review status'**
  String get youtubeStatus;

  /// No description provided for @youtubeMaxResults.
  ///
  /// In en, this message translates to:
  /// **'Maximum results (1-50)'**
  String get youtubeMaxResults;

  /// No description provided for @youtubeAll.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get youtubeAll;

  /// No description provided for @youtubeTopic.
  ///
  /// In en, this message translates to:
  /// **'Curated topic'**
  String get youtubeTopic;

  /// No description provided for @youtubeOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open original video'**
  String get youtubeOpenSource;

  /// No description provided for @youtubeScreening.
  ///
  /// In en, this message translates to:
  /// **'Screening results'**
  String get youtubeScreening;

  /// No description provided for @youtubeAgeBand.
  ///
  /// In en, this message translates to:
  /// **'Age band'**
  String get youtubeAgeBand;

  /// No description provided for @youtubeRightsCleared.
  ///
  /// In en, this message translates to:
  /// **'I verified the rights and permission to embed this video.'**
  String get youtubeRightsCleared;

  /// No description provided for @youtubeRightsRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm the rights review before approval.'**
  String get youtubeRightsRequired;

  /// No description provided for @youtubeRejectReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for rejection'**
  String get youtubeRejectReason;

  /// No description provided for @youtubeReviewDetails.
  ///
  /// In en, this message translates to:
  /// **'Review details'**
  String get youtubeReviewDetails;

  /// No description provided for @youtubeActionApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get youtubeActionApprove;

  /// No description provided for @youtubeActionReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get youtubeActionReject;

  /// No description provided for @youtubeActionRevoke.
  ///
  /// In en, this message translates to:
  /// **'Withdraw'**
  String get youtubeActionRevoke;

  /// No description provided for @youtubeActionOpen.
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get youtubeActionOpen;

  /// No description provided for @youtubeActionFailed.
  ///
  /// In en, this message translates to:
  /// **'The action could not be completed.'**
  String get youtubeActionFailed;

  /// No description provided for @youtubeCandidateEmpty.
  ///
  /// In en, this message translates to:
  /// **'No candidates match this status.'**
  String get youtubeCandidateEmpty;

  /// No description provided for @tileRedemptions.
  ///
  /// In en, this message translates to:
  /// **'Pending reward requests'**
  String get tileRedemptions;

  /// No description provided for @systemTitle.
  ///
  /// In en, this message translates to:
  /// **'System status'**
  String get systemTitle;

  /// No description provided for @systemRefresh.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get systemRefresh;

  /// No description provided for @systemChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get systemChecking;

  /// No description provided for @systemApi.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get systemApi;

  /// No description provided for @systemDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get systemDatabase;

  /// No description provided for @systemUp.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get systemUp;

  /// No description provided for @systemDown.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get systemDown;

  /// No description provided for @activityTitle.
  ///
  /// In en, this message translates to:
  /// **'Last {days} days'**
  String activityTitle(String days);

  /// No description provided for @activityNewUsers.
  ///
  /// In en, this message translates to:
  /// **'New users: {n}'**
  String activityNewUsers(String n);

  /// No description provided for @activitySubmissions.
  ///
  /// In en, this message translates to:
  /// **'Submissions: {n}'**
  String activitySubmissions(String n);

  /// No description provided for @activityApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals: {n}'**
  String activityApprovals(String n);

  /// No description provided for @activityRejections.
  ///
  /// In en, this message translates to:
  /// **'Rejections: {n}'**
  String activityRejections(String n);

  /// No description provided for @activityRedemptions.
  ///
  /// In en, this message translates to:
  /// **'Reward requests: {n}'**
  String activityRedemptions(String n);

  /// No description provided for @activityChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily submissions'**
  String get activityChartTitle;

  /// No description provided for @activityDayTooltip.
  ///
  /// In en, this message translates to:
  /// **'{date}: {submitted} submitted, {approved} approved'**
  String activityDayTooltip(String date, String submitted, String approved);

  /// No description provided for @activityPeak.
  ///
  /// In en, this message translates to:
  /// **'Peak: {n}'**
  String activityPeak(String n);

  /// No description provided for @activityByStatus.
  ///
  /// In en, this message translates to:
  /// **'Reward requests by status'**
  String get activityByStatus;

  /// No description provided for @activityTopCategories.
  ///
  /// In en, this message translates to:
  /// **'Top categories (approved missions)'**
  String get activityTopCategories;

  /// No description provided for @activityNoApproved.
  ///
  /// In en, this message translates to:
  /// **'No approved missions yet.'**
  String get activityNoApproved;

  /// No description provided for @usersTitle.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersTitle;

  /// No description provided for @usersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Parents, children and administrators'**
  String get usersSubtitle;

  /// No description provided for @usersSearch.
  ///
  /// In en, this message translates to:
  /// **'Search name or email'**
  String get usersSearch;

  /// No description provided for @usersAllRoles.
  ///
  /// In en, this message translates to:
  /// **'All roles'**
  String get usersAllRoles;

  /// No description provided for @usersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No users match.'**
  String get usersEmpty;

  /// No description provided for @rolesParents.
  ///
  /// In en, this message translates to:
  /// **'Parents'**
  String get rolesParents;

  /// No description provided for @rolesChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get rolesChildren;

  /// No description provided for @rolesAdmins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get rolesAdmins;

  /// No description provided for @rolesStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get rolesStaff;

  /// No description provided for @userDeactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate account?'**
  String get userDeactivateTitle;

  /// No description provided for @userReactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate account?'**
  String get userReactivateTitle;

  /// No description provided for @userDeactivateBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be signed out and unable to sign in until reactivated.'**
  String userDeactivateBody(String name);

  /// No description provided for @userReactivateBody.
  ///
  /// In en, this message translates to:
  /// **'{name} will be able to sign in again.'**
  String userReactivateBody(String name);

  /// No description provided for @userDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Account deactivated'**
  String get userDeactivated;

  /// No description provided for @userReactivated.
  ///
  /// In en, this message translates to:
  /// **'Account reactivated'**
  String get userReactivated;

  /// No description provided for @userRolesTitle.
  ///
  /// In en, this message translates to:
  /// **'Roles for {name}'**
  String userRolesTitle(String name);

  /// No description provided for @userRolesRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove this role instead of assigning it'**
  String get userRolesRemove;

  /// No description provided for @userRoleAssigned.
  ///
  /// In en, this message translates to:
  /// **'Role assigned'**
  String get userRoleAssigned;

  /// No description provided for @userRoleRemoved.
  ///
  /// In en, this message translates to:
  /// **'Role removed'**
  String get userRoleRemoved;

  /// No description provided for @familiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Families'**
  String get familiesTitle;

  /// No description provided for @familiesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Households, their parents and children'**
  String get familiesSubtitle;

  /// No description provided for @familiesSearch.
  ///
  /// In en, this message translates to:
  /// **'Search family name'**
  String get familiesSearch;

  /// No description provided for @familiesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No families match.'**
  String get familiesEmpty;

  /// No description provided for @familyTimeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone: {zone}'**
  String familyTimeZone(String zone);

  /// No description provided for @familyParents.
  ///
  /// In en, this message translates to:
  /// **'Parents'**
  String get familyParents;

  /// No description provided for @familyChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get familyChildren;

  /// No description provided for @familyNoChildren.
  ///
  /// In en, this message translates to:
  /// **'No children yet.'**
  String get familyNoChildren;

  /// No description provided for @familyChildAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String familyChildAdded(String date);

  /// No description provided for @childDeactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate {name}?'**
  String childDeactivateTitle(String name);

  /// No description provided for @childReactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate {name}?'**
  String childReactivateTitle(String name);

  /// No description provided for @childDeactivateBody.
  ///
  /// In en, this message translates to:
  /// **'The child is signed out everywhere and cannot sign in until reactivated. Their history is kept.'**
  String get childDeactivateBody;

  /// No description provided for @childReactivateBody.
  ///
  /// In en, this message translates to:
  /// **'The child can be started in child mode again.'**
  String get childReactivateBody;

  /// No description provided for @childDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Child deactivated'**
  String get childDeactivated;

  /// No description provided for @childReactivated.
  ///
  /// In en, this message translates to:
  /// **'Child reactivated'**
  String get childReactivated;

  /// No description provided for @missionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get missionsTitle;

  /// No description provided for @missionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every family mission. Deactivating hides it from the child.'**
  String get missionsSubtitle;

  /// No description provided for @missionsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search title'**
  String get missionsSearch;

  /// No description provided for @missionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No missions match.'**
  String get missionsEmpty;

  /// No description provided for @missionAnyChild.
  ///
  /// In en, this message translates to:
  /// **'Any child'**
  String get missionAnyChild;

  /// No description provided for @missionDeactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate mission?'**
  String get missionDeactivateTitle;

  /// No description provided for @missionReactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Reactivate mission?'**
  String get missionReactivateTitle;

  /// No description provided for @missionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" in {family}.'**
  String missionConfirmBody(String title, String family);

  /// No description provided for @missionDeactivated.
  ///
  /// In en, this message translates to:
  /// **'Mission deactivated'**
  String get missionDeactivated;

  /// No description provided for @missionReactivated.
  ///
  /// In en, this message translates to:
  /// **'Mission reactivated'**
  String get missionReactivated;

  /// No description provided for @categoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Mission categories'**
  String get categoriesTitle;

  /// No description provided for @categoriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The groups parents pick from when creating a mission'**
  String get categoriesSubtitle;

  /// No description provided for @categoryNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get categoryNewTitle;

  /// No description provided for @categoryEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get categoryEditTitle;

  /// No description provided for @categoryCreated.
  ///
  /// In en, this message translates to:
  /// **'Category created'**
  String get categoryCreated;

  /// No description provided for @categorySaved.
  ///
  /// In en, this message translates to:
  /// **'Category saved'**
  String get categorySaved;

  /// No description provided for @categoryVisibleToParents.
  ///
  /// In en, this message translates to:
  /// **'Visible to parents'**
  String get categoryVisibleToParents;

  /// No description provided for @presetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Preset missions'**
  String get presetsTitle;

  /// No description provided for @presetsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ready-made ideas parents can start a mission from. The reward values are only suggestions.'**
  String get presetsSubtitle;

  /// No description provided for @presetNewButton.
  ///
  /// In en, this message translates to:
  /// **'New preset'**
  String get presetNewButton;

  /// No description provided for @presetNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New preset mission'**
  String get presetNewTitle;

  /// No description provided for @presetEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit preset mission'**
  String get presetEditTitle;

  /// No description provided for @presetCreated.
  ///
  /// In en, this message translates to:
  /// **'Preset created'**
  String get presetCreated;

  /// No description provided for @presetSaved.
  ///
  /// In en, this message translates to:
  /// **'Preset saved'**
  String get presetSaved;

  /// No description provided for @presetNoCategory.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get presetNoCategory;

  /// No description provided for @presetSuggestedStars.
  ///
  /// In en, this message translates to:
  /// **'Suggested stars'**
  String get presetSuggestedStars;

  /// No description provided for @presetSuggestedXp.
  ///
  /// In en, this message translates to:
  /// **'Suggested XP'**
  String get presetSuggestedXp;

  /// No description provided for @presetYoungestAge.
  ///
  /// In en, this message translates to:
  /// **'Youngest age'**
  String get presetYoungestAge;

  /// No description provided for @presetOldestAge.
  ///
  /// In en, this message translates to:
  /// **'Oldest age'**
  String get presetOldestAge;

  /// No description provided for @presetOffered.
  ///
  /// In en, this message translates to:
  /// **'Offered to parents'**
  String get presetOffered;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get rewardsTitle;

  /// No description provided for @rewardsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards created by families. Parents manage their own; hide one here if needed.'**
  String get rewardsSubtitle;

  /// No description provided for @rewardsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No rewards yet.'**
  String get rewardsEmpty;

  /// No description provided for @rewardHideTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide reward?'**
  String get rewardHideTitle;

  /// No description provided for @rewardShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Show reward?'**
  String get rewardShowTitle;

  /// No description provided for @rewardConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" from {family}.'**
  String rewardConfirmBody(String name, String family);

  /// No description provided for @rewardHidden.
  ///
  /// In en, this message translates to:
  /// **'Reward hidden'**
  String get rewardHidden;

  /// No description provided for @rewardShown.
  ///
  /// In en, this message translates to:
  /// **'Reward shown'**
  String get rewardShown;

  /// No description provided for @redemptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward requests'**
  String get redemptionsTitle;

  /// No description provided for @redemptionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read-only. Parents approve or decline their own children\'s requests.'**
  String get redemptionsSubtitle;

  /// No description provided for @redemptionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reward requests.'**
  String get redemptionsEmpty;

  /// No description provided for @redemptionAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get redemptionAllStatuses;

  /// No description provided for @redemptionPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get redemptionPending;

  /// No description provided for @redemptionApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get redemptionApproved;

  /// No description provided for @redemptionDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get redemptionDeclined;

  /// No description provided for @redemptionGiven.
  ///
  /// In en, this message translates to:
  /// **'Given'**
  String get redemptionGiven;

  /// No description provided for @redemptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get redemptionCancelled;

  /// No description provided for @contentTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning content'**
  String get contentTitle;

  /// No description provided for @contentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'What children see under Learn & Watch, in their language'**
  String get contentSubtitle;

  /// No description provided for @contentAddButton.
  ///
  /// In en, this message translates to:
  /// **'Add content'**
  String get contentAddButton;

  /// No description provided for @contentNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New content'**
  String get contentNewTitle;

  /// No description provided for @contentEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit content'**
  String get contentEditTitle;

  /// No description provided for @contentAdded.
  ///
  /// In en, this message translates to:
  /// **'Content added'**
  String get contentAdded;

  /// No description provided for @contentSaved.
  ///
  /// In en, this message translates to:
  /// **'Content saved'**
  String get contentSaved;

  /// No description provided for @contentEmpty.
  ///
  /// In en, this message translates to:
  /// **'No content yet.'**
  String get contentEmpty;

  /// No description provided for @contentLink.
  ///
  /// In en, this message translates to:
  /// **'Link (https)'**
  String get contentLink;

  /// No description provided for @contentLinkHelp.
  ///
  /// In en, this message translates to:
  /// **'Opens in the child\'s browser or video app'**
  String get contentLinkHelp;

  /// No description provided for @contentThumbnail.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail link (https)'**
  String get contentThumbnail;

  /// No description provided for @contentShownToChildren.
  ///
  /// In en, this message translates to:
  /// **'Shown to children'**
  String get contentShownToChildren;

  /// No description provided for @contentTypeLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get contentTypeLink;

  /// No description provided for @contentTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video link'**
  String get contentTypeVideo;

  /// No description provided for @contentTypeArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get contentTypeArticle;

  /// No description provided for @contentTypeDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get contentTypeDocument;

  /// No description provided for @contentTypeActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get contentTypeActivity;

  /// No description provided for @badgesTitle.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get badgesTitle;

  /// No description provided for @badgesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Awarded automatically when a child reaches the amount. Garden decorations unlock with the default badges.'**
  String get badgesSubtitle;

  /// No description provided for @badgeNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New badge'**
  String get badgeNewTitle;

  /// No description provided for @badgeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit badge'**
  String get badgeEditTitle;

  /// No description provided for @badgeCreated.
  ///
  /// In en, this message translates to:
  /// **'Badge created'**
  String get badgeCreated;

  /// No description provided for @badgeSaved.
  ///
  /// In en, this message translates to:
  /// **'Badge saved'**
  String get badgeSaved;

  /// No description provided for @badgeEarnedBy.
  ///
  /// In en, this message translates to:
  /// **'Earned by'**
  String get badgeEarnedBy;

  /// No description provided for @badgeAmountNeeded.
  ///
  /// In en, this message translates to:
  /// **'Amount needed'**
  String get badgeAmountNeeded;

  /// No description provided for @badgeCanBeEarned.
  ///
  /// In en, this message translates to:
  /// **'Can be earned'**
  String get badgeCanBeEarned;

  /// No description provided for @badgeCriteriaApprovedTasks.
  ///
  /// In en, this message translates to:
  /// **'Approved missions'**
  String get badgeCriteriaApprovedTasks;

  /// No description provided for @badgeCriteriaTotalStars.
  ///
  /// In en, this message translates to:
  /// **'Total stars'**
  String get badgeCriteriaTotalStars;

  /// No description provided for @badgeCriteriaTotalXp.
  ///
  /// In en, this message translates to:
  /// **'Total XP'**
  String get badgeCriteriaTotalXp;

  /// No description provided for @badgeCriteriaStreak.
  ///
  /// In en, this message translates to:
  /// **'Day streak'**
  String get badgeCriteriaStreak;

  /// No description provided for @auditTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditTitle;

  /// No description provided for @auditSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Who changed what, and when'**
  String get auditSubtitle;

  /// No description provided for @auditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No administrative changes recorded yet.'**
  String get auditEmpty;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read by the mobile app every time it starts'**
  String get settingsSubtitle;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Panel language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageHelp.
  ///
  /// In en, this message translates to:
  /// **'Changes this admin panel only. Content written by families or the server is not translated.'**
  String get settingsLanguageHelp;

  /// No description provided for @settingsConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Consent document version'**
  String get settingsConsentTitle;

  /// No description provided for @settingsConsentField.
  ///
  /// In en, this message translates to:
  /// **'Parent / guardian terms version'**
  String get settingsConsentField;

  /// No description provided for @settingsConsentHelp.
  ///
  /// In en, this message translates to:
  /// **'Changing this asks every parent to accept again on their next launch.'**
  String get settingsConsentHelp;

  /// No description provided for @settingsConsentConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask all parents to accept again?'**
  String get settingsConsentConfirmTitle;

  /// No description provided for @settingsConsentConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The new version \"{version}\" will be shown to every parent. Confirm that legal has approved the text.'**
  String settingsConsentConfirmBody(String version);

  /// No description provided for @settingsConsentPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish version'**
  String get settingsConsentPublish;

  /// No description provided for @settingsConsentPublished.
  ///
  /// In en, this message translates to:
  /// **'Consent version published'**
  String get settingsConsentPublished;

  /// No description provided for @settingsConsentSummary.
  ///
  /// In en, this message translates to:
  /// **'Parent / guardian terms: {version}'**
  String settingsConsentSummary(String version);

  /// No description provided for @settingsConsentDraft.
  ///
  /// In en, this message translates to:
  /// **'(built-in draft: legal must confirm)'**
  String get settingsConsentDraft;

  /// No description provided for @settingsMaintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintenance notice'**
  String get settingsMaintenanceTitle;

  /// No description provided for @settingsMaintenanceShow.
  ///
  /// In en, this message translates to:
  /// **'Show a banner in the app'**
  String get settingsMaintenanceShow;

  /// No description provided for @settingsMaintenanceMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get settingsMaintenanceMessage;

  /// No description provided for @settingsMaintenanceHelp.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for the default sentence'**
  String get settingsMaintenanceHelp;

  /// No description provided for @settingsMaintenanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Maintenance notice saved'**
  String get settingsMaintenanceSaved;

  /// No description provided for @settingsMaintenanceShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing: {message}'**
  String settingsMaintenanceShowing(String message);

  /// No description provided for @settingsMaintenanceDefault.
  ///
  /// In en, this message translates to:
  /// **'default message'**
  String get settingsMaintenanceDefault;
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
