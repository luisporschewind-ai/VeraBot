"""语音转写（Speech-to-Text）：OpenAI gpt-4o-mini-transcribe → whisper-1 →（可选）本地 faster-whisper。"""
import asyncio
import json
import logging
import os
import shutil
import tempfile

import httpx

import re
import threading

from ..core.config import DATA_DIR, LOCAL_STT, LOCAL_STT_MODEL, OPENAI_API_KEY, OPENAI_BASE_URL, TRANSCRIBE_MODELS

log = logging.getLogger("verabot.transcribe")

ALLOWED_EXT = {"webm", "ogg", "oga", "m4a", "mp4", "wav", "mp3", "mpeg", "mpga"}
MIME_EXT = {"audio/webm": "webm", "audio/ogg": "ogg", "audio/mp4": "m4a", "audio/x-m4a": "m4a", "audio/m4a": "m4a",
            "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/mpeg": "mp3", "video/webm": "webm"}


class TranscribeError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def detect_ext(filename: str | None, content_type: str | None) -> str | None:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct in MIME_EXT:
        return MIME_EXT[ct]
    ext = (filename or "").rsplit(".", 1)[-1].lower() if "." in (filename or "") else ""
    return ext if ext in ALLOWED_EXT else None


async def probe_duration(data: bytes, ext: str) -> float | None:
    """用 ffprobe 读取时长；未安装 ffprobe 时返回 None（仅依赖大小限制）。"""
    if not shutil.which("ffprobe"):
        return None
    with tempfile.NamedTemporaryFile(suffix="." + ext, delete=False) as f:
        f.write(data)
        path = f.name
    try:
        proc = await asyncio.create_subprocess_exec(
            "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", path,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
        dur = json.loads(out or b"{}").get("format", {}).get("duration")
        return float(dur) if dur not in (None, "N/A") else None
    except Exception:
        return None
    finally:
        os.unlink(path)


def _openai_error(r: httpx.Response) -> str:
    try:
        err = r.json().get("error") or {}
    except ValueError:
        err = {}
    code = err.get("code") or err.get("type") or ""
    if code in ("insufficient_quota", "credit_balance_exhausted"):
        return "OpenAI 账户额度不足"
    if r.status_code == 401:
        return "OpenAI Key 无效"
    if r.status_code == 429:
        return "OpenAI 限流"
    return f"OpenAI HTTP {r.status_code}"


async def _openai(data: bytes, ext: str, language: str) -> dict:
    last_err = "未配置 OPENAI_API_KEY"
    if not OPENAI_API_KEY:
        raise TranscribeError(503, last_err)
    async with httpx.AsyncClient(timeout=httpx.Timeout(90, connect=15)) as client:
        for model in TRANSCRIBE_MODELS:
            form = {"model": model, "language": language, "response_format": "json",
                    "prompt": "以下是普通话语音，请输出简体中文，保留标点。"}
            try:
                r = await client.post(f"{OPENAI_BASE_URL}/audio/transcriptions",
                                      headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                                      data=form, files={"file": (f"audio.{ext}", data, f"audio/{ext}")})
            except httpx.HTTPError as e:
                last_err = f"网络错误 {type(e).__name__}"
                log.warning("transcribe model=%s %s", model, last_err)
                continue
            if r.status_code == 200:
                body = r.json()
                return {"text": (body.get("text") or "").strip(), "model": model, "usage": body.get("usage") or {}}
            # 仅记录状态码与归类后的原因，绝不记录请求头 / Key
            last_err = _openai_error(r)
            log.warning("transcribe model=%s failed: %s", model, last_err)
            if last_err == "OpenAI 账户额度不足" or r.status_code == 401:
                break  # 同一账号换模型也无效
    raise TranscribeError(502, last_err)


_local_model = None
_local_lock = threading.Lock()


def _local_available() -> bool:
    if not LOCAL_STT:
        return False
    try:
        import faster_whisper  # noqa: F401
        return True
    except ImportError:
        return False


def _local_sync(data: bytes, ext: str, language: str) -> dict:
    global _local_model
    from faster_whisper import WhisperModel
    with _local_lock:
        if _local_model is None:
            _local_model = WhisperModel(LOCAL_STT_MODEL, device="cpu", compute_type="int8",
                                        download_root=str(DATA_DIR / "models"))
        with tempfile.NamedTemporaryFile(suffix="." + ext, delete=False) as f:
            f.write(data)
            path = f.name
        try:
            segs, _info = _local_model.transcribe(path, language=language, vad_filter=True,
                                                  initial_prompt="以下是普通话语音，请输出简体中文，保留标点。")
            text = "".join(s.text for s in segs).strip()
        finally:
            os.unlink(path)
    return {"text": text, "model": f"local:faster-whisper-{LOCAL_STT_MODEL}", "usage": {}}


def _normalize_zh(text: str) -> str:
    """中文语境下将半角标点转为全角。"""
    table = {",": "，", "?": "？", "!": "！", ":": "：", ";": "；"}
    return re.sub(r"(?<=[\u4e00-\u9fff])([,?!:;])", lambda m: table[m.group(1)], text)


async def transcribe(data: bytes, ext: str, language: str = "zh") -> dict:
    try:
        res = await _openai(data, ext, language)
    except TranscribeError as e:
        if not _local_available():
            raise TranscribeError(e.status, f"语音转写失败：{e}")
        log.info("OpenAI transcription unavailable (%s); using local fallback", e)
        res = await asyncio.to_thread(_local_sync, data, ext, language)
        res["fallback_reason"] = str(e)
    if language.startswith("zh"):
        res["text"] = _normalize_zh(res["text"])
    return res
