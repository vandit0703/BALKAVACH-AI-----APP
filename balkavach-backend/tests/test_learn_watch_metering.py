"""Learn & Watch curated video links are metered through the one charging path.

A curated YouTube link is handed to the child only when it matches an eligible
catalogue video (``metered_video_id``) and the allowance is not exhausted. The
app then reports progress on that video with ``record_progress``, so time is
charged once, by the existing writer, and watch history is kept. A link that
cannot be metered is never handed out.

In-memory SQLite (tests/video_world.py) with test stand-ins for eligibility;
not PostgreSQL.
"""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import Boolean, DateTime, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from tests.video_world import MODELS, Base, ChildVideoDailyUsage, ChildVideoWatchHistory, Video, db, grant, make_child, tick  # noqa: F401


class EducationalContent(Base):
	__tablename__ = "educational_content"
	id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
	title: Mapped[str] = mapped_column(String, default="Curated")
	description: Mapped[str | None] = mapped_column(String)
	content_type: Mapped[str] = mapped_column(String, default="video")
	category_id: Mapped[UUID | None] = mapped_column(Uuid)
	language_code: Mapped[str] = mapped_column(String, default="en")
	content_url: Mapped[str | None] = mapped_column(String)
	thumbnail_url: Mapped[str | None] = mapped_column(String)
	video_id: Mapped[UUID | None] = mapped_column(Uuid)
	collection_id: Mapped[UUID | None] = mapped_column(Uuid)
	requires_entitlement: Mapped[bool] = mapped_column(Boolean, default=False)
	is_active: Mapped[bool] = mapped_column(Boolean, default=True)
	created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))


WORLD = {**MODELS, "EducationalContent": EducationalContent}


@pytest.fixture
def learn(db, monkeypatch):
	import app.api.v1.educational_content as endpoint

	monkeypatch.setattr(endpoint, "get_model", WORLD.__getitem__)
	monkeypatch.setattr(endpoint, "child_age", lambda child: 8)
	return db


def listing(db, child):
	from app.api.v1.educational_content import list_educational_content

	return {item.title: item for item in list_educational_content(limit=50, offset=0, child=child, session=db)}


def curated(db, title, url, **fields):
	db.add(EducationalContent(title=title, content_url=url, **fields))
	db.commit()


def test_a_curated_youtube_link_is_metered_by_its_catalogue_video(learn):
	child, video = make_child(learn, free_left=600)
	curated(learn, "Stars", f"https://www.youtube.com/watch?v={video.external_video_id}")

	item = listing(learn, child)["Stars"]

	assert item.metered_video_id == video.id
	assert item.content_url is not None


def test_a_link_with_no_catalogue_video_is_never_handed_out(learn):
	child, _ = make_child(learn, free_left=600)
	curated(learn, "Unknown", "https://youtu.be/ZZZZZZZZZZZ")
	curated(learn, "Direct stream", "https://cdn.example.com/lesson.mp4")

	items = listing(learn, child)

	for title in ("Unknown", "Direct stream"):
		assert items[title].content_url is None, title
		assert items[title].metered_video_id is None, title


def test_an_ineligible_catalogue_video_does_not_meter_the_link(learn, monkeypatch):
	import app.services.video_watch_history_service as history

	child, video = make_child(learn, free_left=600)
	curated(learn, "Stars", f"https://youtu.be/{video.external_video_id}")

	def refuse(session, child, video_id):
		raise HTTPException(status_code=403, detail="Video is not eligible for this child")

	monkeypatch.setattr(history, "_eligible_video", refuse)
	item = listing(learn, child)["Stars"]

	assert item.content_url is None
	assert item.metered_video_id is None


def test_zero_allowance_withholds_the_link_but_keeps_the_item(learn):
	child, video = make_child(learn, free_left=0)
	curated(learn, "Stars", f"https://youtu.be/{video.external_video_id}")

	item = listing(learn, child)["Stars"]

	assert item.content_url is None
	assert item.metered_video_id == video.id  # the app can show "time is up" for it


def test_a_parent_grant_makes_the_link_playable_again(learn):
	child, video = make_child(learn, free_left=0)
	curated(learn, "Stars", f"https://youtu.be/{video.external_video_id}")
	grant(learn, child, seconds=900)

	assert listing(learn, child)["Stars"].content_url is not None


def test_playback_charges_once_through_record_progress_and_keeps_history(learn):
	from app.services.video_watch_history_service import record_progress

	child, video = make_child(learn, free_left=600)
	curated(learn, "Stars", f"https://youtu.be/{video.external_video_id}")
	metered = listing(learn, child)["Stars"].metered_video_id

	tick(learn, child, 20)
	result = record_progress(learn, child, metered, 90, is_playing=True)

	usage = learn.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	assert result["accepted_seconds"] == 20
	assert usage.free_watched_seconds == 300 + 20  # make_child had used 300 of 900
	history = learn.query(ChildVideoWatchHistory).filter_by(child_id=child.id, video_id=video.id).one()
	assert history.last_position_seconds == 90


def test_articles_and_other_links_are_unchanged(learn):
	child, _ = make_child(learn, free_left=0)
	curated(learn, "Read me", "https://example.org/article", content_type="article")

	item = listing(learn, child)["Read me"]

	assert item.content_url == "https://example.org/article"
	assert item.metered_video_id is None
