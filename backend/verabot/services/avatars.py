"""头像存储（Avatar storage）：校验、居中裁成正方形、压缩为 JPEG 后写入 SQLite。

用户头像 bot_id=0；Bot 头像 bot_id 为该 Bot 的 id。只按 user_id 读写，调用方必须先确认归属。
"""
import io

from PIL import Image, ImageOps, UnidentifiedImageError

from .. import db
from ..db import avatar_store, bot_store, user_store

MAX_AVATAR_BYTES = 8 * 1024 * 1024
AVATAR_SIZE = 512
JPEG_QUALITY = 85
_MAX_PIXELS = 24_000_000
_HEIC_BRANDS = {b"heic", b"heix", b"hevc", b"heif", b"mif1", b"msf1", b"heim", b"heis", b"avci", b"avic"}

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
    HEIC_ENABLED = True
except Exception:  # 未安装 pillow-heif 或系统缺少解码器时，HEIC 会返回明确错误
    HEIC_ENABLED = False

Image.MAX_IMAGE_PIXELS = _MAX_PIXELS


class AvatarError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def sniff_format(data: bytes) -> str:
    """按文件头识别格式，不信任客户端声明的 Content-Type。"""
    if len(data) >= 3 and data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if len(data) >= 8 and data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if len(data) >= 12 and data[4:8] == b"ftyp" and data[8:12] in _HEIC_BRANDS:
        return "heic"
    return ""


def render_avatar(data: bytes) -> bytes:
    """校验并处理成 AVATAR_SIZE 的 JPEG。失败抛 AvatarError。"""
    if not data:
        raise AvatarError(400, "没有收到图片")
    if len(data) > MAX_AVATAR_BYTES:
        if MAX_AVATAR_BYTES >= 1024 * 1024:
            limit = f"{MAX_AVATAR_BYTES // (1024 * 1024)}MB"
        else:
            limit = f"{max(1, MAX_AVATAR_BYTES // 1024)}KB"
        raise AvatarError(413, f"图片不能超过 {limit}")
    kind = sniff_format(data)
    if not kind:
        raise AvatarError(415, "仅支持 JPEG、PNG、WebP 或 HEIC")
    if kind == "heic" and not HEIC_ENABLED:
        raise AvatarError(415, "服务器暂不能解码 HEIC，请改用 JPEG、PNG 或 WebP")
    try:
        with Image.open(io.BytesIO(data)) as im:
            im.load()
            im = ImageOps.exif_transpose(im) or im
            if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
                rgba = im.convert("RGBA")
                bg = Image.new("RGB", rgba.size, (255, 255, 255))
                bg.paste(rgba, mask=rgba.split()[-1])
                im = bg
            elif im.mode != "RGB":
                im = im.convert("RGB")
            w, h = im.size
            if w < 1 or h < 1:
                raise AvatarError(400, "无法解析图片")
            side = min(w, h)
            left = (w - side) // 2
            top = (h - side) // 2
            im = im.crop((left, top, left + side, top + side))
            im = im.resize((AVATAR_SIZE, AVATAR_SIZE), Image.Resampling.LANCZOS)
            out = io.BytesIO()
            im.save(out, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    except AvatarError:
        raise
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError):
        raise AvatarError(400, "无法解析图片")
    jpeg = out.getvalue()
    if not jpeg or sniff_format(jpeg) != "jpeg":
        raise AvatarError(400, "无法解析图片")
    return jpeg


def save_user_avatar(user_id: int, raw: bytes) -> str:
    jpeg = render_avatar(raw)
    now = db.now_iso()
    with db.tx() as c:
        avatar_store.upsert(c, user_id, 0, jpeg, now)
        user_store.set_avatar_updated(c, user_id, now)
    return now


def delete_user_avatar(user_id: int):
    with db.tx() as c:
        avatar_store.delete_user(c, user_id)
        user_store.clear_avatar_updated(c, user_id)


def read_user_avatar(user_id: int) -> bytes | None:
    with db.tx() as c:
        row = avatar_store.read_user(c, user_id)
    return bytes(row["data"]) if row else None


def save_bot_avatar(user_id: int, bot_id: int, raw: bytes) -> str:
    jpeg = render_avatar(raw)
    now = db.now_iso()
    with db.tx() as c:
        avatar_store.upsert(c, user_id, bot_id, jpeg, now)
        bot_store.set_image_updated(c, user_id, bot_id, now)
    return now


def delete_bot_avatar(user_id: int, bot_id: int):
    with db.tx() as c:
        avatar_store.delete_bot(c, user_id, bot_id)
        bot_store.clear_image_updated(c, user_id, bot_id)


def read_bot_avatar(user_id: int, bot_id: int) -> bytes | None:
    with db.tx() as c:
        row = avatar_store.read_bot(c, user_id, bot_id)
    return bytes(row["data"]) if row else None
