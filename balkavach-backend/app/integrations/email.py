import smtplib
from email.message import EmailMessage

from app.core.config import settings


def send_password_reset(email: str, token: str) -> None:
	if not settings.smtp_host or not settings.password_reset_from_email or not settings.password_reset_url:
		raise RuntimeError("Password reset email is not configured")
	message = EmailMessage()
	message["Subject"] = "Reset your BalKavach password"
	message["From"] = settings.password_reset_from_email
	message["To"] = email
	message.set_content(
		f"Reset your BalKavach password using this link:\n"
		f"{settings.password_reset_url.rstrip('/')}/?token={token}\n\n"
		"This link expires soon. If you did not request it, you can ignore this email."
	)
	with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
		if settings.smtp_use_tls:
			smtp.starttls()
		if settings.smtp_username:
			smtp.login(settings.smtp_username, settings.smtp_password or "")
		smtp.send_message(message)