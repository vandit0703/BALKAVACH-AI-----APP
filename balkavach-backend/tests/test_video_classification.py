"""Short/regular classification. Runs without a database.

The SQL clauses are checked against the Python rule on a real (in-memory
SQLite) engine, so the feeds and the API labels can never disagree.
"""

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Column, Integer, MetaData, String, Table, create_engine, select

from app.api.v1 import videos as video_routes
from app.core.dependencies import require_child
from app.db.session import get_db
from app.main import app
from app.services.video_classification import (
	SHORT_MAX_SECONDS,
	SHORT_MIN_SECONDS,
	known_duration_or_none,
	regular_clause,
	short_clause,
	video_format,
)


@pytest.mark.parametrize(
	("source", "seconds", "expected"),
	[
		("hosted", 1, "short"),
		("hosted", 30, "short"),
		("hosted", 60, "short"),
		("hosted", 61, "regular"),
		("hosted", 3600, "regular"),
		("youtube", 2, "short"),
		("youtube", 30, "short"),
		("youtube", 60, "short"),
		("youtube", 61, "regular"),
		# YouTube imports store 1 when YouTube gave no duration.
		("youtube", 1, "unknown"),
		("youtube", None, "unknown"),
		("hosted", None, "unknown"),
		("hosted", 0, "unknown"),
		("external", -5, "unknown"),
	],
)
def test_duration_rule(source, seconds, expected):
	assert video_format(source, seconds) == expected


def test_bounds_are_the_documented_ones():
	assert (SHORT_MIN_SECONDS, SHORT_MAX_SECONDS) == (1, 60)


def test_unknown_duration_is_never_reported_as_a_number():
	assert known_duration_or_none("youtube", 1) is None
	assert known_duration_or_none("youtube", 45) == 45
	assert known_duration_or_none("hosted", 1) == 1


ROWS = [
	(source, seconds)
	for source in ("hosted", "youtube", "external", None)
	for seconds in (None, -1, 0, 1, 2, 30, 59, 60, 61, 120, 86400)
]


@pytest.fixture
def video_table():
	engine = create_engine("sqlite://")
	meta = MetaData()
	table = Table(
		"videos",
		meta,
		Column("id", Integer, primary_key=True),
		Column("video_source", String),
		Column("duration_seconds", Integer),
	)
	meta.create_all(engine)
	with engine.begin() as connection:
		connection.execute(
			table.insert(),
			[{"id": i, "video_source": s, "duration_seconds": d} for i, (s, d) in enumerate(ROWS)],
		)
	yield engine, table
	engine.dispose()


def test_sql_clauses_match_the_python_rule_exactly(video_table):
	engine, table = video_table
	columns = table.c
	with engine.connect() as connection:
		shorts = {row.id for row in connection.execute(select(table.c.id).where(short_clause(columns)))}
		regular = {row.id for row in connection.execute(select(table.c.id).where(regular_clause(columns)))}
	expected_shorts = {i for i, (s, d) in enumerate(ROWS) if video_format(s, d) == "short"}
	assert shorts == expected_shorts
	# Every row is in exactly one feed: none lost to NULL logic, none in both.
	assert shorts.isdisjoint(regular)
	assert shorts | regular == set(range(len(ROWS)))


# --- Endpoint wiring (the database-backed suite covers real queries) ---------


def _video(source="youtube", seconds=45):
	return SimpleNamespace(
		id=uuid4(),
		title="Bubbles",
		description=None,
		thumbnail_url=None,
		duration_seconds=seconds,
		category_id=None,
		language_code="en",
		content_rating="educational",
		video_source=source,
		external_video_id="abcdefghijk" if source == "youtube" else None,
	)


@pytest.fixture
def client(monkeypatch):
	calls = []

	def fake_feed(session, child, category_id, limit, offset, video_format=None):
		calls.append({"video_format": video_format, "limit": limit, "offset": offset})
		return [_video(seconds=45), _video(seconds=1), _video(source="hosted", seconds=600)]

	monkeypatch.setattr(video_routes, "eligible_feed", fake_feed)
	monkeypatch.setattr(video_routes, "_channel_names", lambda session, videos: {})
	app.dependency_overrides[require_child] = lambda: SimpleNamespace(id=uuid4())
	app.dependency_overrides[get_db] = lambda: None
	try:
		yield TestClient(app), calls
	finally:
		app.dependency_overrides.clear()


def test_each_endpoint_asks_for_its_own_format_and_keeps_paging(client):
	test_client, calls = client
	assert test_client.get("/api/v1/videos/shorts?limit=5&offset=10").status_code == 200
	assert test_client.get("/api/v1/videos/feed?limit=7&offset=0").status_code == 200
	assert calls == [
		{"video_format": "short", "limit": 5, "offset": 10},
		{"video_format": "regular", "limit": 7, "offset": 0},
	]


def test_items_carry_the_backend_label_and_never_a_guessed_duration(client):
	test_client, _ = client
	items = test_client.get("/api/v1/videos/shorts").json()
	assert [(i["video_format"], i["duration_seconds"]) for i in items] == [
		("short", 45),
		("unknown", None),
		("regular", 600),
	]
	# Hosted media never carries a playable URL in a feed.
	assert all("video_url" not in item and "storage_key" not in item for item in items)
	assert items[2]["youtube_video_id"] is None


def test_feeds_require_a_signed_in_child():
	# Only the database is stubbed; the real authentication dependency runs.
	app.dependency_overrides[get_db] = lambda: None
	try:
		test_client = TestClient(app)
		for path in ("/api/v1/videos/shorts", "/api/v1/videos/feed"):
			assert test_client.get(path).status_code == 401
	finally:
		app.dependency_overrides.clear()
