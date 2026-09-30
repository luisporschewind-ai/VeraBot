"""创建 / 重置演示账号 demo / verabot2026。

用法：
  uv run python scripts/dev/seed_demo.py [base_url]            # 补齐缺失的 Bot 与示例对话（幂等）
  uv run python scripts/dev/seed_demo.py [base_url] --reset    # 清空 demo 的对话 / 提醒 / 协作记录后重新生成
每个 Bot 保留简短、自然的历史：Vera（天气 + 提醒 + ask_bot 各一次）、小研、阿厨各一轮直接对话。
"""
import json
import sqlite3
import sys
from pathlib import Path

import httpx

args = [a for a in sys.argv[1:] if not a.startswith("--")]
RESET = "--reset" in sys.argv
BASE = args[0] if args else "http://127.0.0.1:8000"
DB = Path(__file__).resolve().parents[2] / "data" / "verabot.db"   # backend/data/verabot.db
USER, PW = "demo", "verabot2026"

SPECS = [
    dict(name="Vera", avatar="🦊", color="#0f766e", persona="全能私人助理，负责日程、提醒和日常问题",
         instructions="先给结论再给要点；专业知识类问题用 ask_bot 咨询 小研"),
    dict(name="小研", avatar="🔬", color="#0369a1", persona="资深研究员，擅长知识解释与方案对比",
         instructions="结构化回答，不超过 150 字"),
    dict(name="阿厨", avatar="🍀", color="#d97706", persona="家常菜厨师与营养顾问", instructions="菜谱注明用量"),
]
SCRIPT = {
    "Vera": ["石家庄今天天气怎么样？", "明天早上 9 点提醒我带伞",
             "帮我问问小研：秋天为什么容易感冒？给我三条建议"],
    "小研": ["用三句话解释一下什么是复利"],
    "阿厨": ["今晚想吃点清淡的，推荐一道 20 分钟能做好的家常菜"],
}

c = httpx.Client(base_url=BASE, timeout=180)
r = c.post("/api/auth/register", json={"username": USER, "password": PW})
if r.status_code == 409:
    r = c.post("/api/auth/login", json={"username": USER, "password": PW})
r.raise_for_status()
uid = r.json()["user"]["id"]
h = {"Authorization": "Bearer " + r.json()["token"]}

if RESET:
    # 本地开发工具：直接清理 demo 用户的数据（Token 用量记录保留，作为真实消耗）
    with sqlite3.connect(DB) as db:
        for t in ("messages", "reminders", "delegations"):
            db.execute(f"DELETE FROM {t} WHERE user_id=?", (uid,))

existing = {b["name"]: b for b in c.get("/api/bots", headers=h).json()["bots"]}
bots = {s["name"]: existing.get(s["name"]) or c.post("/api/bots", headers=h, json=s).json() for s in SPECS}


def chat(bot, text):
    with c.stream("POST", f"/api/bots/{bot['id']}/chat", headers=h, json={"message": text}) as resp:
        for _ in resp.iter_lines():
            pass


for name, prompts in SCRIPT.items():
    if not c.get(f"/api/bots/{bots[name]['id']}/messages", headers=h).json()["messages"]:
        for p in prompts:
            chat(bots[name], p)
print(json.dumps({"username": USER, "password": PW, "bots": list(bots), "reset": RESET}, ensure_ascii=False))
