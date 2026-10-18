"""VeraBot API 服务入口（FastAPI）：`uvicorn verabot.main:app`。

只负责组装：中间件、异常处理、启动时初始化数据库、注册路由、提醒调度、（可选）托管 Web 客户端。
"""
import asyncio
import logging

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import __version__, db
from .api.routers import actions, attachments, auth, avatars, bots, chat, devices, feedback, mcp, memories, meta, notifications, plugins, reminders, suggestions, voice
from .api.routers import groups, scheduled_tasks, group_execution
from .services.reminders import scheduler as reminder_scheduler
from .core.config import WEB_DIR
from .core import log_redact
from .core.http_cache import NoStoreAPIMiddleware

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log_redact.install()   # 令牌样式字符串在所有日志里脱敏（MCP 连接器 P1）
app = FastAPI(title="VeraBot API", version=__version__)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
# 最外层：所有 /api/* 响应（含 CORS 预检、错误、SSE）都带 Cache-Control: no-store，见 core/http_cache.py
app.add_middleware(NoStoreAPIMiddleware)


@app.exception_handler(RequestValidationError)
async def _validation_error(request, exc: RequestValidationError):
    """422 统一格式：去掉 pydantic 的 "Value error, " 前缀，客户端可直接展示中文提示。"""
    errs = []
    for e in exc.errors():
        msg = str(e.get("msg", ""))
        if msg.startswith("Value error, "):
            msg = msg[len("Value error, "):]
        errs.append({"loc": list(e.get("loc", [])), "msg": msg, "type": e.get("type")})
    return JSONResponse(status_code=422, content={"detail": errs})


@app.on_event("startup")
async def _startup():
    db.init_db()
    from .db import chat_reply_store
    with db.tx(immediate=True) as c:
        chat_reply_store.recover_legacy(c)
    from .db.group_store import recover_interrupted_turns
    recover_interrupted_turns()  # Single-worker only; never resume model calls.
    from .db import group_execution_store
    from .services import group_worker
    from datetime import datetime, timezone
    group_execution_store.recover_interrupted(datetime.now(timezone.utc).isoformat(timespec="seconds"))
    app.state.group_execution_worker = asyncio.create_task(group_worker.loop("api-single-worker"))
    app.state.reminder_scheduler = asyncio.create_task(reminder_scheduler.loop())


@app.on_event("startup")
async def _memory_jobs():
    """滚动摘要：进程内单 worker。启动时把中断的 running 退回 pending。VERABOT_MEMORY_JOBS=0 时不启动。"""
    from .services.memory.jobs import enabled, loop
    if not enabled():
        return
    app.state.memory_jobs = asyncio.create_task(loop())


@app.on_event("shutdown")
async def _shutdown():
    running = []
    for name in ("group_execution_worker", "reminder_scheduler", "attachments_reconcile", "memory_jobs"):
        task = getattr(app.state, name, None)
        if task is not None:
            task.cancel()
            running.append(task)
    if running:
        await asyncio.gather(*running, return_exceptions=True)


@app.on_event("startup")
async def _attachments_reconcile():
    """图片附件：清空 tmp/，启动对账一次，之后每天一次（见 services/attachments/repo.py）。"""
    from .services.attachments.repo import reconcile_loop
    app.state.attachments_reconcile = asyncio.create_task(reconcile_loop())


from .api.routers import items

for r in (attachments.router, auth.router, avatars.router, bots.router, chat.router, memories.router, feedback.router,
          voice.router, reminders.router, items.router, notifications.router, devices.router, meta.router, mcp.router, plugins.router,
          actions.router, suggestions.router, groups.router, group_execution.router, scheduled_tasks.router):
    app.include_router(r)


# ---------------- Web client（可选：frontend/web 存在时托管）----------------
if (WEB_DIR / "index.html").is_file():
    @app.get("/")
    def index():
        return FileResponse(WEB_DIR / "index.html")

    app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")
else:
    @app.get("/")
    def index():
        return {"name": "VeraBot API", "version": __version__, "docs": "/docs", "health": "/api/health"}

from .api.routers import primary_bot
app.include_router(primary_bot.router)

from .api.routers import owned_tasks
app.include_router(owned_tasks.router)

from .api.routers import chat_tasks, conversation_activity
app.include_router(chat_tasks.router)
app.include_router(conversation_activity.router)

# Durable user library; independent of message/attachment retention.
from .api.routers import library as library_router
app.include_router(library_router.router)

from .api.routers import feed
app.include_router(feed.router)
