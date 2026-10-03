#!/usr/bin/env python3
"""图片附件 P1（schema v12）：上传 / 处理 / 发送 / 召回 / 委派 / 确认 / 删除 / 对账 / 隔离 / iOS 契约。

只用临时 SQLite + 临时附件目录，LLM 全部用假实现（不联网）。用例编号见 docs/TEST_CASES_v0.1.md「图片附件」。
"""
import asyncio, base64, io, json, os, re, shutil, sqlite3, sys, tempfile, time
from pathlib import Path

TMP = tempfile.mkdtemp(prefix="vb_att_")
os.environ["VERABOT_DB"] = str(Path(TMP) / "t.db")
os.environ["VERABOT_DATA_DIR"] = TMP
os.environ.setdefault("DEEPSEEK_API_KEY", "test-not-used")
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
IOS = ROOT.parent / "frontend" / "ios"

from PIL import Image  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from verabot import db  # noqa: E402
from verabot.main import app  # noqa: E402
from verabot.services import llm  # noqa: E402
from verabot.services.attachments import images, repo  # noqa: E402
from verabot.services.attachments.store import LocalStore, get_store  # noqa: E402
from verabot.tools.registry import ToolContext, TurnState  # noqa: E402

RESULTS = []


def check(cid, name, ok, note=""):
    RESULTS.append((cid, name, bool(ok), note))
    print(("PASS " if ok else "FAIL ") + cid, name, "" if ok else note)


db.init_db(); db.init_db()
cli = TestClient(app)
STORE = get_store()


def register(u):
    r = cli.post("/api/auth/register", json={"username": u, "password": "pw123456"}).json()
    return {"Authorization": "Bearer " + r["token"]}, r["user"]["id"]


H, UID = register("alice")
H2, UID2 = register("bob")
bot = cli.post("/api/bots", json={"name": "Vera"}, headers=H).json()
helper = cli.post("/api/bots", json={"name": "Helper"}, headers=H).json()
bob_bot = cli.post("/api/bots", json={"name": "BobBot"}, headers=H2).json()


# ---------------------------------------------------------------- 测试图片
def jpeg_with_exif(size=(400, 200)):
    im = Image.new("RGB", size, (200, 30, 30))
    ex = Image.Exif()
    ex[0x0112] = 6                                  # Orientation：顺时针 90°
    ex[0x010F] = "SecretCam"                        # Make
    ex[0x8825] = {1: "N", 2: (39.0, 54.0, 0.0)}     # GPS IFD
    b = io.BytesIO(); im.save(b, "JPEG", exif=ex.tobytes()); return b.getvalue()


def png_alpha(size=(64, 64)):
    im = Image.new("RGBA", size, (0, 0, 255, 0)); im.putpixel((1, 1), (255, 0, 0, 255))
    b = io.BytesIO(); im.save(b, "PNG"); return b.getvalue()


def png_opaque(size=(3000, 1500)):
    b = io.BytesIO(); Image.new("RGB", size, (0, 128, 0)).save(b, "PNG"); return b.getvalue()


def webp():
    b = io.BytesIO(); Image.new("RGB", (100, 80), (9, 9, 9)).save(b, "WEBP"); return b.getvalue()


def gif(frames=3, comment=True):
    fs = [Image.new("RGB", (40, 30), (i * 40 % 256, 0, 0)) for i in range(frames)]
    b = io.BytesIO()
    fs[0].save(b, "GIF", save_all=True, append_images=fs[1:], loop=0, duration=100,
               comment=b"secret comment" if comment else b"")
    return b.getvalue()


def upload(data, h=H, bot_id=None, name="x.jpg"):
    form = {"bot_id": str(bot_id)} if bot_id else {}
    return cli.post("/api/attachments", files={"file": (name, data, "application/octet-stream")}, data=form, headers=h)


def gif_frames(data):
    with Image.open(io.BytesIO(data)) as im:
        return getattr(im, "n_frames", 1)


# ---------------------------------------------------------------- ATT-01 上传
r_jpg = upload(jpeg_with_exif(), bot_id=bot["id"])
r_png = upload(png_alpha())
r_big = upload(png_opaque())
r_webp = upload(webp())
r_gif = upload(gif())
ok = all(r.status_code == 201 for r in (r_jpg, r_png, r_big, r_webp, r_gif))
j = r_jpg.json() if r_jpg.status_code == 201 else {}
rows = {k: repo.get(UID, r.json()["id"]) for k, r in
        {"jpg": r_jpg, "png": r_png, "big": r_big, "webp": r_webp, "gif": r_gif}.items() if r.status_code == 201}
gif_row = rows.get("gif")
check("ATT-01", "上传 JPEG/PNG/WebP/GIF：201，字段齐全，长边 ≤ 2048，有缩略图；GIF 原帧数不变；透明 PNG 保持 PNG",
      ok and set(j) == {"id", "kind", "mime", "width", "height", "bytes", "status", "expires_at"}
      and j["status"] == "pending" and j["kind"] == "image" and re.fullmatch(r"att_[a-z2-7]{26}", j["id"])
      and max(rows["big"]["width"], rows["big"]["height"]) == 2048 and rows["big"]["mime"] == "image/jpeg"
      and rows["png"]["mime"] == "image/png" and rows["webp"]["mime"] == "image/jpeg"
      and all(STORE.exists(r["thumb_key"]) for r in rows.values())
      and gif_row["mime"] == "image/gif" and gif_frames(repo.file_path(gif_row).read_bytes()) == 3
      and repo.file_path(gif_row, "model").read_bytes()[:3] == b"\xff\xd8\xff",
      str([r.status_code for r in (r_jpg, r_png, r_big, r_webp, r_gif)]))
k = rows["jpg"]["storage_key"]
check("ATT-01b", "存储路径 u<uid>/<id前2位>/att_<id>.jpg；目录 0700、文件 0600；sha256 已存",
      k == f"u{UID}/{j['id'][4:6]}/{j['id']}.jpg"
      and oct((STORE.root / k).stat().st_mode & 0o777) == "0o600"
      and oct((STORE.root / k).parent.stat().st_mode & 0o777) == "0o700"
      and len(rows["jpg"]["sha256"]) == 64 and rows["jpg"]["storage_backend"] == "local", k)
r_heic = upload(b"\x00\x00\x00\x18ftypheic" + b"\x00" * 64)
check("ATT-01c", "HEIC：服务器无 pillow_heif 时 415 中文提示（有则正常解码）",
      r_heic.status_code == 415 if not images.HEIC_ENABLED else r_heic.status_code in (201, 400), r_heic.text)

# ---------------------------------------------------------------- ATT-02 类型 / 大小 / 像素
r_fake = upload(b"%PDF-1.7 not an image", name="a.jpg")
old_max = repo.ATTACHMENT_MAX_BYTES
repo.ATTACHMENT_MAX_BYTES = 1000
r_413 = upload(jpeg_with_exif())
repo.ATTACHMENT_MAX_BYTES = old_max
old_px = images.MAX_PIXELS
images.MAX_PIXELS = 10_000
r_px = upload(png_opaque((200, 100)))
images.MAX_PIXELS = old_px
r_bad = upload(b"\xff\xd8\xff\xe0garbage")
check("ATT-02", "伪造扩展名 415、超大小 413、超像素 400、损坏 400（中文提示）",
      r_fake.status_code == 415 and r_413.status_code == 413 and r_px.status_code == 400 and r_bad.status_code == 400
      and "像素" in r_px.json()["detail"],
      f"{r_fake.status_code} {r_413.status_code} {r_px.status_code} {r_bad.status_code}")

# ---------------------------------------------------------------- ATT-03 EXIF
out = repo.file_path(rows["jpg"]).read_bytes()
with Image.open(io.BytesIO(out)) as im:
    exif = im.getexif()
    size = im.size
gif_raw = repo.file_path(gif_row).read_bytes()
check("ATT-03", "输出无 EXIF / GPS / 相机型号，方向已转正（400×200 + Orientation 6 → 200×400）；GIF 注释块已去掉",
      len(exif) == 0 and b"SecretCam" not in out and size == (200, 400) and b"secret comment" not in gif_raw
      and b"NETSCAPE2.0" in gif_raw, f"exif={dict(exif)} size={size}")

# ---------------------------------------------------------------- 假 LLM
CALLS = []          # 每次 stream_chat 的 messages
COMPLETES = []      # 每次 complete 的 messages
SCRIPT = []         # stream_chat 的脚本：str = 文本回复；dict = 工具调用；Exception = 抛出
CAPTION = "一张红色的图片，上面没有文字。"


async def fake_stream(messages, tools):
    CALLS.append({"messages": json.loads(json.dumps(messages)), "tools": [t["function"]["name"] for t in tools or []]})
    step = SCRIPT.pop(0) if SCRIPT else "好的"
    if isinstance(step, Exception):
        raise step
    if isinstance(step, dict):
        yield "tool_calls", [{"id": f"c{len(CALLS)}", "name": step["name"], "arguments": json.dumps(step["args"])}]
    else:
        yield "delta", step
    yield "usage", {"total_tokens": 5}
    yield "finish", "stop"


COMPLETE_SCRIPT = []


async def fake_complete(messages, tools):
    COMPLETES.append(json.loads(json.dumps(messages)))
    step = COMPLETE_SCRIPT.pop(0) if COMPLETE_SCRIPT else CAPTION
    if isinstance(step, Exception):
        raise step
    return {"role": "assistant", "content": step}, {"total_tokens": 7}


llm.stream_chat = fake_stream
llm.complete = fake_complete


def sse(bot_id, message="", ids=(), h=H):
    r = cli.post(f"/api/bots/{bot_id}/chat", json={"message": message, "attachment_ids": list(ids)}, headers=h)
    events = []
    ev = None
    for line in r.text.splitlines():
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:"):
            events.append((ev, json.loads(line[5:].strip())))
    return r, events


def user_msgs(call):
    return [m for m in call["messages"] if m["role"] == "user"]


def has_image(content):
    return isinstance(content, list) and any(p.get("type") == "image_url" for p in content)


# ---------------------------------------------------------------- ATT-04 发送
att1 = j["id"]
CALLS.clear(); COMPLETES.clear()
r, evs = sse(bot["id"], "这是什么？", [att1])
last_user = user_msgs(CALLS[0])[-1]["content"] if CALLS else None
img = [p for p in (last_user or []) if isinstance(p, dict) and p.get("type") == "image_url"]
row1 = repo.get(UID, att1)
msgs = cli.get(f"/api/bots/{bot['id']}/messages", headers=H).json()["messages"]
user_row = [m for m in msgs if m["role"] == "user"][-1]
check("ATT-04", "发送 attachment_ids：本轮 user content 为数组（text + base64 image_url）；附件绑定到用户消息；消息列表带 attachments",
      r.status_code == 200 and isinstance(last_user, list) and len(img) == 1
      and img[0]["image_url"]["url"].startswith("data:image/jpeg;base64,")
      and base64.b64decode(img[0]["image_url"]["url"].split(",", 1)[1]) == out
      and f"[图片 {att1}]" in last_user[0]["text"]
      and row1["status"] == "attached" and row1["message_id"] == user_row["id"] and row1["expires_at"] is None
      and [a["id"] for a in user_row["attachments"]] == [att1]
      and set(user_row["attachments"][0]) == {"id", "kind", "mime", "width", "height", "bytes", "status", "expires_at"}
      and "view_image" not in CALLS[0]["tools"],
      f"{r.status_code} {str(last_user)[:200]}")

# ---------------------------------------------------------------- ATT-05 描述 + 按需召回
row1 = repo.get(UID, att1)
usage_kinds = [x[0] for x in sqlite3.connect(os.environ["VERABOT_DB"]).execute(
    "SELECT kind FROM usage_log WHERE user_id=?", (UID,)).fetchall()]
caption_ok = row1["caption"] == CAPTION and row1["caption_status"] == "ok" and "caption" in usage_kinds \
    and len(COMPLETES) == 1 and has_image(COMPLETES[0][-1]["content"])
CALLS.clear()
sse(bot["id"], "明天天气怎么样")
hist = CALLS[0]
no_image = not any(has_image(m.get("content")) for m in hist["messages"])
cap_text = any(isinstance(m.get("content"), str) and f"[图片 {att1}：{CAPTION}]" in m["content"] for m in hist["messages"])
check("ATT-05a", "首轮后 caption 已存（用量记 caption）；后续轮次旧图只发「[图片 att_x：描述]」、无 image_url；view_image 已暴露",
      caption_ok and no_image and cap_text and "view_image" in hist["tools"], f"cap={row1['caption']} tools={hist['tools']}")
CALLS.clear()
sse(bot["id"], "刚才那张图里是什么颜色？")
kw = CALLS[0]
recalled = [m for m in user_msgs(kw) if has_image(m["content"])]
check("ATT-05b", "关键词兜底（刚才那张图）：本轮 user 消息重新带原图（1 张），只附最近一张",
      len(recalled) == 1 and recalled[0] is user_msgs(kw)[-1], str([type(m["content"]).__name__ for m in user_msgs(kw)]))
CALLS.clear()
SCRIPT[:] = [{"name": "view_image", "args": {"attachment_id": att1}},
             {"name": "view_image", "args": {"attachment_id": att1}}, "看到了，红色"]
r, evs = sse(bot["id"], "颜色深浅如何？")
tool_results = [d for e, d in evs if e == "tool_result"]
second = CALLS[1] if len(CALLS) > 1 else {"messages": []}
recall_users = [m for m in user_msgs(second) if has_image(m["content"])]
check("ATT-05c", "view_image：原图作为额外 user 消息附上；每轮最多 1 张（第 2 次返回 recall_limit）",
      len(recall_users) == 1 and tool_results[0]["result"].get("ok") and tool_results[1]["result"].get("code") == "recall_limit",
      str(tool_results))
CALLS.clear()
sse(bot["id"], "确认，按照图里的内容创建提醒")
check("ATT-05d", "以「确认」开头的消息不触发关键词兜底（避免确认后又被带图拦截）",
      not any(has_image(m["content"]) for m in user_msgs(CALLS[0])))

# ---------------------------------------------------------------- ATT-06 他人 / 已绑定 / 过期 / 其他 Bot
bob_att = upload(gif(), h=H2).json()["id"]
r_other = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": [bob_att]}, headers=H)
r_bound = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": [att1]}, headers=H)
exp_id = upload(webp()).json()["id"]
with db.tx() as c:
    c.execute("UPDATE attachments SET expires_at='2000-01-01T00:00:00+00:00' WHERE id=?", (exp_id,))
r_exp = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": [exp_id]}, headers=H)
helper_att = upload(webp(), bot_id=helper["id"]).json()["id"]
r_wrongbot = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": [helper_att]}, headers=H)
CALLS.clear()
r_ghost = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": ["att_" + "a" * 26]}, headers=H)
check("ATT-06", "他人 / 不存在 404，已发送 409，过期 410，其他 Bot 的图 422；都不调用模型",
      r_other.status_code == 404 and r_ghost.status_code == 404 and r_bound.status_code == 409
      and r_exp.status_code == 410 and r_wrongbot.status_code == 422 and not CALLS,
      f"{r_other.status_code} {r_ghost.status_code} {r_bound.status_code} {r_exp.status_code} {r_wrongbot.status_code}")

# ---------------------------------------------------------------- ATT-07 数量
a2, a3 = upload(webp()).json()["id"], upload(webp()).json()["id"]
r_two = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "看", "attachment_ids": [a2, a3]}, headers=H)
r_empty = cli.post(f"/api/bots/{bot['id']}/chat", json={"message": "  "}, headers=H)
old_day = repo.ATTACHMENTS_PER_DAY
repo.ATTACHMENTS_PER_DAY = 1
r_429 = upload(webp())
repo.ATTACHMENTS_PER_DAY = old_day
old_quota = repo.ATTACHMENT_USER_QUOTA_BYTES
repo.ATTACHMENT_USER_QUOTA_BYTES = 10
r_full = upload(webp())
repo.ATTACHMENT_USER_QUOTA_BYTES = old_quota
CALLS.clear()
r_only, evs_only = sse(bot["id"], "", [a2])
only_text = user_msgs(CALLS[0])[-1]["content"][0]["text"] if CALLS else ""
check("ATT-07", "每条 > 1 张 422；每天超限 429 中文；存储满 413；无图空白消息 422；只发图片（无文字）允许",
      r_two.status_code == 422 and r_429.status_code == 429 and "上限" in r_429.json()["detail"]["message"]
      and r_full.status_code == 413 and r_empty.status_code == 422 and r_only.status_code == 200
      and "用户发送了一张图片" in only_text,
      f"{r_two.status_code} {r_429.status_code} {r_full.status_code} {r_empty.status_code} {r_only.status_code}")

# ---------------------------------------------------------------- ATT-10 看图失败
v_att = upload(webp()).json()["id"]
SCRIPT[:] = [llm.LLMError('DeepSeek HTTP 400: {"error":{"message":"This model does not support image input"}}')]
_, evs = sse(bot["id"], "看图", [v_att])
err = [d for e, d in evs if e == "error"]
v2 = upload(webp()).json()["id"]
SCRIPT[:] = [llm.LLMError("DeepSeek HTTP 500: internal")]
_, evs2 = sse(bot["id"], "看图", [v2])
err2 = [d for e, d in evs2 if e == "error"]
SCRIPT[:] = [llm.LLMError("DeepSeek HTTP 500: internal")]
_, evs3 = sse(bot["id"], "普通问题")
err3 = [d for e, d in evs3 if e == "error"]
check("ATT-10", "看图失败：vision_unsupported / vision_failed + 中文「当前模型无法识别这张图片」，不降级；无图错误不受影响",
      err and err[0]["code"] == "vision_unsupported" and err[0]["message"].startswith("当前模型无法识别这张图片：")
      and err2 and err2[0]["code"] == "vision_failed" and err3 and "code" not in err3[0]
      and repo.get(UID, v_att)["caption_status"] is None,
      f"{err} {err2} {err3}")

# ---------------------------------------------------------------- ATT-11 委派转发
cli.patch(f"/api/bots/{bot['id']}", json={"allowed_tools": ["ask_bot", "create_reminder", "get_weather"],
                                          "delegate_to": [helper["id"]]}, headers=H)
cli.patch(f"/api/bots/{helper['id']}", json={"accept_delegation": True, "allowed_tools": ["create_reminder"]}, headers=H)
d_att = upload(webp(), bot_id=bot["id"]).json()["id"]
COMPLETES.clear()
COMPLETE_SCRIPT[:] = ["Helper：图里是黑色方块"]
SCRIPT[:] = [{"name": "ask_bot", "args": {"bot_name": "Helper", "question": "这张图是什么？"}}, "Helper 说是黑色方块"]
_, evs = sse(bot["id"], "请让 Helper 看看这张图", [d_att])
deleg_user = COMPLETES[0][-1]["content"] if COMPLETES else None
tr = [d for e, d in evs if e == "tool_result" and d["name"] == "ask_bot"]
audit = [json.loads(x[0]) for x in sqlite3.connect(os.environ["VERABOT_DB"]).execute(
    "SELECT detail FROM audit_log WHERE kind='delegation_attachments'").fetchall()]
check("ATT-11", "委派：被委派 Bot 的 user 消息带同一图片 base64；结果与审计含 attachment_ids；不带对话历史",
      has_image(deleg_user) and tr and tr[0]["result"].get("attachment_ids") == [d_att]
      and audit and audit[-1]["attachment_ids"] == [d_att] and len(COMPLETES[0]) == 2,
      f"{str(deleg_user)[:120]} {tr and tr[0]['result']}")

# ---------------------------------------------------------------- ATT-16 带图轮次写操作需确认
w_att = upload(webp(), bot_id=bot["id"]).json()["id"]
SCRIPT[:] = [{"name": "create_reminder", "args": {"content": "按图片开会", "due_at": "2026-10-04 09:00"}},
             {"name": "get_weather", "args": {"city": "北京"}}, "好的"]
_, evs = sse(bot["id"], "按图片建个提醒", [w_att])
res = {d["name"]: d["result"] for e, d in evs if e == "tool_result"}
n_rem = sqlite3.connect(os.environ["VERABOT_DB"]).execute("SELECT COUNT(*) FROM reminders WHERE user_id=?", (UID,)).fetchone()[0]
from verabot.agents.tool_router import dispatch  # noqa: E402
tainted = TurnState(); tainted.image_tainted = True; tainted.image_ids = [w_att]
deleg_ctx = ToolContext(user_id=UID, bot=db.get_bot(UID, helper["id"]), depth=1, turn=tainted)
deleg_res = asyncio.run(dispatch(deleg_ctx, "create_reminder", json.dumps({"content": "x"})))
SCRIPT[:] = [{"name": "create_reminder", "args": {"content": "确认后的提醒", "due_at": "2026-10-04 09:00"}}, "已创建"]
_, evs_ok = sse(bot["id"], "确认")
res_ok = [d["result"] for e, d in evs_ok if e == "tool_result"]
n_rem2 = sqlite3.connect(os.environ["VERABOT_DB"]).execute("SELECT COUNT(*) FROM reminders WHERE user_id=?", (UID,)).fetchone()[0]
check("ATT-16", "带图轮次：create_reminder 返回 image_needs_confirmation 且不执行（委派链同样拦截）；只读工具正常；"
      "下一条文字「确认」后执行",
      res.get("create_reminder", {}).get("code") == "image_needs_confirmation" and n_rem == 0
      and "error" not in res.get("get_weather", {"error": 1}) and deleg_res.get("code") == "image_needs_confirmation"
      and res_ok and "error" not in res_ok[0] and n_rem2 == 1,
      f"{res} n={n_rem} deleg={deleg_res} ok={res_ok}")

# ---------------------------------------------------------------- ISO-ATT-01 隔离
pend = upload(webp()).json()["id"]
iso = [cli.get(f"/api/attachments/{att1}", headers=H2), cli.get(f"/api/attachments/{att1}/content", headers=H2),
       cli.get(f"/api/attachments/{att1}/thumb", headers=H2), cli.delete(f"/api/attachments/{pend}", headers=H2)]
mine = [cli.get(f"/api/attachments/{att1}", headers=H), cli.get(f"/api/attachments/{att1}/content", headers=H),
        cli.get(f"/api/attachments/{att1}/thumb", headers=H)]
noauth = cli.get(f"/api/attachments/{att1}/content")
check("ISO-ATT-01", "B 读取 / 删除 A 的附件全部 404；本人 200 且 private, no-store + nosniff；未登录 401",
      all(x.status_code == 404 for x in iso) and all(x.status_code == 200 for x in mine)
      and all("no-store" in x.headers.get("cache-control", "") for x in mine + iso)
      and all(x.headers.get("cache-control") == "private, no-store" for x in mine[1:])
      and mine[1].headers.get("x-content-type-options") == "nosniff" and mine[1].content == out
      and mine[1].headers["content-type"] == "image/jpeg" and mine[2].content[:3] == b"\xff\xd8\xff"
      and noauth.status_code == 401 and repo.get(UID, pend) is not None,
      str([x.status_code for x in iso + mine]) + f" {noauth.status_code}")
r_del_sent = cli.delete(f"/api/attachments/{att1}", headers=H)
r_del = cli.delete(f"/api/attachments/{pend}", headers=H)
pend_row_gone = repo.get(UID, pend) is None
check("ATT-06b", "DELETE：未发送的图 200 且文件删除；已发送的图 409（随消息删除）",
      r_del.status_code == 200 and pend_row_gone and r_del_sent.status_code == 409, f"{r_del.status_code} {r_del_sent.status_code}")

# ---------------------------------------------------------------- ATT-12 原子写入
orig_tx = db.tx
class Boom(Exception): pass
def bad_tx():
    from contextlib import contextmanager
    @contextmanager
    def cm():
        with orig_tx() as c:
            class Wrap:
                def execute(self, sql, *a):
                    if sql.startswith("INSERT INTO attachments"):
                        raise Boom()
                    return c.execute(sql, *a)
            yield Wrap()
    return cm()
before = set(k for k, _ in STORE.iter_keys())
db.tx = bad_tx
try:
    upload_err = None
    try:
        repo.create(UID, None, webp())
    except Boom:
        upload_err = "boom"
finally:
    db.tx = orig_tx
after = set(k for k, _ in STORE.iter_keys())
tmp_left = list(STORE.tmp_dir.glob("*")) if STORE.tmp_dir.exists() else []
check("ATT-12", "原子写入：写库失败后文件全部删除，tmp/ 无残留",
      upload_err == "boom" and after == before and not tmp_left, f"{after - before} tmp={tmp_left}")

# ---------------------------------------------------------------- ATT-14 路径穿越
s = LocalStore(Path(TMP) / "attachments")
bad = ["../t.db", "u1/../../t.db", "/etc/passwd", "u1/..", "tmp/x.part", "", "u1\\..\\x"]
put_rejected = True
try:
    s.put("../escape.jpg", b"x")
    put_rejected = False
except ValueError:
    pass
check("ATT-14", "路径穿越：含 ../、绝对路径、tmp/ 的 storage_key 一律拒绝（读 None、写 ValueError）",
      all(s.resolve(k) is None for k in bad) and put_rejected and not (Path(TMP) / "escape.jpg").exists())

# ---------------------------------------------------------------- ATT-09 / ATT-13 对账
p1 = upload(webp()).json()["id"]
p1_row = repo.get(UID, p1)
with db.tx() as c:
    c.execute("UPDATE attachments SET expires_at='2000-01-01T00:00:00+00:00' WHERE id=?", (p1,))
orphan = STORE.root / f"u{UID}/zz/att_orphan.jpg"
orphan.parent.mkdir(parents=True, exist_ok=True); orphan.write_bytes(b"x")
fresh_orphan = STORE.root / f"u{UID}/zz/att_fresh.jpg"; fresh_orphan.write_bytes(b"x")
old = time.time() - 7200
os.utime(orphan, (old, old))
m_att = upload(webp()).json()["id"]
m_row = repo.get(UID, m_att)
(STORE.root / m_row["storage_key"]).unlink()
stats = repo.reconcile()
r_410 = cli.get(f"/api/attachments/{m_att}/content", headers=H)
check("ATT-09", "pending 超过 24 小时：对账删除行和文件", repo.get(UID, p1) is None and not STORE.exists(p1_row["storage_key"])
      and stats["expired"] >= 1, str(stats))
check("ATT-13", "孤儿对账：> 1 小时的多余文件删除、新文件保留；库有磁盘无只告警，接口 410「图片已删除或无法加载」",
      not orphan.exists() and fresh_orphan.exists() and stats["missing"] >= 1 and r_410.status_code == 410
      and "图片已删除" in r_410.json()["detail"], f"{stats} {r_410.status_code}")
fresh_orphan.unlink()
with db.tx() as c:
    c.execute("DELETE FROM attachments WHERE id=?", (m_att,))
repo.delete_files(repo.file_keys(m_row))

# ---------------------------------------------------------------- ATT-15 备份恢复
bk = Path(tempfile.mkdtemp(prefix="vb_att_bk_"))
src = sqlite3.connect(os.environ["VERABOT_DB"]); dst = sqlite3.connect(bk / "verabot.db")
src.backup(dst); dst.close(); src.close()
shutil.copytree(STORE.root, bk / "attachments", ignore=shutil.ignore_patterns("tmp"))
restored = LocalStore(bk / "attachments")
rr = sqlite3.connect(bk / "verabot.db").execute("SELECT storage_key, thumb_key FROM attachments").fetchall()
check("ATT-15", "备份（SQLite backup + 复制目录）后恢复：每条记录的原图和缩略图都在",
      rr and all(restored.exists(a) and restored.exists(b) for a, b in rr), f"{len(rr)} rows")

# ---------------------------------------------------------------- ATT-17 / ATT-08 删除
sent = repo.get(UID, d_att)
with db.tx() as c:
    c.execute("DELETE FROM messages WHERE id=?", (sent["message_id"],))
gone_row = repo.get(UID, d_att) is None
repo.reconcile(now=time.time() + 7200)
check("ATT-17", "删除单条消息（目前无接口，直接删行）：附件行级联删除；文件由对账清理",
      gone_row and not STORE.exists(sent["storage_key"]) and not STORE.exists(sent["thumb_key"]))
keys_bot = [k for r in repo.for_messages(UID, [m["id"] for m in cli.get(f"/api/bots/{bot['id']}/messages", headers=H).json()["messages"]]).values() for x in r for k in repo.file_keys(x)]
cli.delete(f"/api/bots/{bot['id']}/messages", headers=H)
n_bot = sqlite3.connect(os.environ["VERABOT_DB"]).execute("SELECT COUNT(*) FROM attachments WHERE bot_id=?", (bot["id"],)).fetchone()[0]
clear_ok = keys_bot and n_bot == 0 and not any(STORE.exists(k) for k in keys_bot)
h_att = upload(webp(), bot_id=helper["id"]).json()["id"]
h_row = repo.get(UID, h_att)
cli.delete(f"/api/bots/{helper['id']}", headers=H)
bot_del_ok = repo.get(UID, h_att) is None and not STORE.exists(h_row["storage_key"])
# 删除账号：没有接口；用户行删除后附件行级联删除，文件由对账清理
bob_rows = [{"storage_key": r[0]} for r in sqlite3.connect(os.environ["VERABOT_DB"]).execute("SELECT storage_key FROM attachments WHERE user_id=?", (UID2,))]
with db.tx() as c:
    c.execute("DELETE FROM users WHERE id=?", (UID2,))
repo.reconcile(now=time.time() + 7200)
acct_ok = bob_rows and not any(STORE.exists(r["storage_key"]) for r in bob_rows)
check("ATT-08", "清空对话 / 删除 Bot：行与文件立即删除；删除账号：行级联删除、文件由对账清理",
      clear_ok and bot_del_ok and acct_ok, f"clear={clear_ok} bot={bot_del_ok} acct={acct_ok}")

# ---------------------------------------------------------------- ATT-18 GIF
g_att = upload(gif(5), bot_id=bot["id"]).json()["id"]
CALLS.clear()
sse(bot["id"], "这个动图是什么", [g_att])
gp = [p for p in user_msgs(CALLS[0])[-1]["content"] if isinstance(p, dict) and p.get("type") == "image_url"]
g_content = cli.get(f"/api/attachments/{g_att}/content", headers=H)
check("ATT-18", "GIF：原文件全部帧保留，接口按 image/gif 返回（iOS 播放动画）；发给模型的是第一帧静态 JPEG（Boss 2026-10-03 决定）",
      gp and gp[0]["image_url"]["url"].startswith("data:image/jpeg;base64,") and g_content.status_code == 200
      and g_content.headers["content-type"] == "image/gif" and gif_frames(g_content.content) == 5)

# ---------------------------------------------------------------- 迁移
c = sqlite3.connect(os.environ["VERABOT_DB"])
ver = c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
cols = {r[1] for r in c.execute("PRAGMA table_info(attachments)")}
idx = {r[1] for r in c.execute("PRAGMA index_list(attachments)")}
c.close()
check("ATT-MIG", "schema v12：attachments 表字段齐全（storage_backend / storage_key / thumb_key / caption），idx_att_user",
      ver == "12" == str(db.SCHEMA_VERSION) and {"id", "user_id", "bot_id", "message_id", "kind", "mime", "bytes", "width",
      "height", "sha256", "storage_backend", "storage_key", "thumb_key", "caption", "caption_status", "status",
      "created_at", "expires_at"} == cols and "idx_att_user" in idx, f"{ver} {cols}")

PUBLIC_KEYS = set(repo.public(repo.get(UID, g_att)).keys())
# v11 → v12：模拟一个 v11 库（没有 attachments 表），再启动一次
with db.tx() as c:
    n_rem_before = c.execute("SELECT COUNT(*) FROM reminders").fetchone()[0]
    c.execute("DROP TABLE attachments")
    c.execute("UPDATE schema_meta SET value='11' WHERE key='version'")
db.init_db()
c = sqlite3.connect(os.environ["VERABOT_DB"])
ver2 = c.execute("SELECT value FROM schema_meta WHERE key='version'").fetchone()[0]
has_tbl = c.execute("SELECT 1 FROM sqlite_master WHERE name='attachments'").fetchone() is not None
n_rem_after = c.execute("SELECT COUNT(*) FROM reminders").fetchone()[0]
c.close()
check("ATT-MIG-11", "v11 → v12：补建 attachments 表、版本 12，提醒数据不变",
      ver2 == "12" and has_tbl and n_rem_before == n_rem_after, f"{ver2} {has_tbl}")

# ---------------------------------------------------------------- ATT-CONTRACT
swift = (IOS / "Packages/VeraBotKit/Sources/VeraBotCore/Attachment.swift").read_text(encoding="utf-8")
block = swift[swift.index("enum CodingKeys"):]
block = block[:block.index("}")]
keys = set()
for line in block.splitlines():
    line = line.strip()
    if not line.startswith("case "):
        continue
    for part in line[5:].split(","):
        part = part.strip()
        keys.add(part.split("=", 1)[1].strip().strip('"') if "=" in part else part)
models = (IOS / "Packages/VeraBotKit/Sources/VeraBotCore/Models.swift").read_text(encoding="utf-8")
api = (IOS / "Packages/VeraBotKit/Sources/VeraBotNetworking/APIClient+Attachments.swift").read_text(encoding="utf-8")
check("ATT-CONTRACT", "契约：iOS Attachment CodingKeys = 后端 public() 键；ChatMessage.attachments / ChatRequest.attachment_ids；"
      "上传字段 file、路径一致",
      keys == PUBLIC_KEYS
      and 'case attachments' in models and 'case attachmentIDs = "attachment_ids"' in swift
      and 'name=\\"file\\"' in api and '"/api/attachments"' in api and "/content" in api and "/thumb" in api,
      f"swift={sorted(keys)}")

p = sum(1 for r in RESULTS if r[2])
print(f"\nSUMMARY {p}/{len(RESULTS)} passed")
sys.exit(0 if p == len(RESULTS) else 1)
