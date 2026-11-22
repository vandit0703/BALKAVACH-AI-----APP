// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'बाल कवच एडमिन';

  @override
  String get navDashboard => 'डैशबोर्ड';

  @override
  String get navUsers => 'उपयोगकर्ता';

  @override
  String get navFamilies => 'परिवार';

  @override
  String get navMissions => 'मिशन';

  @override
  String get navCategories => 'श्रेणियाँ';

  @override
  String get navPresets => 'तैयार मिशन';

  @override
  String get navRewards => 'इनाम';

  @override
  String get navRedemptions => 'इनाम के अनुरोध';

  @override
  String get navContent => 'सीखने की सामग्री';

  @override
  String get navYoutubeReviews => 'YouTube समीक्षा';

  @override
  String get navBadges => 'बैज';

  @override
  String get navSettings => 'सेटिंग';

  @override
  String get navAudit => 'ऑडिट लॉग';

  @override
  String get navGroupOverview => 'अवलोकन';

  @override
  String get navGroupPeople => 'लोग';

  @override
  String get navGroupMissions => 'मिशन और इनाम';

  @override
  String get navGroupLearning => 'सीखना';

  @override
  String get navGroupSystem => 'सिस्टम';

  @override
  String get breadcrumbLabel => 'आप यहाँ हैं';

  @override
  String get noAccess => 'आपकी भूमिका में इस हिस्से तक पहुँच शामिल नहीं है।';

  @override
  String get accountTooltip => 'खाता';

  @override
  String accountRoles(String roles) {
    return 'भूमिकाएँ: $roles';
  }

  @override
  String get languageTooltip => 'भाषा';

  @override
  String get actionCancel => 'रद्द करें';

  @override
  String get actionConfirm => 'पुष्टि करें';

  @override
  String get actionSave => 'सहेजें';

  @override
  String get actionClose => 'बंद करें';

  @override
  String get actionSearch => 'खोजें';

  @override
  String get actionTryAgain => 'फिर से कोशिश करें';

  @override
  String get actionEdit => 'बदलें';

  @override
  String get actionDeactivate => 'निष्क्रिय करें';

  @override
  String get actionReactivate => 'फिर सक्रिय करें';

  @override
  String get actionSignIn => 'साइन इन करें';

  @override
  String get actionSignOut => 'साइन आउट करें';

  @override
  String get actionApply => 'लागू करें';

  @override
  String get actionChange => 'बदलें';

  @override
  String get actionDetails => 'विवरण';

  @override
  String get actionHide => 'छिपाएँ';

  @override
  String get actionShow => 'दिखाएँ';

  @override
  String get actionRoles => 'भूमिकाएँ';

  @override
  String get validationRequired => 'ज़रूरी';

  @override
  String validationMaxLength(String max) {
    return 'अधिकतम $max अक्षर';
  }

  @override
  String get validationWholeNumber => 'पूरी संख्या लिखें';

  @override
  String validationAtLeast(String min) {
    return 'कम से कम $min';
  }

  @override
  String validationAtMost(String max) {
    return 'अधिकतम $max';
  }

  @override
  String get validationHttps => 'पूरा https:// लिंक लिखें';

  @override
  String get errorGeneric => 'कुछ गलत हो गया। कृपया फिर से कोशिश करें।';

  @override
  String get errorNetwork => 'सर्वर से संपर्क नहीं हो पा रहा। कनेक्शन जाँचें।';

  @override
  String get errorForbidden => 'आपको यह करने की अनुमति नहीं है।';

  @override
  String get errorSessionExpired =>
      'आपका सत्र समाप्त हो गया है। कृपया फिर से साइन इन करें।';

  @override
  String get errorNotFound => 'यह आइटम अब मौजूद नहीं है।';

  @override
  String get errorConflict => 'यह पहले से मौजूद किसी चीज़ से मेल नहीं खाता।';

  @override
  String get errorValidation =>
      'कुछ मान सही नहीं हैं। उन्हें जाँचकर फिर कोशिश करें।';

  @override
  String get errorServer =>
      'सर्वर में समस्या आई। कृपया थोड़ी देर बाद फिर कोशिश करें।';

  @override
  String get errorLastSuperAdmin =>
      'आख़िरी सुपर एडमिन को हटाया या निष्क्रिय नहीं किया जा सकता।';

  @override
  String get errorEmailInUse => 'यह ईमेल पता पहले से इस्तेमाल में है।';

  @override
  String get errorUsernameInUse => 'यह यूज़रनेम पहले से इस्तेमाल में है।';

  @override
  String get errorCategoryConflict => 'इस नाम की श्रेणी पहले से मौजूद है।';

  @override
  String get errorInvalidSetting => 'यह सेटिंग मान सही नहीं है।';

  @override
  String get errorInvalidAgeRange =>
      'सबसे छोटी उम्र सबसे बड़ी उम्र से अधिक नहीं हो सकती।';

  @override
  String get errorTemplateIncomplete =>
      'इस मिशन के कुछ संस्करण अनुपलब्ध हैं। कौन-सी आयु और भाषा अनुपलब्ध है, यह देखने के लिए \'संस्करण देखें\' खोलें।';

  @override
  String get errorTooManyRequests =>
      'बहुत ज़्यादा अनुरोध हुए। कृपया थोड़ी देर रुककर फिर कोशिश करें।';

  @override
  String get loading => 'लोड हो रहा है';

  @override
  String get loginSubtitle => 'केवल एडमिन के लिए';

  @override
  String get loginEmail => 'ईमेल';

  @override
  String get loginPassword => 'पासवर्ड';

  @override
  String get loginEmailRequired => 'अपना ईमेल लिखें';

  @override
  String get loginPasswordRequired => 'अपना पासवर्ड लिखें';

  @override
  String get loginWrongCredentials => 'ईमेल या पासवर्ड गलत है।';

  @override
  String get loginNotAdmin => 'यह खाता एडमिन का नहीं है।';

  @override
  String get tableEmpty => 'दिखाने के लिए कुछ नहीं है।';

  @override
  String get tablePrevious => 'पिछला पृष्ठ';

  @override
  String get tableNext => 'अगला पृष्ठ';

  @override
  String tablePage(String page) {
    return 'पृष्ठ $page';
  }

  @override
  String get filterAll => 'सभी';

  @override
  String get statusActive => 'सक्रिय';

  @override
  String get statusDeactivated => 'निष्क्रिय';

  @override
  String get statusHidden => 'छिपा हुआ';

  @override
  String get statusVisible => 'दिखता है';

  @override
  String get statusShown => 'दिखाया गया';

  @override
  String get statusOffered => 'उपलब्ध';

  @override
  String get statusOff => 'बंद';

  @override
  String get colName => 'नाम';

  @override
  String get colEmail => 'ईमेल';

  @override
  String get colRole => 'भूमिका';

  @override
  String get colStatus => 'स्थिति';

  @override
  String get colLastSignIn => 'अंतिम साइन-इन';

  @override
  String get colFamily => 'परिवार';

  @override
  String get colParents => 'माता-पिता';

  @override
  String get colChildren => 'बच्चे';

  @override
  String get colActiveMissions => 'सक्रिय मिशन';

  @override
  String get colCreated => 'बनाया गया';

  @override
  String get colMission => 'मिशन';

  @override
  String get colCategory => 'श्रेणी';

  @override
  String get colChild => 'बच्चा';

  @override
  String get colStarsXp => 'स्टार / XP';

  @override
  String get colDescription => 'विवरण';

  @override
  String get colIcon => 'आइकन';

  @override
  String get colReward => 'इनाम';

  @override
  String get colType => 'प्रकार';

  @override
  String get colStarCost => 'स्टार की कीमत';

  @override
  String get colStars => 'स्टार';

  @override
  String get colRequested => 'अनुरोध का समय';

  @override
  String get colAges => 'उम्र';

  @override
  String get colLink => 'लिंक';

  @override
  String get colAmount => 'मात्रा';

  @override
  String get colWhen => 'कब';

  @override
  String get colAction => 'कार्रवाई';

  @override
  String get colItem => 'आइटम';

  @override
  String get colAdmin => 'एडमिन';

  @override
  String get fieldName => 'नाम';

  @override
  String get fieldTitle => 'शीर्षक';

  @override
  String get fieldDescription => 'विवरण';

  @override
  String get fieldCategory => 'श्रेणी';

  @override
  String get fieldLanguage => 'भाषा';

  @override
  String get fieldType => 'प्रकार';

  @override
  String get fieldRole => 'भूमिका';

  @override
  String get fieldIconName => 'आइकन का नाम';

  @override
  String get fieldIconNameHelp => 'जैसे book-open या palette';

  @override
  String get dashboardTitle => 'डैशबोर्ड';

  @override
  String get dashboardSubtitle => 'बाल कवच के उपयोग की एक झलक';

  @override
  String get range7 => '7 दिन';

  @override
  String get range30 => '30 दिन';

  @override
  String get range90 => '90 दिन';

  @override
  String get tileUsers => 'उपयोगकर्ता';

  @override
  String get tileFamilies => 'परिवार';

  @override
  String get tileChildren => 'सक्रिय बच्चे';

  @override
  String get tileMissions => 'सक्रिय मिशन';

  @override
  String get tileVideos => 'प्रकाशित वीडियो';

  @override
  String get youtubeReviewsTitle => 'YouTube वीडियो समीक्षा';

  @override
  String get youtubeReviewsSubtitle =>
      'चैनल खोजें, उन्हें विश्वसनीय बनाएँ और समीक्षा वाले वीडियो देखें।';

  @override
  String get youtubeDiscover => 'उम्मीदवार खोजें';

  @override
  String get youtubeDiscoverChannels => 'चैनल खोजें';

  @override
  String get youtubeTrustedChannels => 'विश्वसनीय चैनल';

  @override
  String get youtubeChannelSearchHint => 'YouTube चैनल खोजें';

  @override
  String get youtubeNoChannelsFound => 'कोई चैनल नहीं मिला।';

  @override
  String get youtubeNoTrustedChannels => 'अभी कोई चैनल विश्वसनीय नहीं है।';

  @override
  String get youtubeChannelTrusted => 'विश्वसनीय';

  @override
  String get youtubeChannelNotTrusted => 'विश्वसनीय नहीं';

  @override
  String get youtubeUntrustConfirm => 'क्या इस चैनल की खोज और प्रकाशन रोकें?';

  @override
  String get youtubeReviewQueue => 'समीक्षा के लिए वीडियो';

  @override
  String get youtubeNoReviewVideos => 'समीक्षा के लिए कोई वीडियो नहीं है।';

  @override
  String get youtubeRecheck => 'स्वीकृत वीडियो फिर जाँचें';

  @override
  String get youtubeStatus => 'समीक्षा स्थिति';

  @override
  String get youtubeMaxResults => 'अधिकतम परिणाम (1-50)';

  @override
  String get youtubeAll => 'सभी स्थितियाँ';

  @override
  String get youtubeTopic => 'चुना हुआ विषय';

  @override
  String get youtubeOpenSource => 'मूल वीडियो खोलें';

  @override
  String get youtubeScreening => 'जाँच के परिणाम';

  @override
  String get youtubeAgeBand => 'आयु वर्ग';

  @override
  String get youtubeVideoCategory => 'शैक्षिक श्रेणी';

  @override
  String get youtubeCategoriesRequired =>
      'चैनल या वीडियो स्वीकृत करने से पहले सक्रिय वीडियो श्रेणी बनाएँ।';

  @override
  String get youtubeRightsCleared =>
      'मैंने इस वीडियो को एम्बेड करने के अधिकार और अनुमति जाँची है।';

  @override
  String get youtubeRightsRequired =>
      'स्वीकृति से पहले अधिकारों की समीक्षा की पुष्टि करें।';

  @override
  String get youtubeRejectReason => 'अस्वीकृति का कारण';

  @override
  String get youtubeReviewDetails => 'समीक्षा विवरण';

  @override
  String get youtubeActionApprove => 'स्वीकृत करें';

  @override
  String get youtubeActionReject => 'अस्वीकार करें';

  @override
  String get youtubeActionRevoke => 'वापस लें';

  @override
  String get youtubeActionOpen => 'जाँचें';

  @override
  String get youtubeActionFailed => 'कार्रवाई पूरी नहीं हो सकी।';

  @override
  String get youtubeCandidateEmpty =>
      'इस स्थिति से मेल खाने वाले उम्मीदवार नहीं हैं।';

  @override
  String get tileRedemptions => 'लंबित इनाम अनुरोध';

  @override
  String get systemTitle => 'सिस्टम की स्थिति';

  @override
  String get systemRefresh => 'फिर से जाँचें';

  @override
  String get systemChecking => 'जाँच हो रही है…';

  @override
  String get systemApi => 'सर्वर';

  @override
  String get systemDatabase => 'डेटाबेस';

  @override
  String get systemUp => 'उपलब्ध';

  @override
  String get systemDown => 'अनुपलब्ध';

  @override
  String activityTitle(String days) {
    return 'पिछले $days दिन';
  }

  @override
  String activityNewUsers(String n) {
    return 'नए उपयोगकर्ता: $n';
  }

  @override
  String activitySubmissions(String n) {
    return 'जमा किए गए मिशन: $n';
  }

  @override
  String activityApprovals(String n) {
    return 'मंज़ूरियाँ: $n';
  }

  @override
  String activityRejections(String n) {
    return 'अस्वीकृतियाँ: $n';
  }

  @override
  String activityRedemptions(String n) {
    return 'इनाम अनुरोध: $n';
  }

  @override
  String get activityChartTitle => 'रोज़ जमा किए गए मिशन';

  @override
  String activityDayTooltip(String date, String submitted, String approved) {
    return '$date: $submitted जमा, $approved मंज़ूर';
  }

  @override
  String activityPeak(String n) {
    return 'सबसे अधिक: $n';
  }

  @override
  String get activityByStatus => 'स्थिति के अनुसार इनाम अनुरोध';

  @override
  String get activityTopCategories => 'शीर्ष श्रेणियाँ (मंज़ूर मिशन)';

  @override
  String get activityNoApproved => 'अभी कोई मंज़ूर मिशन नहीं है।';

  @override
  String get usersTitle => 'उपयोगकर्ता';

  @override
  String get usersSubtitle => 'माता-पिता, बच्चे और एडमिन';

  @override
  String get usersSearch => 'नाम या ईमेल खोजें';

  @override
  String get usersAllRoles => 'सभी भूमिकाएँ';

  @override
  String get usersEmpty => 'कोई उपयोगकर्ता नहीं मिला।';

  @override
  String get rolesParents => 'माता-पिता';

  @override
  String get rolesChildren => 'बच्चे';

  @override
  String get rolesAdmins => 'एडमिन';

  @override
  String get rolesStaff => 'स्टाफ़';

  @override
  String get userDeactivateTitle => 'खाता निष्क्रिय करें?';

  @override
  String get userReactivateTitle => 'खाता फिर सक्रिय करें?';

  @override
  String userDeactivateBody(String name) {
    return '$name साइन आउट हो जाएँगे और फिर से सक्रिय होने तक साइन इन नहीं कर पाएँगे।';
  }

  @override
  String userReactivateBody(String name) {
    return '$name फिर से साइन इन कर पाएँगे।';
  }

  @override
  String get userDeactivated => 'खाता निष्क्रिय किया गया';

  @override
  String get userReactivated => 'खाता फिर सक्रिय किया गया';

  @override
  String userRolesTitle(String name) {
    return '$name की भूमिकाएँ';
  }

  @override
  String get userRolesRemove => 'इस भूमिका को देने के बजाय हटाएँ';

  @override
  String get userRoleAssigned => 'भूमिका दी गई';

  @override
  String get userRoleRemoved => 'भूमिका हटाई गई';

  @override
  String get familiesTitle => 'परिवार';

  @override
  String get familiesSubtitle => 'परिवार, उनके माता-पिता और बच्चे';

  @override
  String get familiesSearch => 'परिवार का नाम खोजें';

  @override
  String get familiesEmpty => 'कोई परिवार नहीं मिला।';

  @override
  String familyTimeZone(String zone) {
    return 'समय क्षेत्र: $zone';
  }

  @override
  String get familyParents => 'माता-पिता';

  @override
  String get familyChildren => 'बच्चे';

  @override
  String get familyNoChildren => 'अभी कोई बच्चा नहीं है।';

  @override
  String familyChildAdded(String date) {
    return 'जोड़ा गया $date';
  }

  @override
  String childDeactivateTitle(String name) {
    return '$name को निष्क्रिय करें?';
  }

  @override
  String childReactivateTitle(String name) {
    return '$name को फिर सक्रिय करें?';
  }

  @override
  String get childDeactivateBody =>
      'बच्चा हर जगह साइन आउट हो जाएगा और फिर से सक्रिय होने तक साइन इन नहीं कर पाएगा। उसका इतिहास सुरक्षित रहेगा।';

  @override
  String get childReactivateBody =>
      'बच्चे को फिर से चाइल्ड मोड में शुरू किया जा सकेगा।';

  @override
  String get childDeactivated => 'बच्चा निष्क्रिय किया गया';

  @override
  String get childReactivated => 'बच्चा फिर सक्रिय किया गया';

  @override
  String get missionsTitle => 'मिशन';

  @override
  String get missionsSubtitle =>
      'हर परिवार के मिशन। निष्क्रिय करने पर वह बच्चे से छिप जाता है।';

  @override
  String get missionsSearch => 'शीर्षक खोजें';

  @override
  String get missionsEmpty => 'कोई मिशन नहीं मिला।';

  @override
  String get missionAnyChild => 'कोई भी बच्चा';

  @override
  String get missionDeactivateTitle => 'मिशन निष्क्रिय करें?';

  @override
  String get missionReactivateTitle => 'मिशन फिर सक्रिय करें?';

  @override
  String missionConfirmBody(String title, String family) {
    return '\"$title\" — $family में।';
  }

  @override
  String get missionDeactivated => 'मिशन निष्क्रिय किया गया';

  @override
  String get missionReactivated => 'मिशन फिर सक्रिय किया गया';

  @override
  String get missionCatalogComplete => 'सभी 9 आयु और भाषा संस्करण मौजूद हैं';

  @override
  String missionCatalogMissing(int count, String list) {
    return '9 में से $count संस्करण अनुपलब्ध: $list';
  }

  @override
  String missionCatalogCannotPublish(String list) {
    return 'अभी प्रकाशित नहीं किया जा सकता। अनुपलब्ध: $list';
  }

  @override
  String get missionCatalogViewVersions => 'संस्करण देखें';

  @override
  String get missionCatalogPreview =>
      'पूर्वावलोकन (बच्चा और समीक्षा करने वाले अभिभावक क्या देखते हैं)';

  @override
  String get missionEditEdit => 'यह संस्करण संपादित करें';

  @override
  String get missionEditTitle => 'मिशन संस्करण संपादित करें';

  @override
  String get missionEditObjective => 'बच्चा क्या सीखेगा';

  @override
  String get missionEditSteps => 'चरण';

  @override
  String get missionEditAddStep => 'चरण जोड़ें';

  @override
  String missionEditStepN(int number) {
    return 'चरण $number';
  }

  @override
  String get missionEditMoveUp => 'ऊपर ले जाएँ';

  @override
  String get missionEditMoveDown => 'नीचे ले जाएँ';

  @override
  String get missionEditRemove => 'हटाएँ';

  @override
  String get missionEditMaterials => 'सामग्री';

  @override
  String get missionEditAddMaterial => 'सामग्री जोड़ें';

  @override
  String get missionEditNothingNeeded => 'कुछ भी ज़रूरी नहीं';

  @override
  String get missionEditMinutes => 'मिनट';

  @override
  String get missionEditObserve => 'क्या देखना है';

  @override
  String get missionEditSubmit => 'बच्चे को क्या जमा करना है';

  @override
  String get missionEditSafety => 'सुरक्षा निर्देश';

  @override
  String get missionEditCompletion =>
      'पूर्णता की शर्तें (समीक्षक क्या जाँचता है)';

  @override
  String get missionEditCheck => 'जाँचें और पूर्वावलोकन देखें';

  @override
  String get missionEditPreview => 'बच्चा क्या देखेगा';

  @override
  String get missionEditErrors => 'प्रकाशित करने से पहले सुधारें';

  @override
  String get missionEditWarnings => 'बेहतर हो सकता है';

  @override
  String get missionEditReady => 'यह संस्करण प्रकाशित किया जा सकता है।';

  @override
  String get missionEditUnpublishNote =>
      'सहेजने पर यह मिशन तब तक अप्रकाशित रहेगा जब तक आप इसे फिर प्रकाशित न करें।';

  @override
  String get missionEditSave => 'सहेजें';

  @override
  String get missionEditSaved => 'सहेजा गया';

  @override
  String get missionPublishBlockedTitle => 'प्रकाशन रुका हुआ है';

  @override
  String get errorTemplateInstructionsIncomplete =>
      'यह मिशन अभी प्रकाशित नहीं हो सकता: कुछ संस्करणों में असली चरण या जमा करने की आवश्यकता नहीं है। क्या ठीक करना है, यह देखने के लिए संस्करण देखें खोलें।';

  @override
  String get missionIssueStepsMissing => 'कोई क्रमांकित चरण नहीं';

  @override
  String get missionIssueStepsTooFew => 'कम से कम दो चरण चाहिए';

  @override
  String get missionIssueStepsMalformed => 'एक चरण खाली है';

  @override
  String get missionIssuePlaceholder =>
      'सामान्य प्लेसहोल्डर पाठ, असली निर्देश नहीं';

  @override
  String get missionIssueMaterials =>
      'सामग्री नहीं बताई (न हो तो “कुछ भी ज़रूरी नहीं” लिखें)';

  @override
  String get missionIssueSubmission => 'क्या जमा करना है, यह नहीं लिखा';

  @override
  String get missionIssueSafety => 'सुरक्षा निर्देश नहीं हैं';

  @override
  String get missionIssueCompletion => 'पूर्णता की शर्तें नहीं हैं';

  @override
  String get missionIssueBandsIdentical => 'दो आयु वर्गों के चरण एक जैसे हैं';

  @override
  String get missionIssueObjective => '“आप क्या सीखेंगे” वाक्य नहीं है';

  @override
  String get missionIssueObservation => '“क्या देखना है” मार्गदर्शन नहीं है';

  @override
  String get missionCatalogVersionMissing => 'अनुपलब्ध';

  @override
  String missionCatalogAges(String range) {
    return 'आयु $range';
  }

  @override
  String missionCatalogMinutes(int count) {
    return '$count मिनट';
  }

  @override
  String get colVideoRequirement => 'ज़रूरी वीडियो';

  @override
  String missionCatalogMaterials(String items) {
    return 'सामग्री: $items';
  }

  @override
  String missionCatalogSafety(String text) {
    return 'सुरक्षा: $text';
  }

  @override
  String get missionHealthTitle => 'रोटेशन क्षमता';

  @override
  String missionHealthTheme(
    String theme,
    int eligible,
    int published,
    int total,
  ) {
    return '$theme: $eligible पात्र, $published प्रकाशित, कुल $total';
  }

  @override
  String missionHealthLow(int min, int shortfall) {
    return '$min से कम पात्र टेम्पलेट: मिशन दोहराए जाएँगे (और $shortfall प्रकाशित करें)';
  }

  @override
  String get missionHealthOk => 'रोटेशन के लिए पर्याप्त टेम्पलेट हैं';

  @override
  String missionHealthActivities(int distinct, int needed) {
    return '$needed में से $distinct गतिविधियाँ अलग होने की पुष्टि हुई';
  }

  @override
  String missionHealthActivitiesUnchecked(int count) {
    return '$count टेम्पलेट कैटलॉग स्रोत में नहीं हैं, इसलिए उनकी गतिविधि जाँची नहीं जा सकती';
  }

  @override
  String missionHealthTotals(
    int published,
    int unpublished,
    int incomplete,
    int total,
  ) {
    return 'कुल $total टेम्पलेट में से $published प्रकाशित, $unpublished अप्रकाशित, $incomplete अधूरे';
  }

  @override
  String missionHealthFallbacks(int count, int days) {
    return 'पिछले $days दिनों में $count कूलडाउन फ़ॉलबैक';
  }

  @override
  String missionCatalogShown(int count) {
    return '$count बार दिखाया गया';
  }

  @override
  String get categoriesTitle => 'मिशन की श्रेणियाँ';

  @override
  String get categoriesSubtitle =>
      'वे समूह जिनमें से माता-पिता मिशन बनाते समय चुनते हैं';

  @override
  String get categoryNewTitle => 'नई श्रेणी';

  @override
  String get categoryEditTitle => 'श्रेणी बदलें';

  @override
  String get categoryCreated => 'श्रेणी बनाई गई';

  @override
  String get categorySaved => 'श्रेणी सहेजी गई';

  @override
  String get categoryVisibleToParents => 'माता-पिता को दिखती है';

  @override
  String get presetsTitle => 'तैयार मिशन';

  @override
  String get presetsSubtitle =>
      'तैयार सुझाव जिनसे माता-पिता मिशन शुरू कर सकते हैं। इनाम के मान केवल सुझाव हैं।';

  @override
  String get presetNewButton => 'नया तैयार मिशन';

  @override
  String get presetNewTitle => 'नया तैयार मिशन';

  @override
  String get presetEditTitle => 'तैयार मिशन बदलें';

  @override
  String get presetCreated => 'तैयार मिशन बनाया गया';

  @override
  String get presetSaved => 'तैयार मिशन सहेजा गया';

  @override
  String get presetNoCategory => 'कोई श्रेणी नहीं';

  @override
  String get presetSuggestedStars => 'सुझाए गए स्टार';

  @override
  String get presetSuggestedXp => 'सुझाया गया XP';

  @override
  String get presetYoungestAge => 'सबसे छोटी उम्र';

  @override
  String get presetOldestAge => 'सबसे बड़ी उम्र';

  @override
  String get presetOffered => 'माता-पिता को उपलब्ध';

  @override
  String get rewardsTitle => 'इनाम';

  @override
  String get rewardsSubtitle =>
      'परिवारों द्वारा बनाए गए इनाम। माता-पिता अपने इनाम खुद सँभालते हैं; ज़रूरत हो तो यहाँ से कोई इनाम छिपाएँ।';

  @override
  String get rewardsEmpty => 'अभी कोई इनाम नहीं है।';

  @override
  String get rewardHideTitle => 'इनाम छिपाएँ?';

  @override
  String get rewardShowTitle => 'इनाम दिखाएँ?';

  @override
  String rewardConfirmBody(String name, String family) {
    return '\"$name\" — $family का।';
  }

  @override
  String get rewardHidden => 'इनाम छिपाया गया';

  @override
  String get rewardShown => 'इनाम दिखाया गया';

  @override
  String get redemptionsTitle => 'इनाम के अनुरोध';

  @override
  String get redemptionsSubtitle =>
      'केवल देखने के लिए। माता-पिता अपने बच्चों के अनुरोध खुद मंज़ूर या अस्वीकार करते हैं।';

  @override
  String get redemptionsEmpty => 'कोई इनाम अनुरोध नहीं है।';

  @override
  String get redemptionAllStatuses => 'सभी स्थितियाँ';

  @override
  String get redemptionPending => 'लंबित';

  @override
  String get redemptionApproved => 'मंज़ूर';

  @override
  String get redemptionDeclined => 'अस्वीकृत';

  @override
  String get redemptionGiven => 'दिया गया';

  @override
  String get redemptionCancelled => 'रद्द';

  @override
  String get contentTitle => 'सीखने की सामग्री';

  @override
  String get contentSubtitle =>
      'बच्चे \"सीखें और देखें\" में अपनी भाषा में क्या देखते हैं';

  @override
  String get contentAddButton => 'सामग्री जोड़ें';

  @override
  String get contentNewTitle => 'नई सामग्री';

  @override
  String get contentEditTitle => 'सामग्री बदलें';

  @override
  String get contentAdded => 'सामग्री जोड़ी गई';

  @override
  String get contentSaved => 'सामग्री सहेजी गई';

  @override
  String get contentEmpty => 'अभी कोई सामग्री नहीं है।';

  @override
  String get contentLink => 'लिंक (https)';

  @override
  String get contentLinkHelp => 'बच्चे के ब्राउज़र या वीडियो ऐप में खुलता है';

  @override
  String get contentThumbnail => 'थंबनेल लिंक (https)';

  @override
  String get contentShownToChildren => 'बच्चों को दिखाई जाती है';

  @override
  String get contentTypeLink => 'लिंक';

  @override
  String get contentTypeVideo => 'वीडियो लिंक';

  @override
  String get contentTypeArticle => 'लेख';

  @override
  String get contentTypeDocument => 'दस्तावेज़';

  @override
  String get contentTypeActivity => 'गतिविधि';

  @override
  String get badgesTitle => 'बैज';

  @override
  String get badgesSubtitle =>
      'बच्चे के तय मात्रा तक पहुँचने पर अपने आप मिलते हैं। गार्डन की सजावट डिफ़ॉल्ट बैज से खुलती है।';

  @override
  String get badgeNewTitle => 'नया बैज';

  @override
  String get badgeEditTitle => 'बैज बदलें';

  @override
  String get badgeCreated => 'बैज बनाया गया';

  @override
  String get badgeSaved => 'बैज सहेजा गया';

  @override
  String get badgeEarnedBy => 'ऐसे मिलता है';

  @override
  String get badgeAmountNeeded => 'ज़रूरी मात्रा';

  @override
  String get badgeCanBeEarned => 'कमाया जा सकता है';

  @override
  String get badgeCriteriaApprovedTasks => 'मंज़ूर मिशन';

  @override
  String get badgeCriteriaTotalStars => 'कुल स्टार';

  @override
  String get badgeCriteriaTotalXp => 'कुल XP';

  @override
  String get badgeCriteriaStreak => 'लगातार दिन';

  @override
  String get auditTitle => 'ऑडिट लॉग';

  @override
  String get auditSubtitle => 'किसने क्या और कब बदला';

  @override
  String get auditEmpty => 'अभी कोई प्रशासनिक बदलाव दर्ज नहीं हुआ है।';

  @override
  String get settingsTitle => 'सेटिंग';

  @override
  String get settingsSubtitle =>
      'मोबाइल ऐप हर बार शुरू होने पर इन्हें पढ़ता है';

  @override
  String get settingsLanguageTitle => 'पैनल की भाषा';

  @override
  String get settingsLanguageHelp =>
      'यह केवल इस एडमिन पैनल को बदलता है। परिवारों या सर्वर द्वारा लिखी सामग्री का अनुवाद नहीं होता।';

  @override
  String get settingsConsentTitle => 'सहमति दस्तावेज़ का संस्करण';

  @override
  String get settingsConsentField => 'माता-पिता / अभिभावक की शर्तों का संस्करण';

  @override
  String get settingsConsentHelp =>
      'इसे बदलने पर हर माता-पिता से अगली बार ऐप खोलने पर फिर सहमति ली जाएगी।';

  @override
  String get settingsConsentConfirmTitle =>
      'सभी माता-पिता से फिर सहमति माँगें?';

  @override
  String settingsConsentConfirmBody(String version) {
    return 'नया संस्करण \"$version\" हर माता-पिता को दिखाया जाएगा। पुष्टि करें कि कानूनी टीम ने पाठ को मंज़ूरी दे दी है।';
  }

  @override
  String get settingsConsentPublish => 'संस्करण प्रकाशित करें';

  @override
  String get settingsConsentPublished => 'सहमति संस्करण प्रकाशित हुआ';

  @override
  String settingsConsentSummary(String version) {
    return 'माता-पिता / अभिभावक की शर्तें: $version';
  }

  @override
  String get settingsConsentDraft => '(अंतर्निहित मसौदा: कानूनी पुष्टि ज़रूरी)';

  @override
  String get settingsMaintenanceTitle => 'रखरखाव की सूचना';

  @override
  String get settingsMaintenanceShow => 'ऐप में बैनर दिखाएँ';

  @override
  String get settingsMaintenanceMessage => 'संदेश';

  @override
  String get settingsMaintenanceHelp => 'डिफ़ॉल्ट वाक्य के लिए खाली छोड़ें';

  @override
  String get settingsMaintenanceSaved => 'रखरखाव की सूचना सहेजी गई';

  @override
  String settingsMaintenanceShowing(String message) {
    return 'दिखाया जा रहा है: $message';
  }

  @override
  String get settingsMaintenanceDefault => 'डिफ़ॉल्ट संदेश';

  @override
  String get youtubeTrustChannelTitle => 'YouTube चैनल पर भरोसा करें';

  @override
  String get youtubePreview => 'YouTube पर देखें';

  @override
  String get youtubeReevaluate => 'फिर से जाँचें';

  @override
  String get youtubeTrustChannel => 'चैनल पर भरोसा करें';

  @override
  String get youtubeUntrustChannel => 'चैनल का भरोसा हटाएँ';

  @override
  String get youtubePublishApproved => 'स्वीकृत अप्रकाशित वीडियो प्रकाशित करें';

  @override
  String get youtubeSource => 'स्वीकृति का स्रोत';

  @override
  String get youtubeAllOption => 'कोई भी';

  @override
  String get youtubeAutomatic => 'स्वचालित';

  @override
  String get youtubeManual => 'एडमिन द्वारा';

  @override
  String get youtubeAvailability => 'उपलब्धता';

  @override
  String get youtubePublished => 'प्रकाशित';

  @override
  String get youtubeUnpublished => 'अप्रकाशित';

  @override
  String get youtubeDiagnosticsTitle => 'पाइपलाइन निदान';

  @override
  String get youtubeDiagnosticsRefresh => 'निदान ताज़ा करें';

  @override
  String youtubeDiagnosticsUnavailable(Object error) {
    return 'निदान उपलब्ध नहीं: $error';
  }

  @override
  String youtubeQuarantineReason(Object reason, String count) {
    return 'क्वारंटीन: $reason ($count)';
  }

  @override
  String youtubeBlockedReason(Object reason, String count) {
    return 'रुका हुआ: $reason ($count)';
  }

  @override
  String youtubeRights(String status) {
    return 'अधिकार: $status';
  }

  @override
  String get youtubeSummaryTitle => 'समीक्षा सारांश';

  @override
  String get youtubeCountApproved => 'स्वीकृत';

  @override
  String get youtubeCountPending => 'व्यक्ति की प्रतीक्षा में';

  @override
  String get youtubeCountQuarantined => 'क्वारंटीन';

  @override
  String get youtubeCountRejected => 'अस्वीकृत';

  @override
  String get youtubeCountPublished => 'ऐप में प्रकाशित';

  @override
  String youtubeApprovedBySource(String automatic, String manual) {
    return 'स्वचालित रूप से स्वीकृत: $automatic · एडमिन द्वारा: $manual';
  }

  @override
  String get youtubeAutoNote =>
      'जो वीडियो सभी स्वचालित जाँच पास करते हैं, वे एडमिन के बिना स्वीकृत और प्रकाशित हो जाते हैं। केवल वही वीडियो प्रतीक्षा सूची में रहते हैं जिन्हें किसी व्यक्ति की ज़रूरत है।';

  @override
  String get youtubeAutoReview => 'प्रतीक्षारत वीडियो जाँचें';

  @override
  String youtubeAutoReviewResult(
    String checked,
    String approved,
    String waiting,
    String quarantined,
  ) {
    return '$checked जाँचे गए: $approved स्वचालित रूप से स्वीकृत, $waiting को अब भी व्यक्ति की ज़रूरत, $quarantined क्वारंटीन।';
  }

  @override
  String youtubeAutoReviewRetry(String count) {
    return '$count वीडियो के लिए YouTube तक नहीं पहुँचा जा सका। कुछ नहीं बदला; बाद में फिर कोशिश करें।';
  }

  @override
  String get youtubeDecisionColumn => 'निर्णय';

  @override
  String get youtubeDecisionAutomatic => 'स्वचालित रूप से स्वीकृत';

  @override
  String get youtubeDecisionManual => 'एडमिन द्वारा स्वीकृत';

  @override
  String get youtubeDecisionWaiting => 'प्रतीक्षा में';

  @override
  String youtubeReasonLabel(Object reason) {
    return 'कारण: $reason';
  }

  @override
  String youtubeFreshness(String oldest, String hours, String stale) {
    return 'सबसे पुराना सत्यापन: $oldest · $hours घंटे की सीमा पार कर चुके स्वीकृत वीडियो (बच्चों से छिपे): $stale';
  }

  @override
  String get youtubeChannelAll => 'सभी';

  @override
  String get youtubeChannelDetails => 'चैनल का विवरण';

  @override
  String get youtubeChannelCounts => 'मिले वीडियो';

  @override
  String get youtubeChannelDisc => 'खोजे गए';

  @override
  String get youtubeChannelAppr => 'स्वीकृत';

  @override
  String get youtubeChannelPend => 'समीक्षा की प्रतीक्षा में';

  @override
  String get youtubeChannelQuar => 'क्वारंटीन';

  @override
  String get youtubeChannelRej => 'अस्वीकृत';

  @override
  String get youtubeChannelShorts => 'लाइव शॉर्ट्स';

  @override
  String get youtubeChannelReg => 'लाइव वीडियो';

  @override
  String get youtubeChannelLastDisc => 'पिछली खोज';

  @override
  String get youtubeChannelLastVer => 'पिछली दोबारा जाँच';

  @override
  String get youtubeChannelHist => 'इतिहास';

  @override
  String get youtubeChannelNoHist => 'अभी कोई बदलाव दर्ज नहीं है।';

  @override
  String get youtubeChannelEvT => 'चैनल को भरोसेमंद बनाया गया';

  @override
  String get youtubeChannelEvU => 'चैनल का भरोसा हटाया गया';

  @override
  String get youtubeChannelFail => 'चैनल का विवरण लोड नहीं हो सका।';

  @override
  String get youtubeChannelNote =>
      'चैनल को हटाए बिना रोकना और सिंक स्थिति की सुविधा योजना में है और इसके लिए सर्वर अपडेट चाहिए।';

  @override
  String get youtubeChannelAge => 'आयु';

  @override
  String get youtubeChannelLang => 'भाषा';

  @override
  String get youtubeChannelRights => 'अधिकार';

  @override
  String get youtubeChannelNever => 'कभी नहीं';

  @override
  String get youtubeChannelActive => 'सक्रिय';

  @override
  String get youtubeChannelRemoved => 'हटाए गए';
}
