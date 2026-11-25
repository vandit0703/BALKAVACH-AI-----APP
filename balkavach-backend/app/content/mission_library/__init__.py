"""The Mission Library: daily-mission concepts grouped by developmental category (not by weekday).

Plain data. Each concept becomes one ``daily_mission_templates`` row (``theme`` = its category, slug prefix ``lib_``)
with nine ``daily_mission_variations`` rows (3 age bands x en/gu/hi), written by the existing seeder
(``python -m app.cli seed-daily-missions --source library``). Nothing is written by importing this package.

Concepts are authored in a compact form (see ``batch_001.py``) and converted by :func:`to_mission` into exactly the
dict shape the core catalogue uses (``app.content.daily_missions``), so ``variation_payload``, the validator, the
seeder, the compare and the audit all treat both catalogues the same way.

Compact concept fields:

* ``slug``          ``lib_<short_name>``; stable, never renamed (it is the seeding identity).
* ``category``      one of :data:`CATEGORIES`.
* ``mission_type``  ``offline`` | ``interactive`` | ``creative`` (the existing check constraint).
* ``mechanic``      short unique key for what the child actually does; ``summary`` one sentence for reviewers.
* ``review``        per-language translation review status: ``pending`` | ``approved``. Hindi and Gujarati written
                    by the catalogue author start ``pending``; the seeder will not publish a pending concept.
* ``ages``          ``4_6`` / ``7_10`` / ``11_15`` -> ``minutes``, ``rationale`` (why this is right for the age),
                    ``parent_involvement`` and ``en`` / ``hi`` / ``gu`` text blocks with ``title``, ``description``,
                    ``objective``, ``steps``, ``alt``, ``materials``, ``safety``, ``observe``, ``submit``, ``show``,
                    ``parent_check`` (same meanings as the core catalogue).
"""

from __future__ import annotations

from typing import Any

from app.content.mission_library import batch_001, batch_002

LIBRARY_PREFIX = "lib_"
AGE_BANDS = ("4_6", "7_10", "11_15")
LOCALES = ("en", "gu", "hi")

# The 24 developmental categories. Stored as ``daily_mission_templates.theme`` (max 40 characters).
CATEGORIES: dict[str, dict[str, str]] = {
	"logic_problem_solving": {"en": "Logical thinking and problem-solving", "hi": "तार्किक सोच और समस्या-समाधान", "gu": "તાર્કિક વિચાર અને સમસ્યા-ઉકેલ"},
	"everyday_math": {"en": "Mathematics in everyday life", "hi": "रोज़मर्रा का गणित", "gu": "રોજિંદું ગણિત"},
	"language_vocabulary": {"en": "Language and vocabulary", "hi": "भाषा और शब्द-भंडार", "gu": "ભાષા અને શબ્દભંડોળ"},
	"reading_storytelling": {"en": "Reading and storytelling", "hi": "पढ़ना और कहानी कहना", "gu": "વાંચન અને વાર્તાકથન"},
	"writing_communication": {"en": "Writing and communication", "hi": "लेखन और संवाद", "gu": "લેખન અને સંવાદ"},
	"science_observation": {"en": "Science and observation", "hi": "विज्ञान और अवलोकन", "gu": "વિજ્ઞાન અને નિરીક્ષણ"},
	"nature_environment": {"en": "Nature and environmental awareness", "hi": "प्रकृति और पर्यावरण", "gu": "પ્રકૃતિ અને પર્યાવરણ"},
	"creativity_imagination": {"en": "Creativity and imagination", "hi": "रचनात्मकता और कल्पना", "gu": "સર્જનાત્મકતા અને કલ્પના"},
	"art_craft": {"en": "Art and craft", "hi": "कला और शिल्प", "gu": "કલા અને હસ્તકલા"},
	"music_rhythm": {"en": "Music and rhythm", "hi": "संगीत और लय", "gu": "સંગીત અને લય"},
	"movement_coordination": {"en": "Physical movement and coordination", "hi": "शारीरिक गतिविधि और तालमेल", "gu": "શારીરિક હલનચલન અને સંકલન"},
	"health_hygiene": {"en": "Healthy habits and hygiene", "hi": "स्वस्थ आदतें और स्वच्छता", "gu": "સ્વસ્થ ટેવો અને સ્વચ્છતા"},
	"emotional_intelligence": {"en": "Emotional intelligence", "hi": "भावनात्मक समझ", "gu": "ભાવનાત્મક સમજ"},
	"empathy_kindness": {"en": "Empathy and kindness", "hi": "सहानुभूति और दया", "gu": "સહાનુભૂતિ અને દયા"},
	"social_teamwork": {"en": "Social skills and teamwork", "hi": "सामाजिक कौशल और टीमवर्क", "gu": "સામાજિક કૌશલ્ય અને ટીમવર્ક"},
	"independence_self_care": {"en": "Independence and self-care", "hi": "आत्मनिर्भरता और अपनी देखभाल", "gu": "આત્મનિર્ભરતા અને સ્વ-સંભાળ"},
	"responsibility_household": {"en": "Responsibility and household contribution", "hi": "ज़िम्मेदारी और घर में योगदान", "gu": "જવાબદારી અને ઘરમાં યોગદાન"},
	"money_basics": {"en": "Financial awareness and money basics", "hi": "पैसों की समझ", "gu": "પૈસાની સમજ"},
	"digital_safety": {"en": "Digital literacy and online safety", "hi": "डिजिटल समझ और ऑनलाइन सुरक्षा", "gu": "ડિજિટલ સમજ અને ઓનલાઇન સુરક્ષા"},
	"culture_civics": {"en": "Indian culture, traditions and civic awareness", "hi": "भारतीय संस्कृति, परंपराएँ और नागरिक समझ", "gu": "ભારતીય સંસ્કૃતિ, પરંપરા અને નાગરિક સમજ"},
	"memory_concentration": {"en": "Memory and concentration", "hi": "याददाश्त और एकाग्रता", "gu": "યાદશક્તિ અને એકાગ્રતા"},
	"critical_thinking": {"en": "Critical thinking and decision-making", "hi": "आलोचनात्मक सोच और निर्णय", "gu": "વિવેચનાત્મક વિચાર અને નિર્ણય"},
	"practical_life_skills": {"en": "Practical life skills", "hi": "व्यावहारिक जीवन कौशल", "gu": "વ્યવહારુ જીવન કૌશલ્ય"},
	"observation_exploration": {"en": "Observation and exploration", "hi": "अवलोकन और खोज", "gu": "નિરીક્ષણ અને શોધ"},
}

# Which concept files make up the library, in order. A new batch is one more module here.
BATCHES = (batch_001, batch_002)

CONCEPTS: tuple[dict[str, Any], ...] = tuple(concept for batch in BATCHES for concept in batch.CONCEPTS)


def to_mission(concept: dict[str, Any]) -> dict[str, Any]:
	"""A compact concept as a core-catalogue mission dict (the shape ``variation_payload`` reads)."""
	# Imported here: the reward constants live in a service module, and this package must stay import-light.
	from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD

	ages = {}
	for band, age in concept["ages"].items():
		ages[band] = {
			"minutes": age["minutes"],
			"rationale": age.get("rationale", ""),
			"parent_involvement": age.get("parent_involvement", ""),
			"locales": {locale: dict(age[locale]) for locale in LOCALES if locale in age},
		}
	return {
		"slug": concept["slug"],
		"theme": concept["category"],
		"mission_type": concept["mission_type"],
		"skill": concept["category"],
		"library": True,
		"review": dict(concept.get("review", {})),
		# Display only: payouts always use mission_rewards through the approval + ledger pipeline.
		"star_reward": MISSION_STAR_REWARD,
		"xp_reward": MISSION_XP_REWARD,
		"ages": ages,
	}


LIBRARY_MISSIONS: tuple[dict[str, Any], ...] = tuple(to_mission(concept) for concept in CONCEPTS)

# slug -> activity entry, in the same shape as ``app.content.daily_missions.activities.ACTIVITIES``.
LIBRARY_ACTIVITIES: dict[str, dict[str, str]] = {
	concept["slug"]: {
		"mechanic": concept.get("mechanic", ""),
		"summary": concept.get("summary", ""),
		"evidence": "design_assumption",
	}
	for concept in CONCEPTS
}


def is_publishable_translation(mission: dict[str, Any]) -> bool:
	"""True only when every non-English language has been approved by a native-speaker reviewer."""
	review = mission.get("review") or {}
	return all(review.get(locale) == "approved" for locale in LOCALES if locale != "en")
