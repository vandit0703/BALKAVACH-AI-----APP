import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger(__name__)


class APIError(Exception):
	def __init__(self, status_code: int, code: str, message: str) -> None:
		self.status_code = status_code
		self.code = code
		self.message = message


def register_exception_handlers(app: FastAPI) -> None:
	@app.exception_handler(APIError)
	async def handle_api_error(request: Request, exc: APIError) -> JSONResponse:
		return JSONResponse(status_code=exc.status_code, content={"error": {"code": exc.code, "message": exc.message}})

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
			logger.error("Unhandled database request error (%s)", type(exc).__name__)
		else:
			logger.exception("Unhandled request error", exc_info=exc)
		return JSONResponse(
			status_code=500,
			content={"error": {"code": "internal_error", "message": "An internal error occurred"}},
		)
