from collections.abc import Generator

from fastapi import HTTPException
from sqlalchemy import Engine, create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_database_url

database_url = get_database_url()
engine: Engine | None = create_engine(database_url, pool_pre_ping=True, pool_recycle=300) if database_url else None
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False) if engine else None

if engine is not None and engine.dialect.name == "postgresql":
	@event.listens_for(engine, "connect")
	def _set_connection_timezone(dbapi_connection, connection_record) -> None:
		cursor = dbapi_connection.cursor()
		cursor.execute("SET TIME ZONE 'UTC'")
		cursor.close()


def get_db() -> Generator[Session, None, None]:
	if SessionLocal is None:
		raise HTTPException(status_code=503, detail="Database is not configured")
	with SessionLocal() as session:
		yield session
