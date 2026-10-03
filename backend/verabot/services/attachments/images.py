"""图片校验与处理（Pillow）：按文件头识别类型 → 尺寸 / 像素检查 → 去 EXIF 重编码 → 缩略图。

- JPEG / WebP / HEIC / 不透明 PNG：exif_transpose 后长边缩到 2048，重编码 JPEG q85（不写 EXIF，保留 ICC）。
- 带透明的 PNG：同样缩放，保持 PNG（不写文本块）。
- GIF：原样保存全部帧，只去掉注释和非循环用的应用扩展块（XMP 等）；另生成第一帧静态 JPEG（发给模型）。
- 缩略图：320px JPEG q75。
失败抛 ImageError(status, message)，路由原样转成 HTTP 错误。
"""
from __future__ import annotations

import io
from dataclasses import dataclass

from PIL import Image, ImageOps, UnidentifiedImageError

from ..avatars import HEIC_ENABLED, sniff_format

MAX_PIXELS = 40_000_000
MAX_SIDE = 2048
JPEG_QUALITY = 85
THUMB_SIDE = 320
THUMB_QUALITY = 75
GIF_MAX_FRAMES = 500


class ImageError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


@dataclass
class Processed:
    data: bytes
    ext: str           # jpg / png / gif
    mime: str
    width: int
    height: int
    thumb: bytes
    still: bytes | None = None   # 仅 GIF：第一帧 JPEG（给模型）


def detect(data: bytes) -> str:
    """jpeg / png / webp / heic / gif；不认识返回空串。"""
    if len(data) >= 6 and data[:6] in (b"GIF87a", b"GIF89a"):
        return "gif"
    return sniff_format(data)


def _flatten(im: Image.Image) -> Image.Image:
    if im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info):
        rgba = im.convert("RGBA")
        bg = Image.new("RGB", rgba.size, (255, 255, 255))
        bg.paste(rgba, mask=rgba.split()[-1])
        return bg
    return im.convert("RGB") if im.mode != "RGB" else im


def _has_alpha(im: Image.Image) -> bool:
    if im.mode in ("RGBA", "LA", "PA") or (im.mode == "P" and "transparency" in im.info):
        alpha = im.convert("RGBA").getchannel("A")
        return alpha.getextrema()[0] < 255
    return False


def _jpeg(im: Image.Image, quality: int, icc: bytes | None = None) -> bytes:
    out = io.BytesIO()
    kw = {"icc_profile": icc} if icc else {}
    _flatten(im).save(out, format="JPEG", quality=quality, optimize=True, **kw)
    return out.getvalue()


def _thumb(im: Image.Image) -> bytes:
    t = _flatten(im).copy()
    t.thumbnail((THUMB_SIDE, THUMB_SIDE), Image.Resampling.LANCZOS)
    return _jpeg(t, THUMB_QUALITY)


def strip_gif(data: bytes) -> bytes:
    """按 GIF 块结构复制，去掉注释扩展（0xFE）和除 NETSCAPE2.0 / ANIMEXTS1.0 外的应用扩展（0xFF）。"""
    def need(n):
        if pos + n > len(data):
            raise ImageError(400, "无法解析图片")

    out = bytearray(data[:13])
    pos = 13
    need(0)
    flags = data[10]
    if flags & 0x80:
        n = 3 * (2 ** ((flags & 0x07) + 1))
        need(n)
        out += data[pos:pos + n]
        pos += n

    def sub_blocks(start: int) -> int:
        p = start
        while True:
            if p >= len(data):
                raise ImageError(400, "无法解析图片")
            size = data[p]
            p += 1 + size
            if size == 0:
                return p

    while True:
        need(1)
        b = data[pos]
        if b == 0x3B:                      # trailer
            out.append(0x3B)
            return bytes(out)
        if b == 0x21:                      # extension
            need(2)
            label = data[pos + 1]
            end = sub_blocks(pos + 2)
            keep = True
            if label == 0xFE:
                keep = False
            elif label == 0xFF:
                ident = data[pos + 3:pos + 3 + 11] if pos + 2 < len(data) and data[pos + 2] >= 11 else b""
                keep = ident in (b"NETSCAPE2.0", b"ANIMEXTS1.0")
            if keep:
                out += data[pos:end]
            pos = end
        elif b == 0x2C:                    # image descriptor
            need(10)
            lflags = data[pos + 9]
            hdr = 10
            if lflags & 0x80:
                hdr += 3 * (2 ** ((lflags & 0x07) + 1))
            need(hdr + 1)
            end = sub_blocks(pos + hdr + 1)   # +1：LZW 最小码长
            out += data[pos:end]
            pos = end
        else:
            raise ImageError(400, "无法解析图片")


def _open(data: bytes) -> Image.Image:
    try:
        im = Image.open(io.BytesIO(data))
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError):
        raise ImageError(400, "无法解析图片")
    w, h = im.size
    if w < 1 or h < 1:
        raise ImageError(400, "无法解析图片")
    if w * h > MAX_PIXELS:
        raise ImageError(400, "图片像素过大（不超过 4000 万像素）")
    return im


def process(data: bytes, max_bytes: int) -> Processed:
    if not data:
        raise ImageError(400, "没有收到图片")
    if len(data) > max_bytes:
        raise ImageError(413, f"图片不能超过 {max(1, max_bytes // (1024 * 1024))}MB")
    kind = detect(data)
    if not kind:
        raise ImageError(415, "仅支持 JPEG、PNG、WebP、HEIC 或 GIF")
    if kind == "heic" and not HEIC_ENABLED:
        raise ImageError(415, "服务器暂不能解码 HEIC，请改用 JPEG 或 PNG")
    if kind == "gif":
        return _process_gif(data)
    im = _open(data)
    try:
        im.load()
        icc = im.info.get("icc_profile")
        im = ImageOps.exif_transpose(im) or im
        im.thumbnail((MAX_SIDE, MAX_SIDE), Image.Resampling.LANCZOS)
        thumb = _thumb(im)
        if kind == "png" and _has_alpha(im):
            out = io.BytesIO()
            im.convert("RGBA").save(out, format="PNG", optimize=True)
            return Processed(out.getvalue(), "png", "image/png", im.width, im.height, thumb)
        return Processed(_jpeg(im, JPEG_QUALITY, icc), "jpg", "image/jpeg", im.width, im.height, thumb)
    except ImageError:
        raise
    except Exception:
        raise ImageError(400, "无法解析图片")


def _process_gif(data: bytes) -> Processed:
    cleaned = strip_gif(data)
    im = _open(cleaned)
    try:
        if im.width > MAX_SIDE or im.height > MAX_SIDE:
            raise ImageError(400, f"GIF 尺寸过大（每边不超过 {MAX_SIDE}）")
        if getattr(im, "n_frames", 1) > GIF_MAX_FRAMES:
            raise ImageError(400, f"GIF 帧数过多（不超过 {GIF_MAX_FRAMES} 帧）")
        im.seek(0)
        first = im.convert("RGBA")
        return Processed(cleaned, "gif", "image/gif", im.width, im.height, _thumb(first),
                         still=_jpeg(first, JPEG_QUALITY))
    except ImageError:
        raise
    except Exception:
        raise ImageError(400, "无法解析图片")
