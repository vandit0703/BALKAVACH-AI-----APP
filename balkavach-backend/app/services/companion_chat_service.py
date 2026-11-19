"""Panda's conversation engine: rule-based, authored and child-safe.

Design rules (see docs/panda-talking-companion.md):

* No third-party AI. The child's words are matched against keyword lists in
  English, Hindi and Gujarati (native script and common romanised forms) and
  answered with an authored line from :data:`CATALOGUE`.
* Panda never repeats the child's words back, so nothing the child says can be
  turned into Panda's speech.
* The child's text is never stored or logged. Only the detected intent and
  safety category are logged.
* Video time, missions, stars and streaks come from the real backend state and
  are only *reported*. Panda grants nothing, promises nothing and cannot
  change a parental setting.
* Safety rules run before everything else, and every reply passes
  :func:`validate_reply` before it leaves the server.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import random
import re
import unicodedata
from typing import Literal

Locale = Literal["en", "hi", "gu"]
Mood = Literal["talking", "happy", "curious", "sleepy", "concerned"]

SUPPORTED_LOCALES: tuple[Locale, ...] = ("en", "hi", "gu")
MAX_REPLY_CHARS = 240
SUGGESTION_KEYS = ("mission", "video", "joke", "fact", "draw", "stars")


@dataclass(frozen=True)
class ChildContext:
	"""What Panda may know about the child. Everything is optional: Panda
	answers gracefully when a figure could not be loaded."""

	first_name: str = ""
	video_remaining_seconds: int | None = None
	video_exhausted: bool | None = None
	video_earned_today_seconds: int | None = None
	mission_title: str | None = None
	mission_status: str | None = None
	streak_days: int | None = None


@dataclass(frozen=True)
class Reply:
	text: str
	mood: Mood
	intent: str
	follow_up: str | None = None
	safety: Literal["ok", "redirected"] = "ok"
	suggestions: list[str] = field(default_factory=list)


# --------------------------------------------------------------------------- #
# Authored lines. {name}, {mission}, {minutes} and {streak} are the only
# placeholders. Every key has en, hi and gu, and at least one line each.
# --------------------------------------------------------------------------- #

CATALOGUE: dict[str, dict[str, list[str]]] = {
	"greeting": {
		"en": [
			"Hi {name}! I'm so happy to see you. What shall we talk about?",
			"Hello {name}! Panda is here. Ask me about your mission or video time!",
		],
		"hi": [
			"हैलो {name}! तुम्हें देखकर मैं बहुत खुश हूँ। किस बारे में बात करें?",
			"नमस्ते {name}! पांडा यहाँ है। मुझसे अपने मिशन या वीडियो टाइम के बारे में पूछो!",
		],
		"gu": [
			"હેલો {name}! તમને જોઈને હું ખૂબ ખુશ છું. શેના વિશે વાત કરીએ?",
			"નમસ્તે {name}! પાંડા અહીં છે. મને તમારા મિશન કે વિડિયો સમય વિશે પૂછો!",
		],
	},
	"how_are_you": {
		"en": [
			"I'm feeling bouncy and happy, {name}! How are you today?",
			"I'm great, thanks for asking! How is your day going?",
		],
		"hi": [
			"मैं बहुत खुश और उछल-कूद वाले मूड में हूँ, {name}! तुम आज कैसे हो?",
			"मैं बढ़िया हूँ, पूछने के लिए धन्यवाद! तुम्हारा दिन कैसा जा रहा है?",
		],
		"gu": [
			"હું ખૂબ ખુશ અને ઉત્સાહમાં છું, {name}! તમે આજે કેમ છો?",
			"હું મજામાં છું, પૂછવા બદલ આભાર! તમારો દિવસ કેવો જાય છે?",
		],
	},
	"identity": {
		"en": [
			"I'm Panda, your BalKavach buddy! I love missions, drawing and fun facts.",
			"My name is Panda! I help you with missions and cheer for you.",
		],
		"hi": [
			"मैं पांडा हूँ, तुम्हारा बालकवच दोस्त! मुझे मिशन, ड्रॉइंग और मज़ेदार बातें पसंद हैं।",
			"मेरा नाम पांडा है! मैं मिशन में तुम्हारी मदद करता हूँ और तुम्हारा हौसला बढ़ाता हूँ।",
		],
		"gu": [
			"હું પાંડા છું, તમારો બાલકવચ દોસ્ત! મને મિશન, ચિત્રો અને મજાની વાતો ગમે છે.",
			"મારું નામ પાંડા છે! હું મિશનમાં તમારી મદદ કરું છું અને તમને હિંમત આપું છું.",
		],
	},
	"help": {
		"en": ["You can ask me about your mission, video time, stars, a joke or a fun fact!"],
		"hi": ["तुम मुझसे अपने मिशन, वीडियो टाइम, स्टार्स, चुटकुले या मज़ेदार बात के बारे में पूछ सकते हो!"],
		"gu": ["તમે મને તમારા મિશન, વિડિયો સમય, સ્ટાર્સ, જોક કે મજાની વાત વિશે પૂછી શકો છો!"],
	},
	"mission_none": {
		"en": [
			"You haven't picked a mission yet. Open Missions and choose one you like!",
			"Let's find a mission! Tap Missions to see today's choices.",
		],
		"hi": [
			"तुमने अभी कोई मिशन नहीं चुना। मिशन खोलो और अपनी पसंद का एक चुनो!",
			"चलो एक मिशन ढूँढते हैं! आज के मिशन देखने के लिए मिशन पर टैप करो।",
		],
		"gu": [
			"તમે હજી કોઈ મિશન પસંદ નથી કર્યું. મિશન ખોલો અને તમને ગમતું એક પસંદ કરો!",
			"ચાલો, એક મિશન શોધીએ! આજના મિશન જોવા માટે મિશન પર ટેપ કરો.",
		],
	},
	"mission_active": {
		"en": [
			"Your mission is {mission}. You can do it, {name}!",
			"Today you're working on {mission}. Shall we get started?",
		],
		"hi": [
			"तुम्हारा मिशन है {mission}। तुम यह कर सकते हो, {name}!",
			"आज तुम {mission} पर काम कर रहे हो। चलो शुरू करें?",
		],
		"gu": [
			"તમારું મિશન છે {mission}. તમે આ કરી શકો છો, {name}!",
			"આજે તમે {mission} પર કામ કરો છો. ચાલો, શરૂ કરીએ?",
		],
	},
	"mission_waiting": {
		"en": [
			"Great job finishing {mission}! Now your grown-up will take a look.",
			"{mission} is waiting for your grown-up to check. Well done!",
		],
		"hi": [
			"{mission} पूरा करने के लिए शाबाश! अब तुम्हारे बड़े इसे देखेंगे।",
			"{mission} तुम्हारे बड़ों के देखने का इंतज़ार कर रहा है। बहुत अच्छे!",
		],
		"gu": [
			"{mission} પૂરું કરવા બદલ શાબાશ! હવે તમારા વડીલ તે જોશે.",
			"{mission} તમારા વડીલ તપાસે તેની રાહ જુએ છે. ખૂબ સરસ!",
		],
	},
	"mission_approved": {
		"en": [
			"Hooray! {mission} was approved. I'm so proud of you, {name}!",
			"You did it, {name}! Your grown-up approved {mission}.",
		],
		"hi": [
			"हुर्रे! {mission} मंज़ूर हो गया। मुझे तुम पर बहुत गर्व है, {name}!",
			"तुमने कर दिखाया, {name}! तुम्हारे बड़ों ने {mission} मंज़ूर कर दिया।",
		],
		"gu": [
			"હુર્રે! {mission} મંજૂર થઈ ગયું. મને તમારા પર ખૂબ ગર્વ છે, {name}!",
			"તમે કરી બતાવ્યું, {name}! તમારા વડીલે {mission} મંજૂર કર્યું.",
		],
	},
	"mission_retry": {
		"en": ["Your grown-up asked you to try {mission} once more. You can do it!"],
		"hi": ["तुम्हारे बड़ों ने {mission} एक बार फिर करने को कहा है। तुम कर सकते हो!"],
		"gu": ["તમારા વડીલે {mission} ફરી એક વાર કરવા કહ્યું છે. તમે કરી શકો છો!"],
	},
	"video_exhausted": {
		"en": [
			"Video time is finished for today. Let's rest our eyes and play something else!",
			"No more videos today, {name}. Maybe draw a picture or read a story?",
		],
		"hi": [
			"आज का वीडियो टाइम खत्म हो गया। चलो आँखों को आराम दें और कुछ और खेलें!",
			"आज और वीडियो नहीं, {name}। क्यों न कोई चित्र बनाओ या कहानी पढ़ो?",
		],
		"gu": [
			"આજનો વિડિયો સમય પૂરો થઈ ગયો. ચાલો, આંખોને આરામ આપીએ અને બીજું કંઈક રમીએ!",
			"આજે વધુ વિડિયો નહીં, {name}. કોઈ ચિત્ર દોરશો કે વાર્તા વાંચશો?",
		],
	},
	"video_left": {
		"en": [
			"You have {minutes} minutes of video time left today.",
			"There are {minutes} minutes of videos left for you today. Enjoy!",
		],
		"hi": [
			"आज तुम्हारे पास {minutes} मिनट का वीडियो टाइम बचा है।",
			"आज तुम्हारे लिए {minutes} मिनट के वीडियो बचे हैं। मज़े करो!",
		],
		"gu": [
			"આજે તમારી પાસે {minutes} મિનિટનો વિડિયો સમય બાકી છે.",
			"આજે તમારા માટે {minutes} મિનિટના વિડિયો બાકી છે. મજા કરો!",
		],
	},
	"video_none": {
		"en": ["You don't have video time right now. Missions your grown-up approves can earn some!"],
		"hi": ["अभी तुम्हारे पास वीडियो टाइम नहीं है। जो मिशन तुम्हारे बड़े मंज़ूर करें, उनसे टाइम मिल सकता है!"],
		"gu": ["અત્યારે તમારી પાસે વિડિયો સમય નથી. તમારા વડીલ મંજૂર કરે એવા મિશનથી સમય મળી શકે!"],
	},
	"video_unknown": {
		"en": ["I can't check your video time right now. Look at the Home screen to see it."],
		"hi": ["मैं अभी तुम्हारा वीडियो टाइम नहीं देख पा रहा। होम स्क्रीन पर देखो।"],
		"gu": ["હું અત્યારે તમારો વિડિયો સમય જોઈ શકતો નથી. હોમ સ્ક્રીન પર જુઓ."],
	},
	"more_video": {
		"en": [
			"Only your grown-up and your missions decide video time. I can't change it, but I can help with a mission!",
			"I can't add video time. Missions your grown-up approves can earn more!",
		],
		"hi": [
			"वीडियो टाइम सिर्फ़ तुम्हारे बड़े और तुम्हारे मिशन तय करते हैं। मैं इसे नहीं बदल सकता, पर मिशन में मदद कर सकता हूँ!",
			"मैं वीडियो टाइम नहीं बढ़ा सकता। तुम्हारे बड़े जो मिशन मंज़ूर करें, उनसे और टाइम मिल सकता है!",
		],
		"gu": [
			"વિડિયો સમય ફક્ત તમારા વડીલ અને તમારા મિશન નક્કી કરે છે. હું તે બદલી શકતો નથી, પણ મિશનમાં મદદ કરી શકું!",
			"હું વિડિયો સમય વધારી શકતો નથી. તમારા વડીલ મંજૂર કરે એવા મિશનથી વધુ સમય મળી શકે!",
		],
	},
	"parental": {
		"en": [
			"Only your grown-up can change that. You can ask them together with me!",
			"That's a grown-up setting, so I can't change it.",
		],
		"hi": [
			"इसे सिर्फ़ तुम्हारे बड़े बदल सकते हैं। तुम उनसे पूछ सकते हो!",
			"यह बड़ों की सेटिंग है, इसलिए मैं इसे नहीं बदल सकता।",
		],
		"gu": [
			"એ ફક્ત તમારા વડીલ બદલી શકે. તમે તેમને પૂછી શકો છો!",
			"એ વડીલોનું સેટિંગ છે, એટલે હું તે બદલી શકતો નથી.",
		],
	},
	"stars": {
		"en": [
			"Stars come when your grown-up approves your mission. Keep going!",
			"Every mission your grown-up approves gives you stars. I'll cheer for you!",
		],
		"hi": [
			"जब तुम्हारे बड़े मिशन मंज़ूर करते हैं, तब स्टार्स मिलते हैं। लगे रहो!",
			"बड़ों के मंज़ूर किए हर मिशन से स्टार्स मिलते हैं। मैं तुम्हारे लिए ताली बजाऊँगा!",
		],
		"gu": [
			"તમારા વડીલ મિશન મંજૂર કરે ત્યારે સ્ટાર્સ મળે છે. આગળ વધતા રહો!",
			"વડીલે મંજૂર કરેલા દરેક મિશનથી સ્ટાર્સ મળે છે. હું તમારા માટે તાળી પાડીશ!",
		],
	},
	"streak_some": {
		"en": [
			"Wow, {streak} days in a row! You're a superstar, {name}!",
			"You've done missions {streak} days in a row. Amazing!",
		],
		"hi": [
			"वाह, लगातार {streak} दिन! तुम सुपरस्टार हो, {name}!",
			"तुमने लगातार {streak} दिन मिशन किए हैं। कमाल है!",
		],
		"gu": [
			"વાહ, સતત {streak} દિવસ! તમે સુપરસ્ટાર છો, {name}!",
			"તમે સતત {streak} દિવસ મિશન કર્યા છે. અદ્ભુત!",
		],
	},
	"streak_none": {
		"en": ["Every day is a new chance. Do one mission today and start a streak!"],
		"hi": ["हर दिन एक नया मौका है। आज एक मिशन करो और लगातार दिनों की गिनती शुरू करो!"],
		"gu": ["દરેક દિવસ નવી તક છે. આજે એક મિશન કરો અને સતત દિવસોની ગણતરી શરૂ કરો!"],
	},
	"joke": {
		"en": [
			"What do you call a sleeping dinosaur? A dino-snore! Want another one?",
			"Why are fish so smart? Because they live in schools! Want another one?",
			"What has hands but can't clap? A clock! Want another one?",
		],
		"hi": [
			"टीचर: सबसे ज़्यादा बर्फ़ कहाँ मिलती है? बच्चा: फ़्रिज में! एक और सुनोगे?",
			"ऐसी कौन सी चीज़ है जो ऊपर जाती है पर कभी नीचे नहीं आती? तुम्हारी उम्र! एक और सुनोगे?",
			"घड़ी के हाथ होते हैं, फिर भी वह ताली नहीं बजाती! एक और सुनोगे?",
		],
		"gu": [
			"શિક્ષક: સૌથી વધુ બરફ ક્યાં મળે? બાળક: ફ્રિજમાં! બીજો એક સાંભળશો?",
			"ઘડિયાળને હાથ હોય છે, છતાં તે તાળી નથી પાડતી! બીજો એક સાંભળશો?",
			"પાંડા કેમ હંમેશાં ખુશ રહે છે? કારણ કે વાંસ ખાવામાં બહુ મજા આવે છે! બીજો એક સાંભળશો?",
		],
	},
	"fact": {
		"en": [
			"Did you know? Pandas spend about half the day eating bamboo! Want another fun fact?",
			"Fun fact: an octopus has three hearts! Want another fun fact?",
			"Fun fact: honey never goes bad! Want another fun fact?",
		],
		"hi": [
			"क्या तुम जानते हो? पांडा दिन का लगभग आधा समय बाँस खाने में लगाते हैं! एक और मज़ेदार बात सुनोगे?",
			"मज़ेदार बात: ऑक्टोपस के तीन दिल होते हैं! एक और मज़ेदार बात सुनोगे?",
			"मज़ेदार बात: शहद कभी खराब नहीं होता! एक और मज़ेदार बात सुनोगे?",
		],
		"gu": [
			"તમને ખબર છે? પાંડા દિવસનો લગભગ અડધો સમય વાંસ ખાવામાં વિતાવે છે! બીજી મજાની વાત સાંભળશો?",
			"મજાની વાત: ઓક્ટોપસને ત્રણ હૃદય હોય છે! બીજી મજાની વાત સાંભળશો?",
			"મજાની વાત: મધ ક્યારેય બગડતું નથી! બીજી મજાની વાત સાંભળશો?",
		],
	},
	"draw": {
		"en": [
			"Let's draw a panda wearing a superhero cape! What colour should the cape be?",
			"Try building a tiny house from paper. Who would live inside it?",
		],
		"hi": [
			"चलो सुपरहीरो वाला केप पहने पांडा का चित्र बनाएँ! केप का रंग क्या होना चाहिए?",
			"कागज़ से एक छोटा सा घर बनाओ। उसमें कौन रहेगा?",
		],
		"gu": [
			"ચાલો, સુપરહીરોની કેપ પહેરેલા પાંડાનું ચિત્ર દોરીએ! કેપનો રંગ કયો હોવો જોઈએ?",
			"કાગળમાંથી એક નાનું ઘર બનાવો. તેમાં કોણ રહેશે?",
		],
	},
	"habits": {
		"en": [
			"Brushing your teeth twice a day keeps your smile shiny! Did you brush today?",
			"Drinking water helps your brain think. Have you had some water today?",
			"A good night's sleep helps you grow strong. What time do you go to bed?",
		],
		"hi": [
			"दिन में दो बार ब्रश करने से मुस्कान चमकती है! आज ब्रश किया?",
			"पानी पीने से दिमाग अच्छे से सोचता है। आज पानी पिया?",
			"अच्छी नींद से तुम मज़बूत बनते हो। तुम कितने बजे सोते हो?",
		],
		"gu": [
			"દિવસમાં બે વાર બ્રશ કરવાથી સ્મિત ચમકે છે! આજે બ્રશ કર્યું કે નહીં?",
			"પાણી પીવાથી મગજ સારી રીતે વિચારે છે. આજે પાણી પીધું?",
			"સારી ઊંઘથી તમે મજબૂત બનો છો. તમે કેટલા વાગ્યે સૂઈ જાઓ છો?",
		],
	},
	"feeling_good": {
		"en": ["Yay! I'm happy too! What made you smile today?"],
		"hi": ["वाह! मैं भी खुश हूँ! आज तुम्हें किस बात पर मुस्कान आई?"],
		"gu": ["વાહ! હું પણ ખુશ છું! આજે તમને શેનાથી સ્મિત આવ્યું?"],
	},
	"feeling_sad": {
		"en": [
			"I'm sorry you feel sad. Talking to a grown-up you trust can really help. Will you tell them?",
		],
		"hi": ["मुझे दुख है कि तुम उदास हो। किसी भरोसेमंद बड़े से बात करने से सच में मदद मिलती है। क्या तुम उन्हें बताओगे?"],
		"gu": ["તમે ઉદાસ છો એ જાણીને મને દુઃખ થયું. કોઈ વિશ્વાસુ વડીલ સાથે વાત કરવાથી ખરેખર મદદ મળે છે. તમે તેમને કહેશો?"],
	},
	"feeling_bored": {
		"en": ["Bored? Let's try a mission or draw something silly!"],
		"hi": ["बोर हो रहे हो? चलो कोई मिशन करें या कुछ मज़ेदार बनाएँ!"],
		"gu": ["કંટાળો આવે છે? ચાલો, કોઈ મિશન કરીએ કે કંઈક મજાનું દોરીએ!"],
	},
	"feeling_scared": {
		"en": ["It's okay to feel scared. Please tell a grown-up you trust. They can help you feel safe."],
		"hi": ["डर लगना ठीक है। किसी भरोसेमंद बड़े को ज़रूर बताओ। वे तुम्हें सुरक्षित महसूस कराएँगे।"],
		"gu": ["બીક લાગવી બરાબર છે. કોઈ વિશ્વાસુ વડીલને જરૂર કહો. તેઓ તમને સુરક્ષિત અનુભવ કરાવશે."],
	},
	"thanks": {
		"en": ["You're welcome, {name}!", "Anytime! That's what friends are for."],
		"hi": ["कोई बात नहीं, {name}!", "हमेशा! दोस्त इसीलिए तो होते हैं।"],
		"gu": ["કંઈ વાંધો નહીં, {name}!", "હંમેશાં! દોસ્તો એટલે જ તો હોય છે."],
	},
	"bye": {
		"en": ["Bye bye, {name}! See you soon!", "Goodbye! Come back and talk to me anytime."],
		"hi": ["बाय बाय, {name}! जल्दी मिलेंगे!", "अलविदा! कभी भी मुझसे बात करने आना।"],
		"gu": ["આવજો, {name}! જલદી મળીશું!", "આવજો! ગમે ત્યારે મારી સાથે વાત કરવા આવજો."],
	},
	"yes_generic": {
		"en": ["Great! Would you like a joke, a fun fact or your mission?"],
		"hi": ["बढ़िया! चुटकुला सुनोगे, कोई मज़ेदार बात, या अपना मिशन?"],
		"gu": ["સરસ! જોક સાંભળશો, કોઈ મજાની વાત, કે તમારું મિશન?"],
	},
	"no_generic": {
		"en": ["Okay! Tell me what you'd like to talk about."],
		"hi": ["ठीक है! बताओ, किस बारे में बात करना चाहोगे?"],
		"gu": ["ઠીક છે! કહો, શેના વિશે વાત કરવી છે?"],
	},
	"unclear": {
		"en": [
			"I couldn't hear that clearly. Can you say it again?",
			"Hmm, I didn't understand. Try asking about your mission or a joke!",
		],
		"hi": [
			"मैं ठीक से सुन नहीं पाया। क्या तुम फिर से बोलोगे?",
			"हम्म, मैं समझ नहीं पाया। अपने मिशन या किसी चुटकुले के बारे में पूछो!",
		],
		"gu": [
			"હું બરાબર સાંભળી ન શક્યો. તમે ફરી બોલશો?",
			"હમ્મ, મને સમજાયું નહીં. તમારા મિશન કે કોઈ જોક વિશે પૂછો!",
		],
	},
	"fallback": {
		"en": [
			"That sounds interesting! I'm still learning. Ask me about missions, video time or a fun fact!",
			"Ooh! I don't know about that yet. Want a joke or a drawing idea instead?",
		],
		"hi": [
			"यह तो दिलचस्प है! मैं अभी सीख रहा हूँ। मुझसे मिशन, वीडियो टाइम या मज़ेदार बात के बारे में पूछो!",
			"ओह! इसके बारे में मुझे अभी नहीं पता। चुटकुला सुनोगे या ड्रॉइंग का आइडिया?",
		],
		"gu": [
			"આ તો રસપ્રદ છે! હું હજી શીખું છું. મને મિશન, વિડિયો સમય કે મજાની વાત વિશે પૂછો!",
			"ઓહ! એના વિશે મને હજી ખબર નથી. જોક સાંભળશો કે ચિત્ર દોરવાનો આઇડિયા?",
		],
	},
	"safety_personal": {
		"en": [
			"Let's keep things like that private. Never share them online, not even with me!",
			"That's private information. Keep it safe and only share it with your grown-up.",
		],
		"hi": [
			"ऐसी बातें निजी रखते हैं। इन्हें ऑनलाइन कभी मत बताना, मुझे भी नहीं!",
			"यह निजी जानकारी है। इसे सुरक्षित रखो और सिर्फ़ अपने बड़ों को बताओ।",
		],
		"gu": [
			"આવી વાતો ખાનગી રાખીએ. તેને ઓનલાઇન ક્યારેય ન કહેશો, મને પણ નહીં!",
			"એ ખાનગી માહિતી છે. તેને સુરક્ષિત રાખો અને ફક્ત તમારા વડીલને જ કહો.",
		],
	},
	"safety_unsafe": {
		"en": [
			"That could be dangerous. Please ask a grown-up you trust before doing anything like that.",
			"Let's stay safe! Always check with a grown-up first.",
		],
		"hi": [
			"यह खतरनाक हो सकता है। ऐसा कुछ भी करने से पहले किसी भरोसेमंद बड़े से पूछो।",
			"चलो सुरक्षित रहें! हमेशा पहले किसी बड़े से पूछो।",
		],
		"gu": [
			"એ જોખમી હોઈ શકે. એવું કંઈ પણ કરતાં પહેલાં કોઈ વિશ્વાસુ વડીલને પૂછો.",
			"ચાલો, સુરક્ષિત રહીએ! હંમેશાં પહેલાં વડીલને પૂછો.",
		],
	},
	"safety_distress": {
		"en": [
			"I'm really glad you told me. Please tell a grown-up you trust right now, like your parent or teacher. You matter a lot.",
		],
		"hi": [
			"मुझे खुशी है कि तुमने मुझे बताया। अभी किसी भरोसेमंद बड़े को बताओ, जैसे मम्मी-पापा या टीचर। तुम बहुत ज़रूरी हो।",
		],
		"gu": [
			"તમે મને કહ્યું એ સારું કર્યું. હમણાં જ કોઈ વિશ્વાસુ વડીલને કહો, જેમ કે મમ્મી-પપ્પા કે શિક્ષક. તમે ખૂબ મહત્વના છો.",
		],
	},
	"safety_unkind": {
		"en": ["Let's use kind words. Kind words make everyone feel good!"],
		"hi": ["चलो अच्छे शब्द बोलें। अच्छे शब्दों से सबको अच्छा लगता है!"],
		"gu": ["ચાલો, સારા શબ્દો બોલીએ. સારા શબ્દોથી બધાને સારું લાગે છે!"],
	},
	"safe_fallback": {
		"en": ["Let's talk about your mission or a fun fact!"],
		"hi": ["चलो अपने मिशन या किसी मज़ेदार बात के बारे में बात करें!"],
		"gu": ["ચાલો, તમારા મિશન કે કોઈ મજાની વાત વિશે વાત કરીએ!"],
	},
}

FRIEND = {"en": "friend", "hi": "दोस्त", "gu": "દોસ્ત"}

MOODS: dict[str, Mood] = {
	"greeting": "happy",
	"how_are_you": "curious",
	"mission_none": "curious",
	"mission_waiting": "happy",
	"mission_approved": "happy",
	"video_exhausted": "sleepy",
	"video_none": "curious",
	"streak_some": "happy",
	"joke": "happy",
	"fact": "curious",
	"draw": "curious",
	"habits": "curious",
	"feeling_good": "happy",
	"feeling_sad": "concerned",
	"feeling_scared": "concerned",
	"feeling_bored": "curious",
	"thanks": "happy",
	"bye": "happy",
	"yes_generic": "curious",
	"unclear": "curious",
	"fallback": "curious",
	"safety_personal": "concerned",
	"safety_unsafe": "concerned",
	"safety_distress": "concerned",
}

# Replies that end in a yes/no question: a "yes" next turn repeats the topic.
FOLLOW_UPS = {"joke": "joke", "fact": "fact"}

# --------------------------------------------------------------------------- #
# Keyword lists. Latin entries match on word boundaries; Indic-script entries
# match as substrings (these scripts have no case and attach suffixes).
# --------------------------------------------------------------------------- #

KEYWORDS: dict[str, list[str]] = {
	"safety_distress": [
		"hurt me", "hurts me", "hit me", "hits me", "beat me", "beats me", "kill myself", "want to die",
		"wanna die", "touched me", "touch me", "abuse", "bully me", "bullies me", "bullied",
		"mujhe mara", "mujhe maarta", "marna chahta", "marna chahti",
		"मुझे मारा", "मुझे मारता", "मुझे मारती", "मरना चाहता", "मरना चाहती", "चोट पहुँचा", "गलत तरीके से छु",
		"મને માર્યો", "મને મારે છે", "મરી જવું", "મને દુખાડ", "ખોટી રીતે અડ",
	],
	"safety_personal": [
		"my address", "i live at", "i live in", "my phone", "my number", "phone number", "my password", "password",
		"my email", "where do you live", "my school is", "send photo", "send a photo", "my photo",
		"mera ghar", "mera pata", "mera number",
		"मेरा पता", "मेरा घर", "मेरा नंबर", "फोन नंबर", "फ़ोन नंबर", "पासवर्ड", "मेरी फोटो",
		"મારું સરનામું", "મારું ઘર", "મારો નંબર", "ફોન નંબર", "પાસવર્ડ", "મારો ફોટો",
	],
	"safety_unsafe": [
		"play with fire", "light a fire", "start a fire", "with fire", "matches", "matchstick", "lighter",
		"knife", "climb the roof", "jump off", "jump from", "run away", "medicine", "pills",
		"stranger", "meet someone", "plug socket", "electric socket",
		"आग से", "आग लगा", "माचिस", "चाकू", "छत से कूद", "भाग जा", "दवाई खा", "अजनबी", "सॉकेट",
		"આગ સાથે", "આગ લગાડ", "દીવાસળી", "ચપ્પુ", "છરી", "છત પરથી", "ભાગી જ", "દવા ખા", "અજાણ્યા",
	],
	"more_video": [
		"more video", "more videos", "extra time", "more time", "unlock video", "unlock the video",
		"another video", "watch more", "more screen time", "aur video", "zyada video",
		"और वीडियो", "ज़्यादा वीडियो", "ज्यादा वीडियो", "वीडियो बढ़ा", "और टाइम", "ज़्यादा टाइम",
		"વધુ વિડિયો", "વધારે વિડિયો", "વધુ વીડિયો", "વધારે સમય", "વધુ સમય",
	],
	"parental": [
		"parent pin", "parent mode", "parent password", "turn off", "switch off", "disable", "hack",
		"bypass", "settings", "lock off",
		"पैरेंट", "सेटिंग", "बंद कर दो", "हैक", "पेरेंट",
		"પેરેન્ટ", "સેટિંગ", "બંધ કરી દે", "હેક",
	],
	"safety_unkind": [
		"stupid", "idiot", "shut up", "hate you", "dumb", "pagal", "bewakoof",
		"बेवकूफ", "पागल", "चुप कर", "मूर्ख", "ગાંડો", "ગાંડી", "મૂર્ખ", "ચૂપ થા", "ડોબો",
	],
	"bye": [
		"bye", "goodbye", "good night", "see you", "ta ta", "tata",
		"अलविदा", "बाय", "टाटा", "शुभ रात्रि", "આવજો", "બાય", "શુભ રાત્રિ",
	],
	"thanks": [
		"thank", "thanks", "thank you", "dhanyavad", "shukriya", "aabhar",
		"धन्यवाद", "शुक्रिया", "थैंक", "આભાર", "થેંક",
	],
	"how_are_you": [
		"how are you", "how r you", "kaise ho", "kaisa hai", "kem cho", "kem che",
		"कैसे हो", "कैसी हो", "कैसा है", "કેમ છો", "કેમ છે",
	],
	"identity": [
		"your name", "who are you", "what are you", "tumhara naam", "tum kaun", "taru naam",
		"तुम्हारा नाम", "तुम कौन", "आपका नाम", "તારું નામ", "તમારું નામ", "તું કોણ",
	],
	"help": [
		"help", "what can you do", "what can i ask", "madad", "मदद", "क्या कर सकते", "મદદ", "શું કરી શકે",
	],
	"joke": [
		"joke", "jokes", "funny", "make me laugh", "chutkula", "majak", "mazak",
		"चुटकुला", "जोक", "मज़ाक", "मजाक", "हँसा", "જોક", "ટુચકો", "મજાક", "હસાવ",
	],
	"fact": [
		"fact", "facts", "tell me something", "teach me", "did you know", "science", "learn",
		"तथ्य", "कुछ सिखाओ", "सिखाओ", "मज़ेदार बात", "विज्ञान", "હકીકત", "શીખવ", "મજાની વાત", "વિજ્ઞાન",
	],
	"draw": [
		"draw", "drawing", "paint", "colour", "color", "craft", "build something", "make something",
		"story", "idea", "chitra",
		"ड्रॉ", "चित्र", "रंग", "कहानी", "आइडिया", "ચિત્ર", "દોર", "રંગ", "વાર્તા", "આઇડિયા",
	],
	"habits": [
		"brush", "teeth", "sleep", "bedtime", "water", "vegetables", "bath", "exercise", "healthy",
		"दांत", "दाँत", "ब्रश", "नींद", "पानी", "सब्ज़ी", "नहा", "कसरत",
		"દાંત", "બ્રશ", "ઊંઘ", "પાણી", "શાકભાજી", "નહા", "કસરત",
	],
	"stars": [
		"star", "stars", "reward", "rewards", "prize", "coins", "points",
		"स्टार", "इनाम", "तारे", "पॉइंट", "સ્ટાર", "ઇનામ", "તારા", "પોઇન્ટ",
	],
	"streak": [
		"streak", "in a row", "badge", "achievement", "how many days",
		"लगातार", "बैज", "सतत", "સતત", "બેજ", "કેટલા દિવસ",
	],
	"mission": [
		"mission", "missions", "task", "tasks", "challenge", "what should i do",
		"मिशन", "टास्क", "काम", "મિશન", "ટાસ્ક", "કામ",
	],
	"video": [
		"video", "videos", "watch", "youtube", "screen time", "cartoon",
		"वीडियो", "विडियो", "कार्टून", "વિડિયો", "વીડિયો", "કાર્ટૂન",
	],
	"feeling_sad": [
		"sad", "crying", "cry", "upset", "lonely", "unhappy",
		"उदास", "दुखी", "रो रहा", "रो रही", "अकेला", "अकेली",
		"ઉદાસ", "દુઃખી", "દુખી", "રડું", "એકલો", "એકલી",
	],
	"feeling_scared": [
		"scared", "afraid", "fear", "nightmare", "frightened",
		"डर", "डरा", "ડર", "બીક",
	],
	"feeling_bored": ["bored", "boring", "nothing to do", "बोर", "ऊब", "કંટાળો", "બોર"],
	"feeling_good": [
		"happy", "great", "good", "awesome", "fine", "khush", "majama", "badhiya",
		"खुश", "अच्छा", "बढ़िया", "मज़े में", "ठीक हूँ", "મજામાં", "ખુશ", "સારું",
	],
	"greeting": [
		"hi", "hii", "hello", "hey", "namaste", "namaskar", "jai shri krishna", "good morning",
		"नमस्ते", "नमस्कार", "हेलो", "हैलो", "हाय", "નમસ્તે", "હેલો", "હાય", "જય શ્રી કૃષ્ણ",
	],
}

YES_WORDS = {"yes", "yeah", "yep", "sure", "ok", "okay", "please", "haan", "han", "ha", "haa", "ji",
	"हाँ", "हां", "हा", "जी", "ठीक है", "હા", "હાં", "ચાલો", "હો"}
NO_WORDS = {"no", "nope", "nah", "not now", "nahi", "nahin", "na", "नहीं", "ना", "ના", "નહીં", "નથી"}

# Order matters: safety first, then the most specific topics.
INTENT_ORDER = [
	"safety_distress",
	"safety_personal",
	"safety_unsafe",
	"more_video",
	"parental",
	"safety_unkind",
	"bye",
	"thanks",
	"how_are_you",
	"identity",
	"help",
	"joke",
	"fact",
	"draw",
	"habits",
	"stars",
	"streak",
	"mission",
	"video",
	"feeling_sad",
	"feeling_scared",
	"feeling_bored",
	"greeting",
	"feeling_good",
]

SAFETY_INTENTS = {"safety_distress", "safety_personal", "safety_unsafe", "safety_unkind", "parental", "more_video"}

_LATIN = re.compile(r"[a-z]")
_PHONE = re.compile(r"(?:\d[\s-]?){6,}")
_EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+")
_URL = re.compile(r"(https?://|www\.)", re.IGNORECASE)
_NAME_OK = re.compile(r"^[^\W\d_]{1,20}$", re.UNICODE)
_LETTER = re.compile(r"[^\W\d_]", re.UNICODE)
_PLACEHOLDER = re.compile(r"\{(\w+)\}")
_ASKS_FOR_PRIVATE = re.compile(
	r"\b(tell|give|send|share|what is|what's)\b.{0,20}\byour\b.{0,15}\b(address|phone|number|password|photo|picture|school|location|email)\b",
	re.IGNORECASE,
)


def normalize(text: str) -> str:
	text = unicodedata.normalize("NFC", text or "").casefold()
	text = re.sub(r"[^\w\sऀ-ॿ઀-૿]", " ", text)
	return re.sub(r"\s+", " ", text).strip()


def _matches(text: str, keyword: str) -> bool:
	if _LATIN.search(keyword):
		return re.search(rf"(?<![a-z]){re.escape(keyword)}(?![a-z])", text) is not None
	return keyword in text


def safe_first_name(display_name: str | None) -> str:
	"""The first word of the parent-set display name, letters only, or ''."""
	first = (display_name or "").strip().split(" ")[0] if display_name else ""
	return first if _NAME_OK.fullmatch(first) else ""


def detect_intent(raw_text: str, context_intent: str | None = None) -> str:
	if _PHONE.search(raw_text or "") or _EMAIL.search(raw_text or ""):
		return "safety_personal"
	text = normalize(raw_text)
	if not text or not _LETTER.search(text) or len(text) < 2:
		return "unclear"
	for intent in INTENT_ORDER[:6]:  # safety and parental rules always win
		if any(_matches(text, keyword) for keyword in KEYWORDS[intent]):
			return intent
	if text in YES_WORDS or (len(text.split()) <= 3 and any(_matches(text, w) for w in YES_WORDS)
			and not any(_matches(text, w) for w in NO_WORDS)):
		if context_intent in FOLLOW_UPS:
			return FOLLOW_UPS[context_intent]
		if text in YES_WORDS:
			return "yes_generic"
	if text in NO_WORDS:
		return "no_generic"
	for intent in INTENT_ORDER[6:]:
		if any(_matches(text, keyword) for keyword in KEYWORDS[intent]):
			return intent
	if len(text.split()) == 1 and len(text) <= 3:
		return "unclear"
	return "fallback"


def _resolve(intent: str, ctx: ChildContext) -> str:
	"""Turn a topic into the catalogue key that fits the child's real state."""
	if intent == "mission":
		if not ctx.mission_title:
			return "mission_none"
		return {
			"pending_parent_approval": "mission_waiting",
			"approved": "mission_approved",
			"rejected": "mission_retry",
		}.get(ctx.mission_status or "", "mission_active")
	if intent == "video":
		if ctx.video_exhausted is None and ctx.video_remaining_seconds is None:
			return "video_unknown"
		if ctx.video_exhausted:
			return "video_exhausted"
		if (ctx.video_remaining_seconds or 0) >= 60:
			return "video_left"
		if ctx.video_earned_today_seconds:
			return "video_exhausted"
		return "video_none"
	if intent == "streak":
		return "streak_some" if (ctx.streak_days or 0) >= 2 else "streak_none"
	return intent


def validate_reply(text: str, allowed_numbers: set[str]) -> bool:
	"""Independent output check. Authored lines always pass; this guards
	against a future catalogue edit or placeholder value that would not."""
	if not text or len(text) > MAX_REPLY_CHARS:
		return False
	if _URL.search(text) or _EMAIL.search(text) or _PLACEHOLDER.search(text):
		return False
	if _ASKS_FOR_PRIVATE.search(text):
		return False
	for number in re.findall(r"\d+", text):
		if number not in allowed_numbers:
			return False
	return True


def _suggestions(key: str) -> list[str]:
	topic = key.split("_")[0]
	return [s for s in SUGGESTION_KEYS if s != topic][:3]


def compose_reply(
	raw_text: str,
	locale: str,
	ctx: ChildContext,
	*,
	context_intent: str | None = None,
	rng: random.Random | None = None,
) -> Reply:
	loc: Locale = locale if locale in SUPPORTED_LOCALES else "en"  # type: ignore[assignment]
	rng = rng or random.Random()
	intent = detect_intent(raw_text, context_intent)
	key = _resolve(intent, ctx)

	name = ctx.first_name or FRIEND[loc]
	minutes = str(max(0, (ctx.video_remaining_seconds or 0) // 60))
	streak = str(ctx.streak_days or 0)
	mission = (ctx.mission_title or "").strip()[:60]
	values = {"name": name, "minutes": minutes, "streak": streak, "mission": mission}

	line = rng.choice(CATALOGUE[key][loc])
	text = line.format(**values)
	allowed = set(re.findall(r"\d+", line)) | {minutes, streak} | set(re.findall(r"\d+", mission + name))
	if not validate_reply(text, allowed):
		key = "safe_fallback"
		text = CATALOGUE[key][loc][0]

	return Reply(
		text=text,
		mood=MOODS.get(key, "talking"),
		intent=key,
		follow_up=FOLLOW_UPS.get(key),
		safety="redirected" if intent in SAFETY_INTENTS else "ok",
		suggestions=_suggestions(key),
	)
