"""用 Playwright + 本机 Chrome 无头模式截取 Web UI（含一次真实流式对话）。
运行前先执行 seed_demo.py --reset，保证 demo 历史干净、不会累积重复问答。"""
import asyncio
import os
import random
import subprocess
import sys

from playwright.async_api import async_playwright

_args = [a for a in sys.argv[1:] if not a.startswith("--")]
BASE = _args[0] if _args else "http://127.0.0.1:8000"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "assets", "screenshots", "web")  # 仓库根目录 assets/screenshots/web


LIVE_QUESTIONS = [
    "请问问小研：周末在家怎么安排一个高效又放松的学习计划？一句话",
    "请问问小研：喝咖啡的最佳时间是什么时候？一句话",
    "请问问小研：如何快速入门理财？给我一句话建议",
    "请问问小研：秋季跑步要注意什么？一句话",
]


async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=os.getenv("CHROME", "/usr/bin/google-chrome"), headless=True)
        pg = await b.new_page(viewport={"width": 430, "height": 900}, device_scale_factor=2)
        shot = lambda n: pg.screenshot(path=os.path.join(OUT, n))
        await pg.goto(BASE)
        await shot("01_login.png")
        await pg.fill("#auth-user", "demo"); await pg.fill("#auth-pass", "verabot2026")
        await pg.click("#auth-submit"); await pg.wait_for_selector(".bot-item")
        await shot("02_bot_list.png")
        await pg.click("#btn-new-bot"); await pg.wait_for_timeout(400)
        await pg.click("#tpl-row button >> nth=2"); await pg.wait_for_timeout(200)
        await shot("03_create_bot_sheet.png")
        await pg.click("#bf-cancel"); await pg.wait_for_timeout(300)
        await pg.click(".bot-item >> nth=0"); await pg.wait_for_selector(".trace")
        await pg.wait_for_timeout(500)
        await shot("04_chat_history_tools.png")
        await pg.eval_on_selector(".trace.handoff", "e => e.scrollIntoView({block:'center'})")
        await shot("05_chat_ask_bot_trace.png")
        # 输入栏「＋」= 附件占位菜单
        await pg.click("#btn-attach"); await pg.wait_for_selector("#attach-menu:not(.hidden)")
        await pg.wait_for_timeout(200); await shot("11_attach_menu.png")
        await pg.click("#msgs"); await pg.wait_for_timeout(200)
        await pg.fill("#input", random.choice(LIVE_QUESTIONS))
        await pg.press("#input", "Enter")
        await pg.wait_for_selector(".msg:last-child .trace.pending", timeout=60000)
        await shot("06_streaming_handoff_pending.png")
        await pg.wait_for_function("() => !document.querySelector('#btn-send').disabled", timeout=120000)
        await pg.wait_for_timeout(300)
        await shot("07_streaming_done.png")
        await pg.click("#btn-back"); await pg.click(".tab[data-tab=reminders] >> nth=0")
        await pg.wait_for_timeout(600); await shot("08_reminders.png")
        await pg.click("#view-reminders .tab[data-tab=quota]"); await pg.wait_for_selector(".stat")
        await pg.wait_for_timeout(300); await shot("09_quota.png")
        await b.close()

if "--no-reset" not in sys.argv:
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "backend", "scripts", "dev", "seed_demo.py"), BASE, "--reset"], check=True)
asyncio.run(main())
