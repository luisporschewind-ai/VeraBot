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
from .api.routers import auth, avatars, bots, chat, devices, mcp, memories, meta, notifications, plugins, reminders, voice
from .services.reminders import scheduler as reminder_scheduler
from .core.config import WEB_DIR
from .core.http_cache import NoStoreAPIMiddleware

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
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
    app.state.reminder_scheduler = asyncio.create_task(reminder_scheduler.loop())


@app.on_event("shutdown")
async def _shutdown():
    task = getattr(app.state, "reminder_scheduler", None)
    if task is not None:
        task.cancel()


for r in (auth.router, avatars.router, bots.router, chat.router, memories.router, voice.router, reminders.router,
          notifications.router, devices.router, meta.router, mcp.router, plugins.router):
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
