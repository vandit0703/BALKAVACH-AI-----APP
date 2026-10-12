import logging.config
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from starlette.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import settings
from app.core.exceptions import register_exception_handlers
from app.db.session import get_db

logging.config.dictConfig(
	{
		"version": 1,
		"disable_existing_loggers": False,
		"formatters": {"default": {"format": "%(asctime)s %(levelname)s %(name)s %(message)s"}},
		"handlers": {"console": {"class": "logging.StreamHandler", "formatter": "default"}},
		"root": {"level": settings.log_level.upper(), "handlers": ["console"]},
	}
)


@asynccontextmanager
async def lifespan(app: FastAPI):
	yield


app = FastAPI(title=settings.app_name, debug=settings.debug, lifespan=lifespan)
app.add_middleware(
	CORSMiddleware,
	allow_origins=settings.cors_origins,
	allow_credentials=bool(settings.cors_origins),
	allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
	allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)
register_exception_handlers(app)
app.include_router(api_router, prefix="/api/v1")


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
	return {"status": "ok"}


@app.get("/ready", tags=["health"])
def readiness(session: Session = Depends(get_db)) -> dict[str, str]:
	try:
		session.execute(text("SELECT 1"))
	except SQLAlchemyError as error:
		raise HTTPException(status_code=503, detail="Database is unavailable") from error
	return {"status": "ready"}
