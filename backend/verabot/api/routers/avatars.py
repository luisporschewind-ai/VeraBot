"""头像（Avatars）：用户与 Bot 的上传 / 获取 / 恢复默认。

上传为 multipart/form-data，字段名 file。服务端裁成正方形并压缩为 JPEG。
GET 在未设置自定义头像时返回 404，客户端据此显示默认头像（首字母或表情）。
他人的 Bot 与不存在的 Bot 都是 404。
"""
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import Response

from ... import db
from ...services import avatars
from ...services.bots import public_bot
from ...services.users import load_public
from ..deps import current_user, require_bot

router = APIRouter(tags=["avatars"])


async def _read_upload(file: UploadFile) -> bytes:
    data = await file.read(avatars.MAX_AVATAR_BYTES + 1)
    await file.close()
    return data


def _avatar_response(data: bytes) -> Response:
    return Response(
        content=data,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=86400"},
    )


def _raise(err: avatars.AvatarError):
    raise HTTPException(err.status, err.message)


@router.post("/api/me/avatar")
async def upload_my_avatar(file: UploadFile = File(...), user=Depends(current_user)):
    try:
        avatars.save_user_avatar(user["id"], await _read_upload(file))
    except avatars.AvatarError as e:
        _raise(e)
    return load_public(user["id"])


@router.get("/api/me/avatar")
def get_my_avatar(user=Depends(current_user)):
    data = avatars.read_user_avatar(user["id"])
    if not data:
        raise HTTPException(404, "未设置头像")
    return _avatar_response(data)


@router.delete("/api/me/avatar")
def delete_my_avatar(user=Depends(current_user)):
    avatars.delete_user_avatar(user["id"])
    return load_public(user["id"])


@router.post("/api/bots/{bot_id}/avatar")
async def upload_bot_avatar(bot_id: int, file: UploadFile = File(...), user=Depends(current_user)):
    require_bot(user, bot_id)
    try:
        avatars.save_bot_avatar(user["id"], bot_id, await _read_upload(file))
    except avatars.AvatarError as e:
        _raise(e)
    return public_bot(db.get_bot(user["id"], bot_id))


@router.get("/api/bots/{bot_id}/avatar")
def get_bot_avatar(bot_id: int, user=Depends(current_user)):
    require_bot(user, bot_id)
    data = avatars.read_bot_avatar(user["id"], bot_id)
    if not data:
        raise HTTPException(404, "未设置头像")
    return _avatar_response(data)


@router.delete("/api/bots/{bot_id}/avatar")
def delete_bot_avatar(bot_id: int, user=Depends(current_user)):
    require_bot(user, bot_id)
    avatars.delete_bot_avatar(user["id"], bot_id)
    return public_bot(db.get_bot(user["id"], bot_id))
