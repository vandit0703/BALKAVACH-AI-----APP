import html
import smtplib
import ssl
from email.message import EmailMessage
from urllib.parse import urlencode, urlsplit, urlunsplit

from app.core.config import settings


def _send(message: EmailMessage) -> None:
	if not settings.smtp_host or not settings.password_reset_from_email:
		raise RuntimeError("SMTP email is not configured")
	message["From"] = settings.password_reset_from_email
	if settings.smtp_use_ssl:
		with smtplib.SMTP_SSL(
			settings.smtp_host,
			settings.smtp_port,
			timeout=10,
			context=ssl.create_default_context(),
		) as smtp:
			if settings.smtp_username:
				smtp.login(settings.smtp_username, settings.smtp_password or "")
			smtp.send_message(message)
		return
	with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
		if settings.smtp_use_tls:
			smtp.starttls(context=ssl.create_default_context())
		if settings.smtp_username:
			smtp.login(settings.smtp_username, settings.smtp_password or "")
		smtp.send_message(message)


def email_configured() -> bool:
	"""Whether any email can leave the server (SMTP server and sender are set)."""
	return bool(settings.smtp_host and settings.password_reset_from_email)


def send_parent_verification(email: str, otp: str) -> None:
	message = EmailMessage()
	message["Subject"] = "Verify your BalKavach parent account"
	message["To"] = email
	message.set_content(
		f"Your BalKavach verification code is {otp}. It expires in 5 minutes. "
		"If you did not create an account, you can ignore this email."
	)
	message.add_alternative(
		"""<!doctype html><html><body style="margin:0;background:#f3f7f5;font-family:Arial,sans-serif;color:#173b35">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 12px"><tr><td align="center">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fff;border-radius:12px;overflow:hidden">
		<tr><td style="background:#146b58;padding:24px 32px;color:#fff;font-size:22px;font-weight:bold">BalKavach</td></tr>
		<tr><td style="padding:32px"><h1 style="font-size:22px;margin:0 0 12px">Verify your parent account</h1>
		<p style="font-size:16px;line-height:1.6;margin:0 0 20px">Use this code to finish creating your family account:</p>
		<p style="font-size:32px;letter-spacing:6px;font-weight:bold;color:#146b58;margin:0 0 20px">"""
		+ html.escape(otp)
		+ """</p><p style="font-size:14px;line-height:1.6;color:#52645f">This code expires in 5 minutes. If you did not create a BalKavach account, you can ignore this email.</p>
		<p style="font-size:14px;margin:28px 0 0">Warmly,<br>The BalKavach team</p></td></tr></table></td></tr></table></body></html>""",
		subtype="html",
	)
	_send(message)


def password_reset_configured() -> bool:
	"""Whether a reset email can be sent at all (server, sender and link target are set)."""
	return email_configured() and bool(settings.password_reset_url)


def send_login_code(email: str, otp: str, *, minutes: int) -> None:
	"""Passwordless sign-in code for an existing, verified parent account."""
	message = EmailMessage()
	message["Subject"] = "Your BalKavach sign-in code"
	message["To"] = email
	message.set_content(
		f"Your BalKavach sign-in code is {otp}. It expires in {minutes} minutes and can be used once.\n\n"
		"If you did not try to sign in, you can ignore this email. Your password has not changed."
	)
	message.add_alternative(
		"""<!doctype html><html><body style="margin:0;background:#f3f7f5;font-family:Arial,sans-serif;color:#173b35">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 12px"><tr><td align="center">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fff;border-radius:12px;overflow:hidden">
		<tr><td style="background:#146b58;padding:24px 32px;color:#fff;font-size:22px;font-weight:bold">BalKavach</td></tr>
		<tr><td style="padding:32px"><h1 style="font-size:22px;margin:0 0 12px">Your sign-in code</h1>
		<p style="font-size:16px;line-height:1.6;margin:0 0 20px">Enter this code in the BalKavach app to sign in:</p>
		<p style="font-size:32px;letter-spacing:6px;font-weight:bold;color:#146b58;margin:0 0 20px">"""
		+ html.escape(otp)
		+ f"""</p><p style="font-size:14px;line-height:1.6;color:#52645f">This code expires in {minutes} minutes and can be used once. If you did not try to sign in, you can ignore this email. Your password has not changed.</p>
		<p style="font-size:14px;margin:28px 0 0">Warmly,<br>The BalKavach team</p></td></tr></table></td></tr></table></body></html>""",
		subtype="html",
	)
	_send(message)


def _reset_link(token: str) -> str:
	"""The configured reset page or app link with the token added (keeps any query it already has)."""
	parts = urlsplit(settings.password_reset_url.strip())
	path = parts.path.rstrip("/") or parts.path
	query = "&".join(part for part in (parts.query, urlencode({"token": token})) if part)
	return urlunsplit((parts.scheme, parts.netloc, path, query, ""))


def send_password_reset(email: str, token: str) -> None:
	if not password_reset_configured():
		raise RuntimeError("Password reset email is not configured")
	reset_url = _reset_link(token)
	href = html.escape(reset_url, quote=True)
	minutes = settings.password_reset_expire_minutes
	message = EmailMessage()
	message["Subject"] = "Reset your BalKavach password"
	message["To"] = email
	message.set_content(
		f"Use this link to reset your BalKavach password: {reset_url}\n\n"
		f"This single-use link expires in {minutes} minutes. If you did not request a reset, you can ignore this email."
	)
	message.add_alternative(
		"""<!doctype html><html><body style="margin:0;background:#f3f7f5;font-family:Arial,sans-serif;color:#173b35">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 12px"><tr><td align="center">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fff;border-radius:12px;overflow:hidden">
		<tr><td style="background:#146b58;padding:24px 32px;color:#fff;font-size:22px;font-weight:bold">BalKavach</td></tr>
		<tr><td style="padding:32px"><h1 style="font-size:22px;margin:0 0 12px">Reset your password</h1>
		<p style="font-size:16px;line-height:1.6;margin:0 0 24px">Use the button below to choose a new password for your parent account.</p>
		<a href=\""""
		+ href
		+ """\" style="display:inline-block;background:#146b58;color:#fff;text-decoration:none;padding:13px 22px;border-radius:6px;font-weight:bold">Reset password</a>
		<p style="font-size:14px;line-height:1.6;color:#52645f;margin:24px 0 8px">If the button does not work, copy this link into your browser:</p>
		<p style="font-size:13px;line-height:1.5;word-break:break-all;margin:0">"""
		+ html.escape(reset_url)
		+ f"""</p>
		<p style="font-size:14px;line-height:1.6;color:#52645f;margin:24px 0 0">This single-use link expires in {minutes} minutes. If you did not request a reset, you can ignore this email.</p>
		<p style="font-size:14px;margin:28px 0 0">Warmly,<br>The BalKavach team</p></td></tr></table></td></tr></table></body></html>""",
		subtype="html",
	)
	_send(message)
