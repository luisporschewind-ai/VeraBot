#!/usr/bin/env python3
"""头像与昵称的确定性测试（Deterministic tests）。

临时 SQLite，不消耗 Token、不触碰正式数据库。覆盖：
schema v2 → v3 迁移、上传校验与 512 JPEG、恢复默认、用户隔离、昵称校验。

运行（在 backend/ 下）：uv run python scripts/test/avatar_profile_test.py
"""
import io
import os
import re
import sqlite3
import sys
import tempfile
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_av_")
DB = str(Path(TMP) / "t.db")
os.environ["VERABOT_DB"] = DB
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")

# ---------- 1. 先摆一个 schema v2 的库（没有昵称 / 头像列） ----------
V2 = """
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  token_budget INTEGER
);
CREATE TABLE bots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  avatar TEXT NOT NULL DEFAULT '🤖',
  color TEXT NOT NULL DEFAULT '#0F766E',
  persona TEXT NOT NULL DEFAULT '',
  instructions TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  allowed_tools TEXT NOT NULL DEFAULT '[]',
  delegate_to TEXT NOT NULL DEFAULT '[]',
  accept_delegation INTEGER NOT NULL DEFAULT 0,
  UNIQUE(user_id, name)
);
CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""
con = sqlite3.connect(DB)
con.executescript(V2)
con.execute("INSERT INTO schema_meta(key,value) VALUES ('version','2')")
con.execute("INSERT INTO users(id,username,password_hash,created_at) VALUES (1,'legacy_av','x','2026-01-01')")
con.execute(
    "INSERT INTO bots(id,user_id,name,avatar,created_at,allowed_tools,delegate_to,accept_delegation) "
    "VALUES (1,1,'OldBot','🐼','2026-01-01','[\"get_weather\"]','[]',0)"
)
con.commit()
con.close()

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # backend/

from verabot import db  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(f"[{'PASS' if ok else 'FAIL'}] {cid} {name} {note}", flush=True)


db.init_db()
db.init_db()  # 幂等
con = sqlite3.connect(DB)
ver = con.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
user_cols = {r[1] for r in con.execute("PRAGMA table_info(users)")}
bot_cols = {r[1] for r in con.execute("PRAGMA table_info(bots)")}
legacy_bot = con.execute("SELECT name, allowed_tools, image_updated_at FROM bots WHERE id=1").fetchone()
has_avatars = con.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='avatars'").fetchone()
con.close()
check("AV-01", "v2→v3(→当前版本) 迁移：版本、列、头像表，且不改写存量 Bot 权限",
      ver == str(db.SCHEMA_VERSION) and {"nickname", "avatar_updated_at"} <= user_cols and "image_updated_at" in bot_cols
      and has_avatars and legacy_bot[0] == "OldBot" and legacy_bot[1] == '["get_weather"]' and legacy_bot[2] is None,
      f"ver={ver} bot={legacy_bot}")

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image  # noqa: E402

from verabot.main import app  # noqa: E402
from verabot.services import avatars as avatar_svc  # noqa: E402

cli = TestClient(app)


def reg(username):
    r = cli.post("/api/auth/register", json={"username": username, "password": "pw123456"})
    body = r.json()
    return r, {"Authorization": "Bearer " + body["token"]}, body["user"]


def jpeg_bytes(w, h, color=(20, 40, 80)):
    buf = io.BytesIO()
    Image.new("RGB", (w, h), color).save(buf, format="JPEG", quality=90)
    return buf.getvalue()


def png_bytes():
    buf = io.BytesIO()
    Image.new("RGBA", (300, 180), (255, 0, 0, 128)).save(buf, format="PNG")
    return buf.getvalue()


def webp_bytes():
    buf = io.BytesIO()
    Image.new("RGB", (640, 480), (0, 128, 0)).save(buf, format="WEBP")
    return buf.getvalue()


def upload(path, data, headers, name="a.jpg", mime="image/jpeg"):
    return cli.post(path, files={"file": (name, data, mime)}, headers=headers)


r, H, user = reg("alice_av")
check("AV-02", "注册用户：昵称为空，display_name 回退用户名，无头像",
      r.status_code == 200 and user["nickname"] is None and user["display_name"] == "alice_av" and user["has_avatar"] is False,
      str(user))
_, H2, user2 = reg("bob_av")

# ---------- 昵称 ----------
ok = cli.patch("/api/me", json={"nickname": "  小云  "}, headers=H)
me = cli.get("/api/me", headers=H).json()
check("NK-01", "昵称去空白并立即出现在 /api/me",
      ok.status_code == 200 and ok.json()["nickname"] == "小云" and ok.json()["display_name"] == "小云"
      and me["nickname"] == "小云" and me["username"] == "alice_av",
      str(ok.json()))
login = cli.post("/api/auth/login", json={"username": "alice_av", "password": "pw123456"}).json()["user"]
check("NK-02", "重新登录仍返回已保存的昵称", login["nickname"] == "小云" and login["display_name"] == "小云", str(login))
def err_text(resp):
    d = resp.json().get("detail")
    if isinstance(d, list):
        return " ".join((x.get("msg") if isinstance(x, dict) else str(x)) or "" for x in d)
    return "" if d is None else str(d)


blank = cli.patch("/api/me", json={"nickname": "   "}, headers=H)
empty = cli.patch("/api/me", json={"nickname": ""}, headers=H)
long = cli.patch("/api/me", json={"nickname": "云" * 33}, headers=H)
ctrl = cli.patch("/api/me", json={"nickname": "a\nb"}, headers=H)
exact = cli.patch("/api/me", json={"nickname": "名" * 32}, headers=H)
check("NK-03", "空白 / 空 / 超长 / 控制字符 → 422，32 字通过",
      (blank.status_code, empty.status_code, long.status_code, ctrl.status_code, exact.status_code) == (422, 422, 422, 422, 200)
      and "不能为空" in err_text(blank) and "32" in err_text(long) and "Value error" not in err_text(blank),
      f"{blank.status_code} {empty.status_code} {long.status_code} {ctrl.status_code} {exact.status_code} {err_text(blank)} | {err_text(long)}")
bob = cli.get("/api/me", headers=H2).json()
check("NK-04", "改昵称不影响其他用户", bob["username"] == "bob_av" and bob["nickname"] is None, str(bob))
# 恢复一个短昵称，后面断言更好读
cli.patch("/api/me", json={"nickname": "小云"}, headers=H)

# ---------- 用户头像 ----------
missing = cli.get("/api/me/avatar", headers=H)
check("AV-03", "未设置时 GET 头像 404", missing.status_code == 404, str(missing.json()))
noauth = cli.get("/api/me/avatar")
check("AV-04", "未登录 401", noauth.status_code == 401, str(noauth.status_code))

wide = jpeg_bytes(800, 400, (10, 20, 30))
up = upload("/api/me/avatar", wide, H)
got = cli.get("/api/me/avatar", headers=H)
im = Image.open(io.BytesIO(got.content))
check("AV-05", "上传 JPEG 后存成 512 正方形，资料 has_avatar",
      up.status_code == 200 and up.json()["has_avatar"] is True and up.json()["avatar_updated_at"]
      and got.status_code == 200 and got.headers["content-type"].startswith("image/jpeg")
      and im.size == (avatar_svc.AVATAR_SIZE, avatar_svc.AVATAR_SIZE) and im.format == "JPEG",
      f"status={up.status_code} size={im.size} bytes={len(got.content)} meta={up.json().get('has_avatar')}")
# 宽图应被居中裁切：左右纯色、中间另一色，结果中心不是被裁掉的边角色
flag = Image.new("RGB", (800, 400), (255, 0, 0))
flag.paste(Image.new("RGB", (200, 400), (0, 255, 0)), (300, 0))
buf = io.BytesIO()
flag.save(buf, format="JPEG", quality=95)
upload("/api/me/avatar", buf.getvalue(), H)
center = Image.open(io.BytesIO(cli.get("/api/me/avatar", headers=H).content))
px = center.getpixel((256, 256))
check("AV-06", "非正方形按中心裁切（中心保留绿色）", px[1] > px[0] and px[1] > px[2], str(px))

png = upload("/api/me/avatar", png_bytes(), H, name="a.png", mime="image/png")
webp = upload("/api/me/avatar", webp_bytes(), H, name="a.webp", mime="image/webp")
png_im = Image.open(io.BytesIO(cli.get("/api/me/avatar", headers=H).content))
check("AV-07", "PNG（含透明）与 WebP 都接受并转成 JPEG",
      png.status_code == 200 and webp.status_code == 200 and png_im.format == "JPEG" and png_im.size == (512, 512),
      f"png={png.status_code} webp={webp.status_code} {png_im.format}")

gif = upload("/api/me/avatar", b"GIF89a" + b"\x00" * 32, H, name="a.gif", mime="image/gif")
heic = upload("/api/me/avatar", b"\x00\x00\x00\x18ftypheic" + b"\x00" * 16, H, name="a.heic", mime="image/heic")
bad = upload("/api/me/avatar", b"\xff\xd8\xff" + b"not-a-jpeg" * 5, H)
heic_ok = heic.status_code == 415 and "HEIC" in heic.json().get("detail", "")
if avatar_svc.HEIC_ENABLED:
    heic_ok = heic.status_code in (200, 400)
check("AV-08", "GIF 415；损坏 JPEG 400；HEIC 在无解码器时 415",
      gif.status_code == 415 and bad.status_code == 400 and heic_ok,
      f"gif={gif.status_code} {gif.json()} bad={bad.status_code} {bad.json()} heic={heic.status_code} {heic.text[:180]}")

old_max = avatar_svc.MAX_AVATAR_BYTES
avatar_svc.MAX_AVATAR_BYTES = 128
try:
    too_big = upload("/api/me/avatar", jpeg_bytes(64, 64), H)
finally:
    avatar_svc.MAX_AVATAR_BYTES = old_max
check("AV-09", "超过大小上限 413", too_big.status_code == 413 and "不能超过" in too_big.json()["detail"], str(too_big.json()))

# bob 看不到 alice 的头像字节
bob_get = cli.get("/api/me/avatar", headers=H2)
alice_bytes = cli.get("/api/me/avatar", headers=H).content
check("AV-10", "用户头像隔离：他人 GET /api/me/avatar 不是这份图片",
      bob_get.status_code == 404 and alice_bytes[:3] == b"\xff\xd8\xff" and bob_get.content != alice_bytes,
      f"bob={bob_get.status_code}")

cleared = cli.delete("/api/me/avatar", headers=H)
after = cli.get("/api/me/avatar", headers=H)
me2 = cli.get("/api/me", headers=H).json()
check("AV-11", "DELETE 恢复默认：has_avatar 为 false，再 GET 404",
      cleared.status_code == 200 and cleared.json()["has_avatar"] is False and cleared.json()["nickname"] == "小云"
      and after.status_code == 404 and me2["has_avatar"] is False and me2["avatar_updated_at"] is None,
      str(cleared.json()))

# ---------- Bot 头像 ----------
bot = cli.post("/api/bots", json={"name": "头像Bot", "avatar": "🦊"}, headers=H).json()
bob_bot = cli.post("/api/bots", json={"name": "BobOnly"}, headers=H2).json()
before = cli.get(f"/api/bots/{bot['id']}/avatar", headers=H)
check("AV-12", "新 Bot 默认无照片，表情字段仍在",
      before.status_code == 404 and bot["avatar"] == "🦊" and bot["has_avatar"] is False, str(bot))

bup = upload(f"/api/bots/{bot['id']}/avatar", jpeg_bytes(900, 300, (1, 2, 3)), H)
listed = {b["id"]: b for b in cli.get("/api/bots", headers=H).json()["bots"]}
bgot = cli.get(f"/api/bots/{bot['id']}/avatar", headers=H)
bim = Image.open(io.BytesIO(bgot.content))
check("AV-13", "Bot 上传后列表带 has_avatar，GET 为 512 JPEG，表情仍保留",
      bup.status_code == 200 and bup.json()["has_avatar"] is True and bup.json()["avatar"] == "🦊"
      and listed[bot["id"]]["has_avatar"] is True and bim.size == (512, 512),
      f"{bup.status_code} emoji={bup.json().get('avatar')}")

cross = [
    cli.get(f"/api/bots/{bot['id']}/avatar", headers=H2).status_code,
    upload(f"/api/bots/{bot['id']}/avatar", jpeg_bytes(32, 32, (9, 9, 9)), H2).status_code,
    cli.delete(f"/api/bots/{bot['id']}/avatar", headers=H2).status_code,
    cli.get(f"/api/bots/{bob_bot['id']}/avatar", headers=H).status_code,
    upload(f"/api/bots/{bob_bot['id']}/avatar", jpeg_bytes(32, 32), H).status_code,
    cli.delete(f"/api/bots/{bob_bot['id']}/avatar", headers=H).status_code,
    cli.get("/api/bots/999999/avatar", headers=H).status_code,
]
still = cli.get(f"/api/bots/{bot['id']}/avatar", headers=H)
check("AV-14", "Bot 头像隔离：他人读写与不存在的 id 都是 404，原图还在",
      cross == [404, 404, 404, 404, 404, 404, 404] and still.status_code == 200 and still.content[:3] == b"\xff\xd8\xff",
      str(cross))

gone = cli.delete(f"/api/bots/{bot['id']}/avatar", headers=H)
emoji = cli.get(f"/api/bots/{bot['id']}", headers=H).json()
check("AV-15", "删除 Bot 照片后恢复表情，GET 404",
      gone.status_code == 200 and gone.json()["has_avatar"] is False and gone.json()["avatar"] == "🦊"
      and emoji["avatar"] == "🦊" and cli.get(f"/api/bots/{bot['id']}/avatar", headers=H).status_code == 404,
      str(gone.json()))

# 删 Bot 时级联删掉头像行
upload(f"/api/bots/{bot['id']}/avatar", jpeg_bytes(40, 40), H)
cli.delete(f"/api/bots/{bot['id']}", headers=H)
n = sqlite3.connect(DB).execute("SELECT COUNT(*) FROM avatars WHERE bot_id=?", (bot["id"],)).fetchone()[0]
check("AV-16", "删除 Bot 时级联删除头像行", n == 0 and cli.get(f"/api/bots/{bot['id']}/avatar", headers=H).status_code == 404, f"rows={n}")

quota = cli.get("/api/quota", headers=H2).json()
check("AV-17", "用量按 Bot 统计带 has_avatar 字段",
      quota.get("per_bot") and all("has_avatar" in b and "avatar" in b for b in quota["per_bot"]),
      str([{k: b.get(k) for k in ("name", "avatar", "has_avatar")} for b in quota.get("per_bot", [])]))

# ---------- AV-18 契约：默认形象 id 能放进已有 avatar 字段，且与 iOS 枚举一致 ----------
def enum_cases(src: str, name: str) -> list[str]:
    body = src.split(f"enum {name}", 1)[1].split("{", 1)[1]
    kept = []
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("case ") or stripped.startswith("//") or stripped.startswith("///") or not stripped:
            kept.append(line)
        else:
            break
    return re.findall(r"case (\w+)", "\n".join(kept))


repo = Path(__file__).resolve().parents[3]
figure_src = (repo / "frontend/ios/Packages/VeraBotKit/Sources/VeraBotCore/BotAvatarFigure.swift").read_text()
lab_src = (repo / "frontend/ios/VeraBot/Features/Settings/AvatarLabView.swift").read_text()
schema_src = (repo / "backend/verabot/api/schemas.py").read_text()
limit = int(re.search(r"avatar: str = Field\(default=.*?max_length=(\d+)", schema_src).group(1))
figures = enum_cases(figure_src, "BotAvatarFigure")
poses = enum_cases(figure_src, "BotAvatarPose")
kinds = enum_cases(lab_src, "AvatarLabCharacterKind")
lab_states = enum_cases(lab_src, "AvatarLabState")
swift_limit = int(re.search(r"maxStoredLength = (\d+)", figure_src).group(1))
stored_ok = []
for name in figures:
    created = cli.post("/api/bots", json={"name": f"形象{name}", "avatar": name}, headers=H)
    body = created.json()
    stored_ok.append(created.status_code == 201 and body.get("avatar") == name and body.get("has_avatar") is False
                     and len(name) <= limit)
    if created.status_code == 201 and name == "veraBean":
        uploaded = upload(f"/api/bots/{body['id']}/avatar", jpeg_bytes(80, 80), H)
        photo = uploaded.json()
        stored_ok.append(uploaded.status_code == 200 and photo.get("has_avatar") is True and photo.get("avatar") == "veraBean")
    if created.status_code == 201:
        cli.delete(f"/api/bots/{body['id']}", headers=H)
too_long = cli.post("/api/bots", json={"name": "形象过长", "avatar": "veraBeanX"}, headers=H)
check("AV-18", "契约：形象 id ≤ avatar max_length，与实验室角色 / 姿态同名；照片不改 avatar",
      figures == kinds and poses == lab_states and swift_limit == limit == 8
      and all(len(n) <= limit for n in figures) and "veraBean" in figures and len("veraBean") == 8
      and all(stored_ok) and len(stored_ok) == len(figures) + 1
      and too_long.status_code == 422
      and all(title in figure_src for title in ("V豆", "芽芽", "星点", "云朵", "方糖")),
      f"figures={figures} poses={poses} kinds={kinds} states={lab_states} stored={stored_ok} long={too_long.status_code}")

p = sum(1 for r in RESULTS if r[2])
print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
sys.exit(0 if p == len(RESULTS) else 1)
