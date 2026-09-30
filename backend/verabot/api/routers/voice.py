"""语音转写（Speech-to-Text）。"""
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile

from ... import db
from ...core.config import TRANSCRIBE_MAX_BYTES, TRANSCRIBE_MAX_SECONDS
from ...services.transcribe import TranscribeError, detect_ext, probe_duration, transcribe
from ..deps import current_user

router = APIRouter(tags=["voice"])


@router.post("/api/transcribe")
async def api_transcribe(file: UploadFile = File(...), language: str = Form("zh"), user=Depends(current_user)):
    """语音转写：multipart/form-data，字段 file（webm/ogg/m4a/wav/mp3）。返回 {text}，由客户端填入输入框。"""
    ext = detect_ext(file.filename, file.content_type)
    if not ext:
        raise HTTPException(415, "不支持的音频格式，请上传 webm / ogg / m4a / wav / mp3")
    data = await file.read(TRANSCRIBE_MAX_BYTES + 1)
    if len(data) > TRANSCRIBE_MAX_BYTES:
        raise HTTPException(413, f"音频过大（上限 {TRANSCRIBE_MAX_BYTES // (1024 * 1024)} MB）")
    if len(data) < 256:
        raise HTTPException(400, "音频为空或过短")
    duration = await probe_duration(data, ext)
    if duration is not None and duration > TRANSCRIBE_MAX_SECONDS + 1:
        raise HTTPException(413, f"音频过长（上限 {int(TRANSCRIBE_MAX_SECONDS)} 秒，当前 {duration:.0f} 秒）")
    try:
        res = await transcribe(data, ext, (language or "zh")[:5])
    except TranscribeError as e:
        raise HTTPException(e.status, str(e))
    with db.tx() as c:
        c.execute("INSERT INTO transcriptions(user_id,model,bytes,duration_s,chars,total_tokens,created_at)"
                  " VALUES (?,?,?,?,?,?,?)",
                  (user["id"], res["model"], len(data), duration, len(res["text"]),
                   int((res["usage"] or {}).get("total_tokens") or 0), db.now_iso()))
    return {"text": res["text"], "model": res["model"], "duration_s": duration,
            "fallback_reason": res.get("fallback_reason")}
