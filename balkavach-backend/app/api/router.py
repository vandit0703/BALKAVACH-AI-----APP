from fastapi import APIRouter

from app.api.v1.auth import router as auth_router
from app.api.v1.admin import router as admin_router
from app.api.v1.families import router as families_router
from app.api.v1.educational_content import router as educational_content_router
from app.api.v1.progress import router as progress_router
from app.api.v1.rewards import router as rewards_router
from app.api.v1.notifications import router as notifications_router
from app.api.v1.settings import router as settings_router
from app.api.v1.reviews import router as reviews_router
from app.api.v1.tasks import router as tasks_router
from app.api.v1.videos import admin_router as admin_videos_router
from app.api.v1.videos import router as videos_router
from app.api.v1.video_access import router as video_access_router

api_router = APIRouter()
api_router.include_router(auth_router)
api_router.include_router(admin_router)
api_router.include_router(families_router)
api_router.include_router(educational_content_router)
api_router.include_router(tasks_router)
api_router.include_router(reviews_router)
api_router.include_router(progress_router)
api_router.include_router(rewards_router)
api_router.include_router(videos_router)
api_router.include_router(admin_videos_router)
api_router.include_router(video_access_router)
api_router.include_router(notifications_router)
api_router.include_router(settings_router)
