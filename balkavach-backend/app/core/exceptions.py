import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)


class APIError(Exception):
	def __init__(
		self,
		status_code: int,
		code: str,
		message: str,
		*,
		headers: dict[str, str] | None = None,
		details: dict[str, Any] | None = None,
	) -> None:
		self.status_code = status_code
		self.code = code
		self.message = message
		self.headers = headers
		self.details = details


def database_error_details(error: BaseException) -> str:
	"""Which rule the database rejected, for the server log: SQLSTATE plus constraint, table and column names.

	Names only: never the statement parameters or row values (they can hold personal data). Works for psycopg 3
	(``sqlstate``) and psycopg 2 (``pgcode``).
	"""
	original = getattr(error, "orig", None)
	if original is None:
		return ""
	diag = getattr(original, "diag", None)
	parts = {
		"sqlstate": getattr(original, "sqlstate", None) or getattr(original, "pgcode", None),
		"constraint": getattr(diag, "constraint_name", None),
		"table": getattr(diag, "table_name", None),
		"column": getattr(diag, "column_name", None),
	}
	return " " + " ".join(f"{key}={value}" for key, value in parts.items() if value)


def register_exception_handlers(app: FastAPI) -> None:
	@app.exception_handler(APIError)
	async def handle_api_error(request: Request, exc: APIError) -> JSONResponse:
		error: dict[str, Any] = {"code": exc.code, "message": exc.message}
		if exc.details:
			error["details"] = exc.details
		return JSONResponse(status_code=exc.status_code, content={"error": error}, headers=exc.headers)

	@app.exception_handler(StarletteHTTPException)
	async def handle_http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
		message = exc.detail if isinstance(exc.detail, str) else "Request failed"
		return JSONResponse(
			status_code=exc.status_code,
			content={"error": {"code": "http_error", "message": message}},
			headers=exc.headers,
		)

	@app.exception_handler(RequestValidationError)
	async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
		errors: list[dict[str, Any]] = [
			{"location": list(error["loc"]), "message": error["msg"], "type": error["type"]}
			for error in exc.errors()
		]
		return JSONResponse(
			status_code=422,
			content={"error": {"code": "validation_error", "message": "Request validation failed", "details": errors}},
		)

	@app.exception_handler(Exception)
	async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
		if isinstance(exc, SQLAlchemyError):
			logger.error(
				"Unhandled database request error (%s%s) on %s %s",
				type(exc).__name__,
				database_error_details(exc),
				request.method,
				request.url.path,
			)
		else:
			logger.exception("Unhandled request error", exc_info=exc)
		return JSONResponse(
			status_code=500,
			content={"error": {"code": "internal_error", "message": "An internal error occurred"}},
		)
