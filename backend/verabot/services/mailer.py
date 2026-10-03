"""发信（Mail sender）：可插拔后端。

- console（默认）：不发邮件，把验证码写到后端日志（logger `verabot.mail`），开发 / 测试用。
- smtp：设置 `VERABOT_MAIL_BACKEND=smtp` 且配置 `VERABOT_SMTP_*` 后启用（Gmail 需要应用专用密码）。

环境变量在每次发信时读取，改完重启后端即可，不需要改代码。
"""
from __future__ import annotations

import logging
import os
import smtplib
import ssl
from email.message import EmailMessage

log = logging.getLogger("verabot.mail")

# 测试可以读取最近发出的邮件（console 后端也会记录）。只保留最近 50 封，不落盘。
OUTBOX: list[dict] = []


class MailError(Exception):
    pass


def backend_name() -> str:
    return (os.getenv("VERABOT_MAIL_BACKEND") or "console").strip().lower()


def send(to: str, subject: str, body: str, *, code: str | None = None) -> None:
    """发一封纯文本邮件。失败抛 MailError（调用方返回固定中文提示，不回显 SMTP 原文）。"""
    OUTBOX.append({"to": to, "subject": subject, "body": body, "code": code})
    del OUTBOX[:-50]
    name = backend_name()
    if name == "smtp":
        _send_smtp(to, subject, body)
        log.info("mail sent via smtp to=%s subject=%s", _mask(to), subject)
        return
    # console：开发模式，验证码直接写日志
    log.warning("[DEV MAIL] to=%s subject=%s code=%s", to, subject, code or "-")


def _send_smtp(to: str, subject: str, body: str) -> None:
    host = os.getenv("VERABOT_SMTP_HOST", "smtp.gmail.com")
    port = int(os.getenv("VERABOT_SMTP_PORT", "587"))
    user = os.getenv("VERABOT_SMTP_USER", "")
    password = os.getenv("VERABOT_SMTP_PASSWORD", "")
    sender = os.getenv("VERABOT_SMTP_FROM") or user
    use_ssl = os.getenv("VERABOT_SMTP_SSL", "0") == "1"           # 465 端口
    starttls = os.getenv("VERABOT_SMTP_STARTTLS", "1") != "0"     # 587 端口（默认）
    timeout = float(os.getenv("VERABOT_SMTP_TIMEOUT", "15"))
    if not (user and password and sender):
        raise MailError("SMTP 未配置完整（需要 VERABOT_SMTP_USER / VERABOT_SMTP_PASSWORD）")
    msg = EmailMessage()
    msg["From"] = f"VeraBot <{sender}>"
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    ctx = ssl.create_default_context()
    try:
        if use_ssl:
            with smtplib.SMTP_SSL(host, port, timeout=timeout, context=ctx) as s:
                s.login(user, password)
                s.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=timeout) as s:
                if starttls:
                    s.starttls(context=ctx)
                s.login(user, password)
                s.send_message(msg)
    except (smtplib.SMTPException, OSError) as exc:
        log.error("smtp send failed: %s", type(exc).__name__)
        raise MailError("邮件发送失败") from exc


def _mask(email: str) -> str:
    local, _, domain = email.partition("@")
    return (local[:2] + "***@" + domain) if domain else "***"
