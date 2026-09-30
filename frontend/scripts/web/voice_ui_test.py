"""Web 语音输入 UI 测试：Chrome 假音频设备播放中文样本 → 录音 → /api/transcribe → 文本填入输入框（不自动发送）。
另开一个未授权的浏览器验证「麦克风权限被拒绝」提示。"""
import asyncio
import os
import sys

from playwright.async_api import async_playwright

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
HERE = os.path.dirname(os.path.abspath(__file__))
WAV = os.path.join(HERE, "fixtures", "zh_sample_48k.wav")
OUT = os.path.join(HERE, "..", "..", "..", "assets", "screenshots", "web")  # 仓库根目录 assets/screenshots/web
CHROME = os.getenv("CHROME", "/usr/bin/google-chrome")


async def login_and_open_chat(pg):
    await pg.goto(BASE)
    await pg.fill("#auth-user", "demo"); await pg.fill("#auth-pass", "verabot2026")
    await pg.click("#auth-submit"); await pg.wait_for_selector(".bot-item")
    await pg.click(".bot-item >> nth=0"); await pg.wait_for_selector("#msgs .msg")


async def main():
    ok = True
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=CHROME, headless=True, args=[
            "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream",
            f"--use-file-for-fake-audio-capture={WAV}"])
        pg = await b.new_page(viewport={"width": 430, "height": 900}, device_scale_factor=2)
        await login_and_open_chat(pg)
        sent_before = await pg.locator("#msgs .msg.me").count()
        await pg.click("#btn-mic")
        await pg.wait_for_selector("#btn-mic.recording")
        await pg.wait_for_timeout(3600)
        await pg.screenshot(path=os.path.join(OUT, "10a_voice_recording.png"))
        timer = await pg.text_content("#rec-text")
        print("recording UI:", timer)
        await pg.click("#btn-mic")
        await pg.wait_for_function("() => document.querySelector('#input').value.length > 0", timeout=120000)
        text = await pg.input_value("#input")
        print("input box:", text)
        await pg.wait_for_timeout(300)
        await pg.screenshot(path=os.path.join(OUT, "10_voice_input.png"))
        sent_after = await pg.locator("#msgs .msg.me").count()
        ok &= ("三点" in text or "3点" in text) and "开会" in text
        ok &= sent_after == sent_before  # 未自动发送
        print("not auto-sent:", sent_after == sent_before)
        await b.close()

        # 权限被拒绝：不带 fake-ui 标志，headless 下权限请求会被拒绝
        b2 = await p.chromium.launch(executable_path=CHROME, headless=True,
                                     args=["--use-fake-device-for-media-stream"])
        ctx = await b2.new_context(viewport={"width": 430, "height": 900}, device_scale_factor=2)
        pg2 = await ctx.new_page()
        await login_and_open_chat(pg2)
        await pg2.click("#btn-mic")
        await pg2.wait_for_selector("#toast:not(.hidden)", timeout=15000)
        toast = await pg2.text_content("#toast")
        print("denied toast:", toast)
        await pg2.screenshot(path=os.path.join(OUT, "10b_voice_permission_denied.png"))
        ok &= "权限" in toast or "麦克风" in toast
        await b2.close()
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)

asyncio.run(main())
