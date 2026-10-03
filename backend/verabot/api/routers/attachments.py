"""图片附件（Attachments P1，schema v12）：上传 / 元数据 / 原图 / 缩略图 / 删除未发送的图。

- 上传：multipart，字段 file，可选 bot_id。按文件头识别类型，去 EXIF 重编码（GIF 原样保留动画）。
- 下载：鉴权代理（Bearer），不用签名 URL；`Cache-Control: private, no-store`、`X-Content-Type-Options: nosniff`。
- 他人的、不存在的 id 一律 404；库里有但文件没了 410。
- 已发送的图片随消息删除（清空对话 / 删除 Bot），这里只能删未发送（pending）的。
"""
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse

from ...core.config import ATTACHMENT_MAX_BYTES
from ...services.attachments import repo
from ..deps import current_user

router = APIRouter(tags=["attachments"])
FILE_HEADERS = {"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"}


def _raise(e: repo.AttachmentError):
    detail = {"message": e.message, "code": e.code} if e.code else e.message
    raise HTTPException(e.status, detail)


def _owned(user, att_id: str) -> dict:
    r = repo.get(user["id"], att_id)
    if not r:
        raise HTTPException(404, "图片不存在")
    return r


@router.post("/api/attachments", status_code=201)
def upload_attachment(file: UploadFile = File(...), bot_id: int | None = Form(None), user=Depends(current_user)):
    data = file.file.read(ATTACHMENT_MAX_BYTES + 1)
    file.file.close()
    try:
        return repo.create(user["id"], bot_id, data)
    except repo.AttachmentError as e:
        _raise(e)


@router.get("/api/attachments/{att_id}")
def attachment_meta(att_id: str, user=Depends(current_user)):
    return repo.public(_owned(user, att_id))


def _file(user, att_id: str, variant: str):
    r = _owned(user, att_id)
    path = repo.file_path(r, variant)
    if path is None:
        raise HTTPException(410, repo.GONE_MESSAGE)
    mime = r["mime"] if variant == "content" else "image/jpeg"
    return FileResponse(path, media_type=mime, headers=FILE_HEADERS)


@router.get("/api/attachments/{att_id}/content")
def attachment_content(att_id: str, user=Depends(current_user)):
    return _file(user, att_id, "content")


@router.get("/api/attachments/{att_id}/thumb")
def attachment_thumb(att_id: str, user=Depends(current_user)):
    return _file(user, att_id, "thumb")


@router.delete("/api/attachments/{att_id}")
def attachment_delete(att_id: str, user=Depends(current_user)):
    try:
        repo.delete_pending(user["id"], att_id)
    except repo.AttachmentError as e:
        _raise(e)
    return {"ok": True}
