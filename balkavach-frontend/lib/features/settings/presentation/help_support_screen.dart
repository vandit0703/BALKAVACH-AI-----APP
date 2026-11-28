import 'package:flutter/material.dart';

import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/brand_header.dart';

/// Localized Help & Support screen (DEC-07 / Workstream 5).
///
/// Covers parent/child accounts, child linking, missions, Stars/XP/rewards,
/// earned video time & carry-forward, video safety, and account deletion
/// without fabricating unapproved support emails, phone numbers, or SLAs.
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final code = Localizations.localeOf(context).languageCode;
    final faqs = _faqsFor(code);

    return Scaffold(
      appBar: AppBar(title: BrandTitle(title: l10n.settingsHelpTitle)),
      body: ScrollablePage(
        spacing: AppSpacing.md,
        children: [
          AppCard(
            key: const Key('help.intro'),
            color: context.colors.surfaceContainerLow,
            elevated: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.xs,
              children: [
                Text(
                  l10n.settingsHelpTitle,
                  style: context.text.titleLarge,
                ),
                Text(
                  l10n.settingsHelpSubtitle,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < faqs.length; i++)
            AppCard(
              key: Key('help.faq.$i'),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
                title: Text(faqs[i].$1, style: context.text.titleMedium),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      faqs[i].$2,
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static List<(String, String)> _faqsFor(String code) => switch (code) {
    'gu' => const [
      (
        'માતા-પિતા અને બાળકના એકાઉન્ટ કેવી રીતે કામ કરે છે?',
        'માતા-પિતા તેમના ઈમેલ અને પાસવર્ડથી સાઇન ઇન કરે છે અને તેમના પરિવારમાં બાળકની પ્રોફાઇલ બનાવે છે. બાળકો ફક્ત માતા-પિતા દ્વારા બનાવેલ એકાઉન્ટ અથવા લિંક કોડથી સાઇન ઇન કરી શકે છે.',
      ),
      (
        'બાળકનું ડિવાઇસ કોડ અથવા QR દ્વારા કેવી રીતે લિંક કરવું?',
        'માતા-પિતા બાળકની પ્રોફાઇલમાંથી એક વખત ઉપયોગમાં લઈ શકાય તેવો લિંક કોડ બનાવી શકે છે. બાળકના ડિવાઇસ પર તે કોડ દાખલ કરીને સુરક્ષિત રીતે લિંક કરી શકાય છે.',
      ),
      (
        'મિશન અને માતા-પિતાની મંજૂરી કેવી રીતે કામ કરે છે?',
        'બાળક મિશન પૂર્ણ કરીને ફોટો અથવા નોંધ સબમિટ કરે છે. માતા-પિતા મંજૂર કરે ત્યારે જ 10 સ્ટાર, 15 XP અને 15 મિનિટનો વિડિયો સમય મળે છે.',
      ),
      (
        'સ્ટાર, XP અને ઇનામનો ઇતિહાસ',
        'બાળકો કમાયેલા સ્ટારથી પરિવારના ઇનામો માટે વિનંતી કરી શકે છે. રદ થયેલ અથવા બદલાયેલ ઇનામોનો ઇતિહાસ પણ સુરક્ષિત રહે છે.',
      ),
      (
        'કમાયેલો વિડિયો સમય અને કેરી-ફોરવર્ડ',
        'દરેક મંજૂર મિશન પર 15 મિનિટ (900 સેકન્ડ) મળે છે. મફત દૈનિક સમય શૂન્ય છે. વણવપરાયેલ કમાયેલો સમય આગળના દિવસે પણ જળવાઈ રહે છે અને સમય શૂન્ય થતાં પ્લેબેક બંધ થાય છે.',
      ),
      (
        'વિડિયો સલામતી',
        'માત્ર ઉંમર-યોગ્ય, મોડરેટેડ અને અધિકારો-મંજૂર કરાયેલા વિડિયો જ દેખાય છે.',
      ),
      (
        'એકાઉન્ટ ડિલીટ અને ગોપનીયતા',
        'તમે સેટિંગ્સમાંથી એકાઉન્ટ ડિલીટ કરી શકો છો. વ્યક્તિગત માહિતી અનામી કરવામાં આવે છે અને નાણાકીય/ઓડિટ ઇતિહાસ સુરક્ષિત રાખવામાં આવે છે.',
      ),
    ],
    'hi' => const [
      (
        'माता-पिता और बच्चे के खाते कैसे काम करते हैं?',
        'माता-पिता अपने ईमेल और पासवर्ड से साइन इन करते हैं और परिवार में बच्चे की प्रोफ़ाइल बनाते हैं। बच्चे केवल माता-पिता द्वारा बनाए गए खाते या लिंक कोड से साइन इन कर सकते हैं।',
      ),
      (
        'कोड या QR से बच्चे का डिवाइस कैसे लिंक करें?',
        'माता-पिता बच्चे की प्रोफ़ाइल से एक बार उपयोग होने वाला लिंक कोड बना सकते हैं। बच्चे के डिवाइस पर कोड दर्ज करके सुरक्षित रूप से लिंक किया जा सकता है।',
      ),
      (
        'मिशन और माता-पिता की स्वीकृति कैसे काम करती है?',
        'बच्चा मिशन पूरा करके फ़ोटो या नोट सबमिट करता है। माता-पिता की स्वीकृति पर ही 10 स्टार, 15 XP और 15 मिनट का वीडियो समय मिलता है।',
      ),
      (
        'स्टार, XP और इनाम इतिहास',
        'बच्चे अर्जित स्टार से परिवार के इनाम का अनुरोध कर सकते हैं। बदले या हटाए गए इनामों का इतिहास भी सुरक्षित रहता है।',
      ),
      (
        'अर्जित वीडियो समय और कैरी-फ़ॉरवर्ड',
        'प्रत्येक स्वीकृत मिशन पर 15 मिनट (900 सेकंड) मिलते हैं। निःशुल्क दैनिक समय शून्य है। बचा हुआ अर्जित समय अगले दिन भी उपलब्ध रहता है और शून्य होने पर प्लेबैक रुक जाता है।',
      ),
      (
        'वीडियो सुरक्षा',
        'केवल आयु-उपयुक्त, मॉडरेटेड और अधिकार-स्वीकृत वीडियो ही दिखाए जाते हैं।',
      ),
      (
        'खाता हटाना और गोपनीयता',
        'आप सेटिंग्स से अपना खाता हटा सकते हैं। व्यक्तिगत जानकारी को गुमनाम कर दिया जाता है और ऑडिट/लेज़र रिकॉर्ड सुरक्षित रखे जाते हैं।',
      ),
    ],
    _ => const [
      (
        'How do parent and child accounts work?',
        'Parents sign in with email and password and create child profiles for their family. Children sign in using parent-created credentials or a secure linking code.',
      ),
      (
        'How does child device linking with a code or QR work?',
        'A parent generates a short-lived, single-use linking code from the child profile. Entering that code on the child device links it safely without exposing personal data.',
      ),
      (
        'How do missions and parent approvals work?',
        'Children complete a mission and submit a photo or note. Only after parent approval are 10 Stars, 15 XP, and 15 minutes of video time granted.',
      ),
      (
        'How do Stars, XP, and reward history work?',
        'Children redeem earned Stars for parent-configured rewards. Past redemption records preserve reward titles and cancellation timestamps.',
      ),
      (
        'How does earned video time and carry-forward work?',
        'Each approved mission grants 15 minutes (900 seconds). Free daily allowance is zero. Unused earned time carries forward across days, and playback stops immediately at zero.',
      ),
      (
        'How is video safety controlled?',
        'Only age-appropriate, moderated, rights-cleared videos appear.',
      ),
      (
        'How do account deletion and privacy work?',
        'Parents can delete their account from Settings. Personal data and media are anonymized while anonymized reward ledgers and audit logs are retained.',
      ),
    ],
  };
}
