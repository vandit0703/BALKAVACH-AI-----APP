// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Gujarati (`gu`).
class AppLocalizationsGu extends AppLocalizations {
  AppLocalizationsGu([String locale = 'gu']) : super(locale);

  @override
  String get appName => 'બાલ કવચ એડમિન';

  @override
  String get navDashboard => 'ડેશબોર્ડ';

  @override
  String get navUsers => 'વપરાશકર્તાઓ';

  @override
  String get navFamilies => 'પરિવારો';

  @override
  String get navMissions => 'મિશન';

  @override
  String get navCategories => 'શ્રેણીઓ';

  @override
  String get navPresets => 'તૈયાર મિશન';

  @override
  String get navRewards => 'ઇનામ';

  @override
  String get navRedemptions => 'ઇનામની વિનંતીઓ';

  @override
  String get navContent => 'શીખવાની સામગ્રી';

  @override
  String get navYoutubeReviews => 'YouTube સમીક્ષા';

  @override
  String get navBadges => 'બેજ';

  @override
  String get navSettings => 'સેટિંગ';

  @override
  String get navAudit => 'ઓડિટ લૉગ';

  @override
  String get navGroupOverview => 'ઝાંખી';

  @override
  String get navGroupPeople => 'લોકો';

  @override
  String get navGroupMissions => 'મિશન અને ઇનામ';

  @override
  String get navGroupLearning => 'શીખવું';

  @override
  String get navGroupSystem => 'સિસ્ટમ';

  @override
  String get breadcrumbLabel => 'તમે અહીં છો';

  @override
  String get noAccess => 'તમારી ભૂમિકામાં આ વિભાગની ઍક્સેસ શામેલ નથી.';

  @override
  String get accountTooltip => 'ખાતું';

  @override
  String accountRoles(String roles) {
    return 'ભૂમિકાઓ: $roles';
  }

  @override
  String get languageTooltip => 'ભાષા';

  @override
  String get actionCancel => 'રદ કરો';

  @override
  String get actionConfirm => 'પુષ્ટિ કરો';

  @override
  String get actionSave => 'સાચવો';

  @override
  String get actionClose => 'બંધ કરો';

  @override
  String get actionSearch => 'શોધો';

  @override
  String get actionTryAgain => 'ફરી પ્રયાસ કરો';

  @override
  String get actionEdit => 'ફેરફાર';

  @override
  String get actionDeactivate => 'નિષ્ક્રિય કરો';

  @override
  String get actionReactivate => 'ફરી સક્રિય કરો';

  @override
  String get actionSignIn => 'સાઇન ઇન કરો';

  @override
  String get actionSignOut => 'સાઇન આઉટ કરો';

  @override
  String get actionApply => 'લાગુ કરો';

  @override
  String get actionChange => 'બદલો';

  @override
  String get actionDetails => 'વિગતો';

  @override
  String get actionHide => 'છુપાવો';

  @override
  String get actionShow => 'બતાવો';

  @override
  String get actionRoles => 'ભૂમિકાઓ';

  @override
  String get validationRequired => 'જરૂરી';

  @override
  String validationMaxLength(String max) {
    return 'વધુમાં વધુ $max અક્ષર';
  }

  @override
  String get validationWholeNumber => 'પૂર્ણ સંખ્યા લખો';

  @override
  String validationAtLeast(String min) {
    return 'ઓછામાં ઓછું $min';
  }

  @override
  String validationAtMost(String max) {
    return 'વધુમાં વધુ $max';
  }

  @override
  String get validationHttps => 'પૂરી https:// લિંક લખો';

  @override
  String get errorGeneric => 'કંઈક ખોટું થયું. કૃપા કરી ફરી પ્રયાસ કરો.';

  @override
  String get errorNetwork => 'સર્વર સુધી પહોંચી શકાતું નથી. કનેક્શન તપાસો.';

  @override
  String get errorForbidden => 'તમને આ કરવાની પરવાનગી નથી.';

  @override
  String get errorSessionExpired =>
      'તમારું સત્ર સમાપ્ત થયું છે. કૃપા કરી ફરી સાઇન ઇન કરો.';

  @override
  String get errorNotFound => 'આ આઇટમ હવે અસ્તિત્વમાં નથી.';

  @override
  String get errorConflict => 'આ પહેલેથી અસ્તિત્વમાં રહેલી બાબત સાથે અથડાય છે.';

  @override
  String get errorValidation =>
      'કેટલાક મૂલ્યો માન્ય નથી. તપાસીને ફરી પ્રયાસ કરો.';

  @override
  String get errorServer =>
      'સર્વરમાં સમસ્યા આવી. કૃપા કરી થોડી વારમાં ફરી પ્રયાસ કરો.';

  @override
  String get errorLastSuperAdmin =>
      'છેલ્લા સુપર એડમિનને દૂર કે નિષ્ક્રિય કરી શકાતા નથી.';

  @override
  String get errorEmailInUse => 'આ ઇમેઇલ સરનામું પહેલેથી વપરાયેલું છે.';

  @override
  String get errorUsernameInUse => 'આ યુઝરનેમ પહેલેથી વપરાયેલું છે.';

  @override
  String get errorCategoryConflict => 'આ નામની શ્રેણી પહેલેથી અસ્તિત્વમાં છે.';

  @override
  String get errorInvalidSetting => 'આ સેટિંગ મૂલ્ય માન્ય નથી.';

  @override
  String get errorInvalidAgeRange =>
      'સૌથી નાની ઉંમર સૌથી મોટી ઉંમર કરતાં વધુ ન હોઈ શકે.';

  @override
  String get errorTooManyRequests =>
      'ઘણી બધી વિનંતીઓ થઈ. કૃપા કરી થોડી વાર રાહ જોઈને ફરી પ્રયાસ કરો.';

  @override
  String get loading => 'લોડ થઈ રહ્યું છે';

  @override
  String get loginSubtitle => 'ફક્ત એડમિન માટે';

  @override
  String get loginEmail => 'ઇમેઇલ';

  @override
  String get loginPassword => 'પાસવર્ડ';

  @override
  String get loginEmailRequired => 'તમારો ઇમેઇલ લખો';

  @override
  String get loginPasswordRequired => 'તમારો પાસવર્ડ લખો';

  @override
  String get loginWrongCredentials => 'ઇમેઇલ કે પાસવર્ડ ખોટો છે.';

  @override
  String get loginNotAdmin => 'આ ખાતું એડમિનનું નથી.';

  @override
  String get tableEmpty => 'બતાવવા માટે કંઈ નથી.';

  @override
  String get tablePrevious => 'પાછલું પૃષ્ઠ';

  @override
  String get tableNext => 'આગલું પૃષ્ઠ';

  @override
  String tablePage(String page) {
    return 'પૃષ્ઠ $page';
  }

  @override
  String get filterAll => 'બધા';

  @override
  String get statusActive => 'સક્રિય';

  @override
  String get statusDeactivated => 'નિષ્ક્રિય';

  @override
  String get statusHidden => 'છુપાયેલ';

  @override
  String get statusVisible => 'દેખાય છે';

  @override
  String get statusShown => 'બતાવેલ';

  @override
  String get statusOffered => 'ઉપલબ્ધ';

  @override
  String get statusOff => 'બંધ';

  @override
  String get colName => 'નામ';

  @override
  String get colEmail => 'ઇમેઇલ';

  @override
  String get colRole => 'ભૂમિકા';

  @override
  String get colStatus => 'સ્થિતિ';

  @override
  String get colLastSignIn => 'છેલ્લું સાઇન-ઇન';

  @override
  String get colFamily => 'પરિવાર';

  @override
  String get colParents => 'માતા-પિતા';

  @override
  String get colChildren => 'બાળકો';

  @override
  String get colActiveMissions => 'સક્રિય મિશન';

  @override
  String get colCreated => 'બનાવેલ';

  @override
  String get colMission => 'મિશન';

  @override
  String get colCategory => 'શ્રેણી';

  @override
  String get colChild => 'બાળક';

  @override
  String get colStarsXp => 'સ્ટાર / XP';

  @override
  String get colDescription => 'વર્ણન';

  @override
  String get colIcon => 'આઇકન';

  @override
  String get colReward => 'ઇનામ';

  @override
  String get colType => 'પ્રકાર';

  @override
  String get colStarCost => 'સ્ટારની કિંમત';

  @override
  String get colStars => 'સ્ટાર';

  @override
  String get colRequested => 'વિનંતીનો સમય';

  @override
  String get colAges => 'ઉંમર';

  @override
  String get colLink => 'લિંક';

  @override
  String get colAmount => 'જથ્થો';

  @override
  String get colWhen => 'ક્યારે';

  @override
  String get colAction => 'કાર્યવાહી';

  @override
  String get colItem => 'આઇટમ';

  @override
  String get colAdmin => 'એડમિન';

  @override
  String get fieldName => 'નામ';

  @override
  String get fieldTitle => 'શીર્ષક';

  @override
  String get fieldDescription => 'વર્ણન';

  @override
  String get fieldCategory => 'શ્રેણી';

  @override
  String get fieldLanguage => 'ભાષા';

  @override
  String get fieldType => 'પ્રકાર';

  @override
  String get fieldRole => 'ભૂમિકા';

  @override
  String get fieldIconName => 'આઇકનનું નામ';

  @override
  String get fieldIconNameHelp => 'દા.ત. book-open અથવા palette';

  @override
  String get dashboardTitle => 'ડેશબોર્ડ';

  @override
  String get dashboardSubtitle => 'બાલ કવચ કેવી રીતે વપરાય છે તેની ઝલક';

  @override
  String get range7 => '7 દિવસ';

  @override
  String get range30 => '30 દિવસ';

  @override
  String get range90 => '90 દિવસ';

  @override
  String get tileUsers => 'વપરાશકર્તાઓ';

  @override
  String get tileFamilies => 'પરિવારો';

  @override
  String get tileChildren => 'સક્રિય બાળકો';

  @override
  String get tileMissions => 'સક્રિય મિશન';

  @override
  String get tileVideos => 'પ્રકાશિત વીડિયો';

  @override
  String get youtubeReviewsTitle => 'YouTube વીડિયો સમીક્ષા';

  @override
  String get youtubeReviewsSubtitle =>
      'બાળકોની વીડિયો સૂચિમાં દેખાય તે પહેલાં ઉમેદવારોની સમીક્ષા કરો.';

  @override
  String get youtubeDiscover => 'ઉમેદવારો શોધો';

  @override
  String get youtubeRecheck => 'મંજૂર વીડિયોની ફરી તપાસો';

  @override
  String get youtubeStatus => 'સમીક્ષા સ્થિતિ';

  @override
  String get youtubeMaxResults => 'મહત્તમ પરિણામો (1-50)';

  @override
  String get youtubeAll => 'બધી સ્થિતિઓ';

  @override
  String get youtubeTopic => 'પસંદ કરેલો વિષય';

  @override
  String get youtubeOpenSource => 'મૂળ વીડિયો ખોલો';

  @override
  String get youtubeScreening => 'તપાસના પરિણામો';

  @override
  String get youtubeAgeBand => 'ઉંમર જૂથ';

  @override
  String get youtubeRightsCleared =>
      'મેં આ વીડિયોને એમ્બેડ કરવાના અધિકારો અને પરવાનગી તપાસી છે.';

  @override
  String get youtubeRightsRequired =>
      'મંજૂરી પહેલાં અધિકારોની સમીક્ષાની પુષ્ટિ કરો.';

  @override
  String get youtubeRejectReason => 'નકારવાનું કારણ';

  @override
  String get youtubeReviewDetails => 'સમીક્ષાની વિગતો';

  @override
  String get youtubeActionApprove => 'મંજૂર કરો';

  @override
  String get youtubeActionReject => 'નકારો';

  @override
  String get youtubeActionRevoke => 'પાછું ખેંચો';

  @override
  String get youtubeActionOpen => 'તપાસો';

  @override
  String get youtubeActionFailed => 'ક્રિયા પૂર્ણ થઈ શકી નથી.';

  @override
  String get youtubeCandidateEmpty => 'આ સ્થિતિ સાથે મેળ ખાતા ઉમેદવારો નથી.';

  @override
  String get tileRedemptions => 'બાકી ઇનામ વિનંતીઓ';

  @override
  String get systemTitle => 'સિસ્ટમની સ્થિતિ';

  @override
  String get systemRefresh => 'ફરી તપાસો';

  @override
  String get systemChecking => 'તપાસ ચાલુ છે…';

  @override
  String get systemApi => 'સર્વર';

  @override
  String get systemDatabase => 'ડેટાબેઝ';

  @override
  String get systemUp => 'ઉપલબ્ધ';

  @override
  String get systemDown => 'અનુપલબ્ધ';

  @override
  String activityTitle(String days) {
    return 'છેલ્લા $days દિવસ';
  }

  @override
  String activityNewUsers(String n) {
    return 'નવા વપરાશકર્તાઓ: $n';
  }

  @override
  String activitySubmissions(String n) {
    return 'સબમિટ કરેલા મિશન: $n';
  }

  @override
  String activityApprovals(String n) {
    return 'મંજૂરીઓ: $n';
  }

  @override
  String activityRejections(String n) {
    return 'નામંજૂરીઓ: $n';
  }

  @override
  String activityRedemptions(String n) {
    return 'ઇનામ વિનંતીઓ: $n';
  }

  @override
  String get activityChartTitle => 'દૈનિક સબમિશન';

  @override
  String activityDayTooltip(String date, String submitted, String approved) {
    return '$date: $submitted સબમિટ, $approved મંજૂર';
  }

  @override
  String activityPeak(String n) {
    return 'સૌથી વધુ: $n';
  }

  @override
  String get activityByStatus => 'સ્થિતિ મુજબ ઇનામ વિનંતીઓ';

  @override
  String get activityTopCategories => 'ટોચની શ્રેણીઓ (મંજૂર મિશન)';

  @override
  String get activityNoApproved => 'હજી કોઈ મંજૂર મિશન નથી.';

  @override
  String get usersTitle => 'વપરાશકર્તાઓ';

  @override
  String get usersSubtitle => 'માતા-પિતા, બાળકો અને એડમિન';

  @override
  String get usersSearch => 'નામ કે ઇમેઇલ શોધો';

  @override
  String get usersAllRoles => 'બધી ભૂમિકાઓ';

  @override
  String get usersEmpty => 'કોઈ વપરાશકર્તા મળ્યા નથી.';

  @override
  String get rolesParents => 'માતા-પિતા';

  @override
  String get rolesChildren => 'બાળકો';

  @override
  String get rolesAdmins => 'એડમિન';

  @override
  String get rolesStaff => 'સ્ટાફ';

  @override
  String get userDeactivateTitle => 'ખાતું નિષ્ક્રિય કરવું?';

  @override
  String get userReactivateTitle => 'ખાતું ફરી સક્રિય કરવું?';

  @override
  String userDeactivateBody(String name) {
    return '$name સાઇન આઉટ થઈ જશે અને ફરી સક્રિય ન થાય ત્યાં સુધી સાઇન ઇન કરી શકશે નહીં.';
  }

  @override
  String userReactivateBody(String name) {
    return '$name ફરી સાઇન ઇન કરી શકશે.';
  }

  @override
  String get userDeactivated => 'ખાતું નિષ્ક્રિય કર્યું';

  @override
  String get userReactivated => 'ખાતું ફરી સક્રિય કર્યું';

  @override
  String userRolesTitle(String name) {
    return '$name ની ભૂમિકાઓ';
  }

  @override
  String get userRolesRemove => 'આ ભૂમિકા આપવાને બદલે દૂર કરો';

  @override
  String get userRoleAssigned => 'ભૂમિકા આપવામાં આવી';

  @override
  String get userRoleRemoved => 'ભૂમિકા દૂર કરવામાં આવી';

  @override
  String get familiesTitle => 'પરિવારો';

  @override
  String get familiesSubtitle => 'પરિવારો, તેમના માતા-પિતા અને બાળકો';

  @override
  String get familiesSearch => 'પરિવારનું નામ શોધો';

  @override
  String get familiesEmpty => 'કોઈ પરિવાર મળ્યો નથી.';

  @override
  String familyTimeZone(String zone) {
    return 'સમય ક્ષેત્ર: $zone';
  }

  @override
  String get familyParents => 'માતા-પિતા';

  @override
  String get familyChildren => 'બાળકો';

  @override
  String get familyNoChildren => 'હજી કોઈ બાળક નથી.';

  @override
  String familyChildAdded(String date) {
    return 'ઉમેર્યું $date';
  }

  @override
  String childDeactivateTitle(String name) {
    return '$name ને નિષ્ક્રિય કરવું?';
  }

  @override
  String childReactivateTitle(String name) {
    return '$name ને ફરી સક્રિય કરવું?';
  }

  @override
  String get childDeactivateBody =>
      'બાળક બધે સાઇન આઉટ થઈ જશે અને ફરી સક્રિય ન થાય ત્યાં સુધી સાઇન ઇન કરી શકશે નહીં. તેનો ઇતિહાસ સચવાયેલો રહેશે.';

  @override
  String get childReactivateBody => 'બાળકને ફરી ચાઇલ્ડ મોડમાં શરૂ કરી શકાશે.';

  @override
  String get childDeactivated => 'બાળક નિષ્ક્રિય કર્યું';

  @override
  String get childReactivated => 'બાળક ફરી સક્રિય કર્યું';

  @override
  String get missionsTitle => 'મિશન';

  @override
  String get missionsSubtitle =>
      'દરેક પરિવારના મિશન. નિષ્ક્રિય કરવાથી તે બાળકથી છુપાઈ જાય છે.';

  @override
  String get missionsSearch => 'શીર્ષક શોધો';

  @override
  String get missionsEmpty => 'કોઈ મિશન મળ્યું નથી.';

  @override
  String get missionAnyChild => 'કોઈપણ બાળક';

  @override
  String get missionDeactivateTitle => 'મિશન નિષ્ક્રિય કરવું?';

  @override
  String get missionReactivateTitle => 'મિશન ફરી સક્રિય કરવું?';

  @override
  String missionConfirmBody(String title, String family) {
    return '\"$title\" — $family માં.';
  }

  @override
  String get missionDeactivated => 'મિશન નિષ્ક્રિય કર્યું';

  @override
  String get missionReactivated => 'મિશન ફરી સક્રિય કર્યું';

  @override
  String get categoriesTitle => 'મિશનની શ્રેણીઓ';

  @override
  String get categoriesSubtitle =>
      'જે જૂથોમાંથી માતા-પિતા મિશન બનાવતી વખતે પસંદ કરે છે';

  @override
  String get categoryNewTitle => 'નવી શ્રેણી';

  @override
  String get categoryEditTitle => 'શ્રેણીમાં ફેરફાર કરો';

  @override
  String get categoryCreated => 'શ્રેણી બનાવી';

  @override
  String get categorySaved => 'શ્રેણી સાચવી';

  @override
  String get categoryVisibleToParents => 'માતા-પિતાને દેખાય છે';

  @override
  String get presetsTitle => 'તૈયાર મિશન';

  @override
  String get presetsSubtitle =>
      'તૈયાર સૂચનો જેમાંથી માતા-પિતા મિશન શરૂ કરી શકે છે. ઇનામના મૂલ્યો ફક્ત સૂચનો છે.';

  @override
  String get presetNewButton => 'નવું તૈયાર મિશન';

  @override
  String get presetNewTitle => 'નવું તૈયાર મિશન';

  @override
  String get presetEditTitle => 'તૈયાર મિશનમાં ફેરફાર કરો';

  @override
  String get presetCreated => 'તૈયાર મિશન બનાવ્યું';

  @override
  String get presetSaved => 'તૈયાર મિશન સાચવ્યું';

  @override
  String get presetNoCategory => 'કોઈ શ્રેણી નહીં';

  @override
  String get presetSuggestedStars => 'સૂચવેલા સ્ટાર';

  @override
  String get presetSuggestedXp => 'સૂચવેલ XP';

  @override
  String get presetYoungestAge => 'સૌથી નાની ઉંમર';

  @override
  String get presetOldestAge => 'સૌથી મોટી ઉંમર';

  @override
  String get presetOffered => 'માતા-પિતાને ઉપલબ્ધ';

  @override
  String get rewardsTitle => 'ઇનામ';

  @override
  String get rewardsSubtitle =>
      'પરિવારોએ બનાવેલા ઇનામ. માતા-પિતા પોતાના ઇનામ સંભાળે છે; જરૂર પડે તો અહીંથી કોઈ ઇનામ છુપાવો.';

  @override
  String get rewardsEmpty => 'હજી કોઈ ઇનામ નથી.';

  @override
  String get rewardHideTitle => 'ઇનામ છુપાવવું?';

  @override
  String get rewardShowTitle => 'ઇનામ બતાવવું?';

  @override
  String rewardConfirmBody(String name, String family) {
    return '\"$name\" — $family નું.';
  }

  @override
  String get rewardHidden => 'ઇનામ છુપાવ્યું';

  @override
  String get rewardShown => 'ઇનામ બતાવ્યું';

  @override
  String get redemptionsTitle => 'ઇનામની વિનંતીઓ';

  @override
  String get redemptionsSubtitle =>
      'ફક્ત જોવા માટે. માતા-પિતા પોતાના બાળકોની વિનંતીઓ જાતે મંજૂર કે નામંજૂર કરે છે.';

  @override
  String get redemptionsEmpty => 'કોઈ ઇનામ વિનંતી નથી.';

  @override
  String get redemptionAllStatuses => 'બધી સ્થિતિઓ';

  @override
  String get redemptionPending => 'બાકી';

  @override
  String get redemptionApproved => 'મંજૂર';

  @override
  String get redemptionDeclined => 'નામંજૂર';

  @override
  String get redemptionGiven => 'આપેલ';

  @override
  String get redemptionCancelled => 'રદ';

  @override
  String get contentTitle => 'શીખવાની સામગ્રી';

  @override
  String get contentSubtitle =>
      'બાળકો \"શીખો અને જુઓ\" માં પોતાની ભાષામાં શું જુએ છે';

  @override
  String get contentAddButton => 'સામગ્રી ઉમેરો';

  @override
  String get contentNewTitle => 'નવી સામગ્રી';

  @override
  String get contentEditTitle => 'સામગ્રીમાં ફેરફાર કરો';

  @override
  String get contentAdded => 'સામગ્રી ઉમેરી';

  @override
  String get contentSaved => 'સામગ્રી સાચવી';

  @override
  String get contentEmpty => 'હજી કોઈ સામગ્રી નથી.';

  @override
  String get contentLink => 'લિંક (https)';

  @override
  String get contentLinkHelp => 'બાળકના બ્રાઉઝર કે વીડિયો એપમાં ખુલે છે';

  @override
  String get contentThumbnail => 'થંબનેલ લિંક (https)';

  @override
  String get contentShownToChildren => 'બાળકોને બતાવવામાં આવે છે';

  @override
  String get contentTypeLink => 'લિંક';

  @override
  String get contentTypeVideo => 'વીડિયો લિંક';

  @override
  String get contentTypeArticle => 'લેખ';

  @override
  String get contentTypeDocument => 'દસ્તાવેજ';

  @override
  String get contentTypeActivity => 'પ્રવૃત્તિ';

  @override
  String get badgesTitle => 'બેજ';

  @override
  String get badgesSubtitle =>
      'બાળક નક્કી કરેલા જથ્થા સુધી પહોંચે ત્યારે આપોઆપ મળે છે. ગાર્ડનની સજાવટ ડિફૉલ્ટ બેજથી ખુલે છે.';

  @override
  String get badgeNewTitle => 'નવો બેજ';

  @override
  String get badgeEditTitle => 'બેજમાં ફેરફાર કરો';

  @override
  String get badgeCreated => 'બેજ બનાવ્યો';

  @override
  String get badgeSaved => 'બેજ સાચવ્યો';

  @override
  String get badgeEarnedBy => 'આ રીતે મળે છે';

  @override
  String get badgeAmountNeeded => 'જરૂરી જથ્થો';

  @override
  String get badgeCanBeEarned => 'મેળવી શકાય છે';

  @override
  String get badgeCriteriaApprovedTasks => 'મંજૂર મિશન';

  @override
  String get badgeCriteriaTotalStars => 'કુલ સ્ટાર';

  @override
  String get badgeCriteriaTotalXp => 'કુલ XP';

  @override
  String get badgeCriteriaStreak => 'સતત દિવસો';

  @override
  String get auditTitle => 'ઓડિટ લૉગ';

  @override
  String get auditSubtitle => 'કોણે શું અને ક્યારે બદલ્યું';

  @override
  String get auditEmpty => 'હજી કોઈ વહીવટી ફેરફાર નોંધાયો નથી.';

  @override
  String get settingsTitle => 'સેટિંગ';

  @override
  String get settingsSubtitle => 'મોબાઇલ એપ દર વખતે શરૂ થાય ત્યારે આ વાંચે છે';

  @override
  String get settingsLanguageTitle => 'પેનલની ભાષા';

  @override
  String get settingsLanguageHelp =>
      'આ ફક્ત આ એડમિન પેનલ બદલે છે. પરિવારો કે સર્વરે લખેલી સામગ્રીનો અનુવાદ થતો નથી.';

  @override
  String get settingsConsentTitle => 'સંમતિ દસ્તાવેજનું સંસ્કરણ';

  @override
  String get settingsConsentField => 'માતા-પિતા / વાલીની શરતોનું સંસ્કરણ';

  @override
  String get settingsConsentHelp =>
      'આ બદલવાથી દરેક માતા-પિતાને આગલી વખતે એપ ખોલતાં ફરી સંમતિ આપવાનું કહેવાશે.';

  @override
  String get settingsConsentConfirmTitle =>
      'બધા માતા-પિતાને ફરી સંમતિ આપવા કહેવું?';

  @override
  String settingsConsentConfirmBody(String version) {
    return 'નવું સંસ્કરણ \"$version\" દરેક માતા-પિતાને બતાવવામાં આવશે. પુષ્ટિ કરો કે કાનૂની ટીમે લખાણ મંજૂર કર્યું છે.';
  }

  @override
  String get settingsConsentPublish => 'સંસ્કરણ પ્રકાશિત કરો';

  @override
  String get settingsConsentPublished => 'સંમતિ સંસ્કરણ પ્રકાશિત થયું';

  @override
  String settingsConsentSummary(String version) {
    return 'માતા-પિતા / વાલીની શરતો: $version';
  }

  @override
  String get settingsConsentDraft => '(બિલ્ટ-ઇન ડ્રાફ્ટ: કાનૂની પુષ્ટિ જરૂરી)';

  @override
  String get settingsMaintenanceTitle => 'જાળવણીની સૂચના';

  @override
  String get settingsMaintenanceShow => 'એપમાં બેનર બતાવો';

  @override
  String get settingsMaintenanceMessage => 'સંદેશ';

  @override
  String get settingsMaintenanceHelp => 'ડિફૉલ્ટ વાક્ય માટે ખાલી રાખો';

  @override
  String get settingsMaintenanceSaved => 'જાળવણીની સૂચના સાચવી';

  @override
  String settingsMaintenanceShowing(String message) {
    return 'બતાવાઈ રહ્યું છે: $message';
  }

  @override
  String get settingsMaintenanceDefault => 'ડિફૉલ્ટ સંદેશ';
}
