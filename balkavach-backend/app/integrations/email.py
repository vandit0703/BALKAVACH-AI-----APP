import html
import smtplib
import ssl
from email.message import EmailMessage
from urllib.parse import urlencode

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


def send_password_reset(email: str, token: str) -> None:
	if not settings.password_reset_url:
		raise RuntimeError("Password reset email is not configured")
	reset_url = f"{settings.password_reset_url.rstrip('/')}?{urlencode({'token': token})}"
	message = EmailMessage()
	message["Subject"] = "Reset your BalKavach password"
	message["To"] = email
	message.set_content(
		f"Use this link to reset your BalKavach password: {reset_url}\n\n"
		"This single-use link expires in 30 minutes. If you did not request a reset, you can ignore this email."
	)
	message.add_alternative(
		"""<!doctype html><html><body style="margin:0;background:#f3f7f5;font-family:Arial,sans-serif;color:#173b35">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="padding:32px 12px"><tr><td align="center">
		<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fff;border-radius:12px;overflow:hidden">
		<tr><td style="background:#146b58;padding:24px 32px;color:#fff;font-size:22px;font-weight:bold">BalKavach</td></tr>
		<tr><td style="padding:32px"><h1 style="font-size:22px;margin:0 0 12px">Reset your password</h1>
		<p style="font-size:16px;line-height:1.6;margin:0 0 24px">Use the button below to choose a new password for your parent account.</p>
		<a href=""" + html.escape(reset_url, quote=True) + """" style="display:inline-block;background:#146b58;color:#fff;text-decoration:none;padding:13px 22px;border-radius:6px;font-weight:bold">Reset password</a>
		<p style="font-size:14px;line-height:1.6;color:#52645f;margin:24px 0 0">This single-use link expires in 30 minutes. If you did not request a reset, you can ignore this email.</p>
		<p style="font-size:14px;margin:28px 0 0">Warmly,<br>The BalKavach team</p></td></tr></table></td></tr></table></body></html>""",
		subtype="html",
	)
	_send(message)
import smtplib
from email.message import EmailMessage

from app.core.config import settings


def send_password_reset(email: str, token: str) -> None:
	if not settings.smtp_host or not settings.password_reset_from_email or not settings.password_reset_url:
		raise RuntimeError("Password reset email is not configured")
	message = EmailMessage()
	message["Subject"] = "Reset your BALKAVACH password"
	message["From"] = settings.password_reset_from_email
	message["To"] = email
	message.set_content(
		f"Reset your BALKAVACH password using this link:\n"
		f"{settings.password_reset_url.rstrip('/')}/?token={token}\n\n"
		"This link expires soon. If you did not request it, you can ignore this email."
	)
	with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
		if settings.smtp_use_tls:
			smtp.starttls()
		if settings.smtp_username:
			smtp.login(settings.smtp_username, settings.smtp_password or "")
		smtp.send_message(message)