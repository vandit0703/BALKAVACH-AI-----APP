"""Panda conversation engine and endpoint: safety, languages, real state, limits."""

import random
import re
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.services import companion_chat_service as svc
from app.services.companion_chat_service import CATALOGUE, ChildContext, compose_reply, detect_intent, validate_reply

DEVANAGARI = re.compile("[ऀ-ॿ]")
GUJARATI = re.compile("[઀-૿]")


def reply(text, locale="en", ctx=ChildContext(first_name="Aarav"), **kw):
	return compose_reply(text, locale, ctx, rng=random.Random(1), **kw)


# --------------------------------------------------------------------- catalogue


def test_every_catalogue_key_has_all_three_languages_in_the_right_script():
	for key, by_locale in CATALOGUE.items():
		assert set(by_locale) == {"en", "hi", "gu"}, key
		for line in by_locale["hi"]:
			assert DEVANAGARI.search(line), (key, line)
		for line in by_locale["gu"]:
			assert GUJARATI.search(line), (key, line)


def test_gujarati_replies_use_the_respectful_form_like_the_app_ui():
	# The app addresses the child with તમે; Panda must not switch to તું.
	informal = re.compile(r"(^|[^઀-૿])(તું|તારું|તારો|તારી|તને|તેં)(?![઀-૿])|તારા (વડીલ|મિશન|માટે|પર)")
	for key, by_locale in CATALOGUE.items():
		for line in by_locale["gu"]:
			assert not informal.search(line), (key, line)


def test_every_authored_line_passes_the_output_validator():
	values = {"name": "Aarav", "mission": "Tidy toys", "minutes": "15", "streak": "4"}
	for key, by_locale in CATALOGUE.items():
		for lines in by_locale.values():
			for line in lines:
				allowed = set(re.findall(r"\d+", line)) | {"15", "4"}
				assert validate_reply(line.format(**values), allowed), (key, line)


def test_no_authored_line_asks_for_personal_information():
	asks = re.compile(r"\b(your|tumhara|tera) (address|phone|password|photo|location|school)\b", re.I)
	for by_locale in CATALOGUE.values():
		for line in by_locale["en"]:
			assert not asks.search(line), line


# --------------------------------------------------------------------- safety


@pytest.mark.parametrize(
	"text",
	[
		"my phone number is 98765 43210",
		"my email is kid@example.com",
		"my address is 12 Park Street",
		"what is your password",
		"मेरा पता बताऊँ?",
		"મારું સરનામું કહું?",
	],
)
def test_personal_information_is_redirected(text):
	result = reply(text)
	assert result.intent == "safety_personal"
	assert result.safety == "redirected"
	assert "98765" not in result.text and "@" not in result.text


@pytest.mark.parametrize(
	"text,intent",
	[
		("can I play with fire", "safety_unsafe"),
		("I want to use a knife", "safety_unsafe"),
		("should I meet a stranger", "safety_unsafe"),
		("माचिस से खेलूँ?", "safety_unsafe"),
		("અજાણ્યા માણસને મળું?", "safety_unsafe"),
		("someone hit me", "safety_distress"),
		("i want to die", "safety_distress"),
		("मुझे मारा", "safety_distress"),
		("you are stupid", "safety_unkind"),
	],
)
def test_unsafe_prompts_get_a_safe_redirect(text, intent):
	result = reply(text)
	assert result.intent == intent
	assert result.safety == "redirected"
	assert result.mood in {"concerned", "talking"}


def test_safety_wins_over_a_friendly_topic_in_the_same_sentence():
	assert detect_intent("tell me a joke about playing with fire") == "safety_unsafe"


def test_panda_never_repeats_the_childs_words():
	secret = "Zorblax"
	for text in [f"my name is {secret}", f"tell me a joke {secret}", f"{secret} {secret}"]:
		assert secret not in reply(text).text


def test_a_bad_line_is_replaced_by_the_safe_fallback(monkeypatch):
	monkeypatch.setitem(CATALOGUE, "joke", {loc: ["Visit www.example.com now"] for loc in ("en", "hi", "gu")})
	result = reply("tell me a joke")
	assert result.intent == "safe_fallback"
	assert "www" not in result.text


# --------------------------------------------------------------------- video time and parental control


def test_more_video_is_never_granted_even_with_time_left():
	for ctx in [ChildContext(video_exhausted=True, video_remaining_seconds=0),
				ChildContext(video_exhausted=False, video_remaining_seconds=1200)]:
		result = reply("give me more video time please", ctx=ctx)
		assert result.intent == "more_video"
		assert result.safety == "redirected"


def test_exhausted_video_time_makes_panda_sleepy_and_promises_nothing():
	result = reply("can I watch a video", ctx=ChildContext(video_exhausted=True, video_remaining_seconds=0,
		video_earned_today_seconds=900))
	assert result.intent == "video_exhausted"
	assert result.mood == "sleepy"


def test_remaining_minutes_are_the_real_figure():
	result = reply("how much video time", ctx=ChildContext(video_exhausted=False, video_remaining_seconds=900))
	assert result.intent == "video_left"
	assert "15" in result.text


def test_unknown_allowance_never_guesses():
	assert reply("video time?", ctx=ChildContext()).intent == "video_unknown"


def test_parent_settings_cannot_be_changed_by_panda():
	for text in ["turn off the parent pin", "hack the settings", "पैरेंट मोड बंद करो"]:
		result = reply(text)
		assert result.intent == "parental", text


def test_stars_are_never_promised():
	result = reply("will I get stars")
	assert result.intent == "stars"
	assert "grown-up" in result.text


# --------------------------------------------------------------------- missions, streaks, names


@pytest.mark.parametrize(
	"status,expected",
	[(None, "mission_none"), ("in_progress", "mission_active"), ("pending_parent_approval", "mission_waiting"),
	 ("approved", "mission_approved"), ("rejected", "mission_retry")],
)
def test_mission_reply_matches_real_status(status, expected):
	ctx = ChildContext(mission_title="Tidy toys" if status else None, mission_status=status)
	result = reply("what is my mission", ctx=ctx)
	assert result.intent == expected
	if status:
		assert "Tidy toys" in result.text


def test_streak_uses_the_real_count():
	assert "4" in reply("my streak", ctx=ChildContext(streak_days=4)).text
	assert reply("my streak", ctx=ChildContext(streak_days=0)).intent == "streak_none"


def test_first_name_is_used_and_sanitised():
	assert svc.safe_first_name("Aarav Patel") == "Aarav"
	assert svc.safe_first_name("<script>") == ""
	assert svc.safe_first_name("R2D2") == ""
	assert "Aarav" in compose_reply("hello", "en", ChildContext(first_name="Aarav"), rng=random.Random(0)).text
	assert "friend" in compose_reply("hello", "en", ChildContext(), rng=random.Random(0)).text


# --------------------------------------------------------------------- conversation context and languages


def test_yes_after_a_joke_tells_another_joke():
	first = reply("tell me a joke")
	assert first.follow_up == "joke"
	assert reply("yes", context_intent=first.follow_up).intent == "joke"
	assert reply("yes").intent == "yes_generic"
	assert reply("no", context_intent="joke").intent == "no_generic"


@pytest.mark.parametrize(
	"text,locale,intent,script",
	[
		("tell me a joke", "en", "joke", None),
		("मुझे एक चुटकुला सुनाओ", "hi", "joke", DEVANAGARI),
		("મને જોક કહે", "gu", "joke", GUJARATI),
		("तुम कैसे हो", "hi", "how_are_you", DEVANAGARI),
		("કેમ છો", "gu", "how_are_you", GUJARATI),
		("kem cho panda", "gu", "how_are_you", GUJARATI),
		("मेरा मिशन क्या है", "hi", "mission_none", DEVANAGARI),
		("મારું મિશન શું છે", "gu", "mission_none", GUJARATI),
	],
)
def test_three_languages(text, locale, intent, script):
	result = reply(text, locale=locale)
	assert result.intent == intent
	if script:
		assert script.search(result.text)


CHIP_LABELS = {  # balkavach-frontend/lib/l10n/app_{en,hi,gu}.arb pandaSuggest*
	"mission": ["My mission", "मेरा मिशन", "મારું મિશન"],
	"video": ["Video time", "वीडियो टाइम", "વિડિયો સમય"],
	"joke": ["Tell a joke", "चुटकुला सुनाओ", "જોક કહો"],
	"fact": ["Fun fact", "मज़ेदार बात", "મજાની વાત"],
	"draw": ["Drawing idea", "ड्रॉइंग आइडिया", "ચિત્રનો આઇડિયા"],
	"stars": ["My stars", "मेरे स्टार", "મારા સ્ટાર"],
}


@pytest.mark.parametrize("topic", sorted(CHIP_LABELS))
def test_app_suggestion_chips_reach_their_topic_in_every_language(topic):
	for label in CHIP_LABELS[topic]:
		assert detect_intent(label) == topic, label


@pytest.mark.parametrize("text", ["", "   ", "??!!", "123", "a"])
def test_empty_or_unintelligible_input(text):
	assert detect_intent(text) == "unclear"


def test_unknown_topic_gets_a_gentle_fallback():
	result = reply("quantum spaceship banana engine")
	assert result.intent == "fallback"
	assert result.mood == "curious"


@pytest.mark.parametrize(
	"text,intent,catalogue_key",
	[
		("Tell me a joke", "joke", "joke"),
		("Tell me a story", "draw", "draw"),
		("Ask me a riddle", "fallback", "fallback"),
		("Let's play a game", "fallback", "fallback"),
		("Hello Panda", "greeting", "greeting"),
	],
)
def test_common_text_prompts_use_the_existing_authored_catalogue(text, intent, catalogue_key):
	result = compose_reply(text, "en", ChildContext(), rng=random.Random(0))
	assert result.intent == intent
	expected = {
		line.format(name="friend", mission="", minutes="0", streak="0")
		for line in CATALOGUE[catalogue_key]["en"]
	}
	assert result.text in expected


def test_unsupported_locale_falls_back_to_english():
	assert compose_reply("hello", "fr", ChildContext(), rng=random.Random(0)).text.startswith(("Hi", "Hello"))


# --------------------------------------------------------------------- endpoint


@pytest.fixture
def client(monkeypatch):
	from fastapi.testclient import TestClient

	from app.api.v1 import companion
	from app.core.dependencies import require_child
	from app.db.session import get_db
	from app.main import app

	child = SimpleNamespace(id=uuid4(), user_id=uuid4(), family_id=uuid4(), display_name="Aarav")
	monkeypatch.setattr(companion, "chat_limiter", companion.FixedWindowLimiter())
	monkeypatch.setattr(companion, "turn_cache", companion._TurnCache())
	monkeypatch.setattr(companion.panda_chat_access, "chat_allowed", lambda *_: True)
	calls = {"context": 0}

	def fake_context(session, c):
		calls["context"] += 1
		return ChildContext(first_name="Aarav", video_exhausted=True, video_remaining_seconds=0), "gu"

	monkeypatch.setattr(companion, "load_child_context", fake_context)
	app.dependency_overrides[require_child] = lambda: child
	app.dependency_overrides[get_db] = lambda: MagicMock()
	try:
		with TestClient(app) as test_client:
			yield test_client, calls
	finally:
		app.dependency_overrides.pop(require_child, None)
		app.dependency_overrides.pop(get_db, None)


def test_endpoint_replies_in_the_childs_language_with_real_state(client):
	http, _ = client
	response = http.post("/api/v1/companion/chat", json={"text": "video", "turn_id": str(uuid4())})
	assert response.status_code == 200
	body = response.json()
	assert body["locale"] == "gu"
	assert body["intent"] == "video_exhausted"
	assert body["mood"] == "sleepy"
	assert GUJARATI.search(body["reply"])


def test_duplicate_turn_is_answered_once(client):
	http, calls = client
	turn = str(uuid4())
	first = http.post("/api/v1/companion/chat", json={"text": "joke", "locale": "en", "turn_id": turn}).json()
	second = http.post("/api/v1/companion/chat", json={"text": "joke", "locale": "en", "turn_id": turn}).json()
	assert first == second
	assert calls["context"] == 1


def test_chat_endpoint_requires_parent_approval(client, monkeypatch):
	http, calls = client
	from app.api.v1 import companion

	monkeypatch.setattr(companion.panda_chat_access, "chat_allowed", lambda *_: False)
	response = http.post(
		"/api/v1/companion/chat",
		json={"text": "tell me a joke", "turn_id": str(uuid4())},
	)
	assert response.status_code == 403
	assert response.json()["error"]["code"] == "panda_chat_access_required"
	assert calls["context"] == 0


def test_chat_endpoint_rechecks_approval_before_returning_cached_turn(client, monkeypatch):
	http, calls = client
	from app.api.v1 import companion

	allowed = True
	monkeypatch.setattr(companion.panda_chat_access, "chat_allowed", lambda *_: allowed)
	turn_id = str(uuid4())
	first = http.post(
		"/api/v1/companion/chat",
		json={"text": "tell me a joke", "turn_id": turn_id},
	)
	assert first.status_code == 200
	allowed = False
	second = http.post(
		"/api/v1/companion/chat",
		json={"text": "tell me a joke", "turn_id": turn_id},
	)
	assert second.status_code == 403
	assert calls["context"] == 1


def test_rate_limit_returns_429(client):
	http, _ = client
	from app.api.v1.companion import CHAT_RATE_LIMIT

	for _ in range(CHAT_RATE_LIMIT):
		assert http.post("/api/v1/companion/chat", json={"text": "hi", "turn_id": str(uuid4())}).status_code == 200
	limited = http.post("/api/v1/companion/chat", json={"text": "hi", "turn_id": str(uuid4())})
	assert limited.status_code == 429


@pytest.mark.parametrize(
	"payload",
	[
		{"text": "", "turn_id": "00000000-0000-0000-0000-000000000001"},
		{"text": "x" * 301, "turn_id": "00000000-0000-0000-0000-000000000001"},
		{"text": "hi", "turn_id": "not-a-uuid"},
		{"text": "hi", "turn_id": "00000000-0000-0000-0000-000000000001", "locale": "fr"},
		{"text": "hi", "turn_id": "00000000-0000-0000-0000-000000000001", "context_intent": "DROP TABLE"},
	],
)
def test_invalid_requests_are_rejected(client, payload):
	http, _ = client
	assert http.post("/api/v1/companion/chat", json=payload).status_code == 422


def test_endpoint_requires_a_child_token():
	from fastapi.testclient import TestClient

	from app.db.session import get_db
	from app.main import app

	# No database here: only the missing bearer token is under test.
	app.dependency_overrides[get_db] = lambda: MagicMock()
	try:
		with TestClient(app) as http:
			response = http.post("/api/v1/companion/chat", json={"text": "hi", "turn_id": str(uuid4())})
	finally:
		app.dependency_overrides.pop(get_db, None)
	assert response.status_code == 401


def test_childs_text_is_not_logged(client, caplog):
	http, _ = client
	with caplog.at_level("DEBUG"):
		http.post("/api/v1/companion/chat", json={"text": "my secret word is pineapple", "turn_id": str(uuid4())})
	assert "pineapple" not in caplog.text
