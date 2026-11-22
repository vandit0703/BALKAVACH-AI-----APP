from pathlib import Path
import re

path = Path('app/services/youtube_review_service.py')
text = path.read_text(encoding='utf-8')

# 1) import fix
old_import = 'from app.services.video_classification import regular_clause, short_clause, video_format'
new_import = 'from app.services.video_classification import known_duration_or_none, regular_clause, short_clause, video_format'
if old_import not in text:
    raise SystemExit('import line not found')
text = text.replace(old_import, new_import)

# 2) replace list_trusted_channels with stats-capable version
old_list = '''def list_trusted_channels(session: Session, limit: int, offset: int) -> list[Any]:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	return (
		session.query(Trusted)
		.order_by(Trusted.is_active.desc(), Trusted.channel_title, Trusted.channel_id)
		.offset(offset)
		.limit(limit)
		.all()
	)
'''
new_list = '''def channel_status(channel) -> str:
	"""Display status derived from existing columns."""
	return "approved" if getattr(channel, "is_active", False) else "revoked"


def _channel_to_public_dict(channel, *, status: str | None = None, counts: dict[str, int] | None = None, last_discovery_at=None) -> dict[str, Any]:
	counts = counts or {}
	return {
		"id": channel.id,
		"channel_id": channel.channel_id,
		"channel_title": channel.channel_title,
		"thumbnail_url": channel.thumbnail_url,
		"age_min": channel.age_min,
		"age_max": channel.age_max,
		"language_code": channel.language_code,
		"category_id": channel.category_id,
		"rights_status": channel.rights_status,
		"is_active": channel.is_active,
		"created_by": channel.created_by,
		"notes": channel.notes,
		"created_at": utc_aware(channel.created_at) if channel.created_at else None,
		"updated_at": utc_aware(channel.updated_at) if channel.updated_at else None,
		"status": status or channel_status(channel),
		"total_videos": counts.get("total_videos", counts.get("discovered")),
		"shorts_count": counts.get("shorts_count"),
		"long_videos_count": counts.get("long_videos_count"),
		"last_discovery_at": utc_aware(last_discovery_at) if last_discovery_at else None,
	}


def _enrich_trusted_channel(session: Session, channel) -> dict[str, Any]:
	counts = _channel_video_counts(session, channel.channel_id)
	last_discovery_at = _channel_last_discovered(session, channel.channel_id)
	return _channel_to_public_dict(channel, status=channel_status(channel), counts=counts, last_discovery_at=last_discovery_at)


def list_trusted_channels(session: Session, limit: int, offset: int, *, include_stats: bool = False) -> list[Any]:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	rows = (
		session.query(Trusted)
		.order_by(Trusted.is_active.desc(), Trusted.channel_title, Trusted.channel_id)
		.offset(offset)
		.limit(limit)
		.all()
	)
	if not include_stats:
		return rows
	return [_enrich_trusted_channel(session, row) for row in rows]
'''
if old_list not in text:
    raise SystemExit('list_trusted_channels block not found')
text = text.replace(old_list, new_list)

# add update_trusted_channel after untrust_channel
marker = '''\n\ndef discover(
	session: Session,
	actor,
	client: YouTubeClient,
	request: YouTubeDiscoverRequest,'''
update_fn = r'''

def update_trusted_channel(session: Session, actor, channel_id: str, request) -> Any:
	Trusted = get_model("YouTubeTrustedChannel")
	_require_tables("YouTubeTrustedChannel")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).with_for_update().one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	changes = request.model_dump(exclude_unset=True)
	if "category_id" in changes and changes["category_id"] is not None:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == changes["category_id"], VideoCategory.is_active.is_(True)
		).first():
			raise APIError(404, "video_category_not_found", "Video category not found")
	for field in ("channel_title", "age_min", "age_max", "category_id", "rights_status", "is_active", "notes"):
		if field in changes:
			setattr(channel, field, changes[field])
	if "thumbnail_url" in changes:
		channel.thumbnail_url = safe_channel_thumbnail_url(changes["thumbnail_url"])
	if "language_code" in changes:
		channel.language_code = changes["language_code"].lower() if changes["language_code"] else None
	channel.updated_at = _now()
	session.flush()
	record_audit(session, actor.id, "youtube.channel_updated", "youtube_trusted_channel", channel.id, {
		"channel_id": channel.channel_id, "fields": sorted(changes.keys()),
	})
	session.commit()
	session.refresh(channel)
	return channel

'''
if marker not in text:
    raise SystemExit('discover marker not found')
text = text.replace(marker, update_fn + marker)

# 3) enhance discover_trusted counters and metrics
old_counts = '''	counts = {
		"channels_checked": len(channels),
		"created": 0,
		"skipped_existing": 0,
		"automatically_published": 0,
		"pending_review": 0,
		"quarantined": 0,
		"unavailable": 0,
		"channels_unavailable": 0,
		"pages_checked": 0,
		"channels_pending_initial_scan": 0,
		"channels_pending_upload_scan": 0,
	}'''
new_counts = '''	counts = {
		"channels_checked": len(channels),
		"created": 0,
		"skipped_existing": 0,
		"automatically_published": 0,
		"pending_review": 0,
		"quarantined": 0,
		"unavailable": 0,
		"channels_unavailable": 0,
		"pages_checked": 0,
		"channels_pending_initial_scan": 0,
		"channels_pending_upload_scan": 0,
		"scanned_videos": 0,
		"shorts_count": 0,
		"long_videos_count": 0,
		"error_count": 0,
	}'''
if old_counts not in text:
    raise SystemExit('discover_trusted counts block not found')
text = text.replace(old_counts, new_counts)

old_video_ids_block = '''				video_ids = page_video_ids
				existing_rows = (
					session.query(Review, Video)
					.join(Video, Video.id == Review.video_id)
					.filter(Review.youtube_video_id.in_(video_ids))
					.with_for_update()
					.all()
				) if video_ids else []
				existing = {review.youtube_video_id: (review, video) for review, video in existing_rows}
				counts["skipped_existing"] += len(existing)
				open_report_video_ids: set[UUID] = set()
				if video_ids and has_model("ContentReport"):
					Report = get_model("ContentReport")
					open_report_video_ids = {
						row[0]
						for row in session.query(Report.video_id).filter(
							Report.video_id.in_([video.id for _, video in existing_rows]),
							Report.status == "open",
						).all()
					}'''
new_video_ids_block = '''				video_ids = page_video_ids
				counts["scanned_videos"] += len(video_ids)
				existing_rows = (
					session.query(Review, Video)
					.join(Video, Video.id == Review.video_id)
					.filter(Review.youtube_video_id.in_(video_ids))
					.with_for_update()
					.all()
				) if video_ids else []
				existing = {review.youtube_video_id: (review, video) for review, video in existing_rows}
				counts["skipped_existing"] += len(existing)
				for _review, _video in existing_rows:
					_fmt = video_format(_video.video_source, _video.duration_seconds)
					if _fmt == "short":
						counts["shorts_count"] += 1
					elif _fmt in {"regular", "unknown"}:
						counts["long_videos_count"] += 1
				open_report_video_ids: set[UUID] = set()
				if video_ids and has_model("ContentReport"):
					Report = get_model("ContentReport")
					open_report_video_ids = {
						row[0]
						for row in session.query(Report.video_id).filter(
							Report.video_id.in_([video.id for _, video in existing_rows]),
							Report.status == "open",
						).all()
					}'''
if old_video_ids_block not in text:
    raise SystemExit('discover_trusted video_ids block not found')
text = text.replace(old_video_ids_block, new_video_ids_block)

old_created_block = '''					created = _create_candidate(session, actor, video_id, item, "trusted_channel_uploads", channel)
					if created is None:
						counts["skipped_existing"] += 1
						continue
					counts["created"] += 1
					review, video = created'''
new_created_block = '''					created = _create_candidate(session, actor, video_id, item, "trusted_channel_uploads", channel)
					if created is None:
						counts["skipped_existing"] += 1
						continue
					counts["created"] += 1
					review, video = created
					_fmt = video_format(video.video_source, video.duration_seconds)
					if _fmt == "short":
						counts["shorts_count"] += 1
					elif _fmt in {"regular", "unknown"}:
						counts["long_videos_count"] += 1'''
if old_created_block not in text:
    raise SystemExit('discover_trusted created block not found')
text = text.replace(old_created_block, new_created_block)

appendix = r'''

def _trusted_channel_or_404(session: Session, channel_id: str):
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	return channel


def _channel_last_discovered(session: Session, channel_id: str):
	Review = get_model("YouTubeContentReview")
	return session.query(func.max(Review.discovered_at)).filter(Review.channel_id == channel_id).scalar()


def _channel_video_counts(session: Session, channel_id: str) -> dict[str, int]:
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	by_status = dict(
		session.query(Review.status, func.count(Review.id))
		.filter(Review.channel_id == channel_id)
		.group_by(Review.status)
		.all()
	)
	discovered = sum(int(v) for v in by_status.values())
	shorts = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, short_clause(Video)
	).count()
	regular = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, regular_clause(Video)
	).count()
	published_short_count = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True), short_clause(Video)
	).count()
	published_regular_count = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True), regular_clause(Video)
	).count()
	published = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True)
	).count()
	return {
		"discovered": discovered,
		"approved": int(by_status.get("approved", 0)),
		"pending_review": int(by_status.get("pending_review", 0)),
		"quarantined": int(by_status.get("quarantined", 0)),
		"rejected": int(by_status.get("rejected", 0)),
		"unavailable": int(by_status.get("unavailable", 0)),
		"revoked": int(by_status.get("revoked", 0)),
		"published": published,
		"published_shorts": published_short_count,
		"published_regular": published_regular_count,
		"total_videos": discovered,
		"shorts_count": shorts,
		"long_videos_count": regular,
	}


def list_channel_videos(
	session: Session,
	channel_id: str,
	*,
	limit: int = 50,
	offset: int = 0,
	status: str | None = None,
	video_format_filter: str | None = None,
	query: str | None = None,
) -> dict[str, Any]:
	_require_tables("YouTubeTrustedChannel", "YouTubeContentReview")
	_trusted_channel_or_404(session, channel_id)
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory") if has_model("VideoCategory") else None
	q = session.query(Review, Video).join(Video, Video.id == Review.video_id).filter(Review.channel_id == channel_id)
	if status:
		if status == "published":
			q = q.filter(Video.is_published.is_(True))
		elif status == "unpublished":
			q = q.filter(Video.is_published.is_(False))
		else:
			q = q.filter(Review.status == status)
	if video_format_filter == "short":
		q = q.filter(short_clause(Video))
	elif video_format_filter in {"long", "regular"}:
		q = q.filter(regular_clause(Video))
	if query:
		like = f"%{query.strip()}%"
		q = q.filter(or_(Video.title.ilike(like), Review.youtube_video_id.ilike(like)))
	total = q.with_entities(func.count(Review.id)).order_by(None).scalar() or 0
	rows = q.order_by(Review.discovered_at.desc(), Review.id.desc()).offset(offset).limit(limit).all()
	items = []
	for review, video in rows:
		category_name = None
		if video.category_id and VideoCategory is not None:
			category = session.get(VideoCategory, video.category_id)
			category_name = category.name if category else None
		items.append({
			"review_id": review.id,
			"video_id": video.id,
			"youtube_video_id": review.youtube_video_id,
			"title": video.title,
			"thumbnail_url": video.thumbnail_url,
			"duration_seconds": known_duration_or_none(video.video_source, video.duration_seconds),
			"video_format": video_format(video.video_source, video.duration_seconds),
			"discovery_topic": getattr(review, "discovery_topic", None),
			"category_id": video.category_id,
			"category_name": category_name,
			"age_min": video.age_min,
			"age_max": video.age_max,
			"review_status": review.status,
			"publication_status": "published" if video.is_published else review.status,
			"is_published": bool(video.is_published),
			"discovered_at": utc_aware(review.discovered_at) if review.discovered_at else None,
			"source_url": review.source_url,
			"channel_id": review.channel_id,
		})
	return {"items": items, "total": int(total), "limit": limit, "offset": offset}


def list_channel_discovery_runs(session: Session, channel_id: str, limit: int = 50) -> list[Any]:
	_trusted_channel_or_404(session, channel_id)
	if not has_model("YouTubeChannelDiscoveryRun"):
		return []
	Run = get_model("YouTubeChannelDiscoveryRun")
	return (
		session.query(Run)
		.filter(Run.channel_id == channel_id)
		.order_by(Run.started_at.desc(), Run.id.desc())
		.limit(limit)
		.all()
	)


def _discovery_run_values(channel_id: str, actor_id, trigger: str = "manual") -> dict[str, Any]:
	return {
		"channel_id": channel_id,
		"triggered_by": actor_id,
		"trigger": trigger,
		"status": "running",
		"started_at": datetime.now(timezone.utc),
		"scanned_videos": 0, "new_videos": 0, "duplicate_videos": 0, "shorts_count": 0, "long_videos_count": 0,
		"auto_approved_count": 0, "pending_review_count": 0, "quarantined_count": 0, "unavailable_count": 0, "error_count": 0,
	}


def _finalize_discovery_run(run, counts: dict[str, Any] | None, *, status: str = "completed", error_message: str | None = None) -> None:
	run.status = status
	run.completed_at = datetime.now(timezone.utc)
	if counts:
		run.scanned_videos = int(counts.get("scanned_videos", counts.get("created", 0) + counts.get("skipped_existing", 0)))
		run.new_videos = int(counts.get("created", 0))
		run.duplicate_videos = int(counts.get("skipped_existing", 0))
		run.shorts_count = int(counts.get("shorts_count", 0))
		run.long_videos_count = int(counts.get("long_videos_count", 0))
		run.auto_approved_count = int(counts.get("automatically_published", 0))
		run.pending_review_count = int(counts.get("pending_review", 0))
		run.quarantined_count = int(counts.get("quarantined", 0))
		run.unavailable_count = int(counts.get("unavailable", 0))
		run.error_count = int(counts.get("error_count", 0))
	run.error_message = error_message[:2000] if error_message else None


def discover_channel_more(session: Session, actor, client: YouTubeClient, channel_id: str, *, trigger: str = "manual") -> dict[str, Any]:
	"""Run channel-specific trusted discovery with overlap prevention and execution history."""
	channel = _trusted_channel_or_404(session, channel_id)
	run = None
	if has_model("YouTubeChannelDiscoveryRun"):
		Run = get_model("YouTubeChannelDiscoveryRun")
		existing_running = session.query(Run.id).filter(Run.channel_id == channel_id, Run.status == "running").first()
		if existing_running:
			raise APIError(409, "youtube_channel_discovery_running", "A discovery run is already in progress for this channel")
		run = Run(**_discovery_run_values(channel_id, actor.id, trigger))
		session.add(run)
		session.commit()  # make running state visible to overlapping requests
		session.refresh(run)
	try:
		counts = discover_trusted(session, actor, client, 50, channel_id=channel_id)
		counts.setdefault("scanned_videos", counts.get("created", 0) + counts.get("skipped_existing", 0))
		counts.setdefault("shorts_count", 0)
		counts.setdefault("long_videos_count", 0)
		counts.setdefault("error_count", 0)
		if run is not None and has_model("YouTubeChannelDiscoveryRun"):
			Run = get_model("YouTubeChannelDiscoveryRun")
			run = session.query(Run).filter(Run.id == run.id).one_or_none() or run
			_finalize_discovery_run(run, counts, status="completed")
			session.add(run)
			session.commit()
			session.refresh(run)
	except YouTubeError as error:
		api_error = to_api_error(error)
		if run is not None and has_model("YouTubeChannelDiscoveryRun"):
			try:
				session.rollback()
				Run = get_model("YouTubeChannelDiscoveryRun")
				run = session.query(Run).filter(Run.id == run.id).one_or_none()
				if run is not None:
					_finalize_discovery_run(run, None, status="failed", error_message=f"{api_error.code}: {api_error.message}")
					run.error_count = 1
					session.add(run)
					session.commit()
					session.refresh(run)
			except Exception:
				session.rollback()
		raise api_error from error
	except Exception as error:
		if run is not None and has_model("YouTubeChannelDiscoveryRun"):
			try:
				session.rollback()
				Run = get_model("YouTubeChannelDiscoveryRun")
				run = session.query(Run).filter(Run.id == run.id).one_or_none()
				if run is not None:
					_finalize_discovery_run(run, None, status="failed", error_message=str(error))
					run.error_count = 1
					session.add(run)
					session.commit()
					session.refresh(run)
			except Exception:
				session.rollback()
		raise
	result = {
		"channel_id": channel_id,
		"channel_title": channel.channel_title if channel else None,
		**counts,
	}
	if run is not None:
		result.update({
			"id": run.id,
			"triggered_by": run.triggered_by,
			"trigger": run.trigger,
			"status": run.status,
			"started_at": utc_aware(run.started_at) if run.started_at else None,
			"completed_at": utc_aware(run.completed_at) if run.completed_at else None,
			"scanned_videos": run.scanned_videos,
			"new_videos": run.new_videos,
			"duplicate_videos": run.duplicate_videos,
			"shorts_count": run.shorts_count,
			"long_videos_count": run.long_videos_count,
			"auto_approved_count": run.auto_approved_count,
			"pending_review_count": run.pending_review_count,
			"quarantined_count": run.quarantined_count,
			"unavailable_count": run.unavailable_count,
			"error_count": run.error_count,
			"error_message": run.error_message,
		})
	return result
'''

# Replace channel_detail/channel_history at end
old_detail = re.search(r"^def channel_detail\(session: Session, channel_id: str\) -> dict\[str, Any\]:.*?^def channel_history\(session: Session, channel_id: str, limit: int = 50\) -> list\[Any\]:.*?\Z", text, flags=re.S|re.M)
if not old_detail:
    raise SystemExit('channel_detail/channel_history block not found')
new_detail = r'''def channel_detail(session: Session, channel_id: str) -> dict[str, Any]:
	"""One trusted channel with the counts of what discovery found, from existing tables only."""
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")

	by_status = dict(
		session.query(Review.status, func.count(Review.id))
		.filter(Review.channel_id == channel_id)
		.group_by(Review.status)
		.all()
	)
	published = session.query(Video.id).join(Review, Review.video_id == Video.id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True)
	)
	shorts = published.filter(short_clause(Video)).count()
	regular = published.filter(regular_clause(Video)).count()
	last_discovered, last_verified = session.query(
		func.max(Review.discovered_at), func.max(Review.last_verified_at)
	).filter(Review.channel_id == channel_id).one()
	discovered = sum(int(v) for v in by_status.values())
	try:
		all_shorts = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
			Review.channel_id == channel_id, short_clause(Video)
		).count()
		all_regular = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
			Review.channel_id == channel_id, regular_clause(Video)
		).count()
	except Exception:
		all_shorts, all_regular = shorts, regular
	counts = {
		"discovered": discovered,
		"approved": int(by_status.get("approved", 0)),
		"pending_review": int(by_status.get("pending_review", 0)),
		"quarantined": int(by_status.get("quarantined", 0)),
		"rejected": int(by_status.get("rejected", 0)),
		"published": shorts + regular,
		"published_shorts": shorts,
		"published_regular": regular,
		# additive fields for richer admin UI
		"total_videos": discovered,
		"unavailable": int(by_status.get("unavailable", 0)),
		"shorts_count": all_shorts,
		"long_videos_count": all_regular,
	}
	return {
		"channel": _channel_to_public_dict(channel, status=channel_status(channel), counts=counts, last_discovery_at=last_discovered),
		"status": channel_status(channel),
		"counts": counts,
		"last_discovered_at": utc_aware(last_discovered) if last_discovered else None,
		"last_verified_at": utc_aware(last_verified) if last_verified else None,
	}


def channel_history(session: Session, channel_id: str, limit: int = 50) -> list[Any]:
	"""Status-change trail for one channel, from the existing audit log."""
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	AuditLog = get_model("AuditLog")
	return (
		session.query(AuditLog)
		.filter(AuditLog.entity_type == "youtube_trusted_channel", AuditLog.entity_id == channel.id)
		.order_by(AuditLog.created_at.desc())
		.limit(limit)
		.all()
	)

'''
text = text[:old_detail.start()] + new_detail + appendix
path.write_text(text, encoding='utf-8')
print('patched')
