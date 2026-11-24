import os
from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, Integer, JSON, String, Uuid, create_engine
from sqlalchemy.orm import DeclarativeBase, mapped_column, sessionmaker

os.environ.setdefault("DATABASE_URL", "sqlite://")

import app.db.base as db_base
from app.services import admin_service
from app.services import youtube_review_service as svc


class Base(DeclarativeBase):
    pass


class Trusted(Base):
    __tablename__ = "youtube_trusted_channels"
    id = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    channel_id = mapped_column(String(64), unique=True)
    channel_title = mapped_column(String(200), nullable=True)
    thumbnail_url = mapped_column(String(1000), nullable=True)
    age_min = mapped_column(Integer, nullable=True)
    age_max = mapped_column(Integer, nullable=True)
    language_code = mapped_column(String(10), nullable=True)
    category_id = mapped_column(Uuid(as_uuid=True), nullable=True)
    rights_status = mapped_column(String(20), default="cleared")
    is_active = mapped_column(Boolean, default=True)
    created_by = mapped_column(Uuid(as_uuid=True), nullable=True)
    notes = mapped_column(String, nullable=True)
    created_at = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))


class Video(Base):
    __tablename__ = "videos"
    id = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    title = mapped_column(String(200), default="v")
    video_source = mapped_column(String(20), default="youtube")
    external_video_id = mapped_column(String(20), nullable=True)
    duration_seconds = mapped_column(Integer, default=60)
    age_min = mapped_column(Integer, default=3)
    age_max = mapped_column(Integer, default=5)
    language_code = mapped_column(String(10), default="en")
    category_id = mapped_column(Uuid(as_uuid=True), nullable=True)
    content_rating = mapped_column(String(30), default="educational")
    is_published = mapped_column(Boolean, default=True)


class Review(Base):
    __tablename__ = "youtube_content_reviews"
    id = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    video_id = mapped_column(Uuid(as_uuid=True))
    youtube_video_id = mapped_column(String(20))
    channel_id = mapped_column(String(64))
    status = mapped_column(String(20), default="approved")
    screening_flags = mapped_column(JSON, nullable=True, default=list)
    rights_status = mapped_column(String(20), default="cleared")
    made_for_kids = mapped_column(Boolean, nullable=True, default=True)
    publication_source = mapped_column(String(20), default="automatic")


class Audit(Base):
    __tablename__ = "audit_logs"
    id = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    actor_user_id = mapped_column(Uuid(as_uuid=True), nullable=True)
    action = mapped_column(String(80))
    entity_type = mapped_column(String(40))
    entity_id = mapped_column(Uuid(as_uuid=True), nullable=True)
    details = mapped_column(JSON, nullable=True)
    created_at = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))


MODELS = {
    "YouTubeTrustedChannel": Trusted,
    "YouTubeContentReview": Review,
    "Video": Video,
    "AuditLog": Audit,
}

orig = (svc.get_model, svc.has_model, admin_service.get_model, db_base.get_model, db_base.has_model)
svc.get_model = lambda name: MODELS[name]
svc.has_model = lambda name: name in MODELS
admin_service.get_model = lambda name: MODELS[name]
db_base.get_model = lambda name: MODELS[name]
db_base.has_model = lambda name: name in MODELS
try:
    engine = create_engine("sqlite://")
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine, expire_on_commit=False)
    db = Session()
    channel = Trusted(channel_id="UC1111111111111111111111", channel_title="Kids", age_min=3, age_max=5, rights_status="cleared", is_active=True)
    db.add(channel)
    db.flush()
    v1 = Video(age_min=3, age_max=5, external_video_id="aaaaaaaaaaa")
    v2 = Video(age_min=3, age_max=5, external_video_id="bbbbbbbbbbb")
    db.add_all([v1, v2])
    db.flush()
    db.add_all([
        Review(video_id=v1.id, youtube_video_id="aaaaaaaaaaa", channel_id=channel.channel_id, status="approved"),
        Review(video_id=v2.id, youtube_video_id="bbbbbbbbbbb", channel_id=channel.channel_id, status="pending_review"),
    ])
    db.commit()

    req = SimpleNamespace(model_dump=lambda exclude_unset=True: {"age_min": 9, "age_max": 12})
    svc.update_trusted_channel(db, SimpleNamespace(id=uuid4()), channel.channel_id, req)

    db2 = Session()
    ages = sorted((v.age_min, v.age_max) for v in db2.query(Video).all())
    ch = db2.query(Trusted).one()
    assert (ch.age_min, ch.age_max) == (9, 12)
    assert ages == [(9, 12), (9, 12)]
    print("VERIFY_OK", ages)
finally:
    (svc.get_model, svc.has_model, admin_service.get_model, db_base.get_model, db_base.has_model) = orig
