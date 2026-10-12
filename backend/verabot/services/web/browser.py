"""匿名 Chromium 搜索会话；仅公开搜索域名，不访问结果站点或个人配置。"""
import asyncio
import importlib.util
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

SEARCH_HOSTS = frozenset(('www.google.com','google.com','consent.google.com','www.gstatic.com','ssl.gstatic.com','fonts.gstatic.com','www.bing.com','cn.bing.com','r.bing.com','th.bing.com'))
_SLOTS=asyncio.Semaphore(2)


def browser_ready() -> bool:
    spec=importlib.util.find_spec('playwright')
    if not spec or not spec.origin: return False
    root=Path(spec.origin).parent
    try:
        browsers=json.loads((root/'driver/package/browsers.json').read_text())['browsers']
        revision=next(b['revision'] for b in browsers if b['name']=='chromium')
    except (OSError,ValueError,KeyError,StopIteration): return False
    base=os.getenv('PLAYWRIGHT_BROWSERS_PATH')
    if base=='0': base=str(root/'driver/package/.local-browsers')
    if not base:
        base=str(Path.home()/('Library/Caches/ms-playwright' if sys.platform=='darwin' else '.cache/ms-playwright'))
    folder=Path(base)/('chromium_headless_shell-'+revision)
    return any(path.is_file() for pattern in ('*/chrome-headless-shell', '*/chrome-headless-shell.exe', '*/headless_shell') for path in folder.glob(pattern))


def allowed_search_url(url: str) -> bool:
    try:
        p=urlsplit(url)
        return p.scheme=='https' and p.hostname in SEARCH_HOSTS and p.port in (None,443) and not p.username and not p.password
    except ValueError: return False


async def search_page(url: str) -> list[dict]:
    from .provider import WebError
    if not browser_ready(): raise WebError('web_browser_unavailable')
    from playwright.async_api import async_playwright, Error as BrowserError, TimeoutError as BrowserTimeout
    browser=None
    try:
        async with _SLOTS, async_playwright() as engine:
            browser=await engine.chromium.launch(headless=True, chromium_sandbox=True, timeout=8000)
            try:
                context=await browser.new_context(locale='zh-CN',service_workers='block',accept_downloads=False)
                async def route(request):
                    if allowed_search_url(request.request.url): await request.continue_()
                    else: await request.abort()
                await context.route('**/*',route)
                await context.route_web_socket('**/*',lambda socket: socket.close())
                page=await context.new_page()
                page.set_default_timeout(8000)
                try:
                    host=urlsplit(url).hostname
                    response=await page.goto(url,wait_until='domcontentloaded',timeout=2000 if host in ('www.google.com','google.com') else 10000)
                except BrowserTimeout:
                    raise
                except BrowserError:
                    raise WebError('web_unavailable') from None
                if response and response.status in (403,429): raise WebError('web_access_blocked')
                if '/sorry/' in page.url or urlsplit(page.url).hostname=='consent.google.com': raise WebError('web_access_blocked')
                if urlsplit(url).hostname in ('www.bing.com','cn.bing.com'):
                    await page.wait_for_function("document.querySelector('#b_results, #algocore, #news') || document.querySelector('#b_captcha')")
                    if await page.locator('#b_captcha').count(): raise WebError('web_access_blocked')
                    return await page.evaluate("""() => [...document.querySelectorAll('#news a.title, #news a.news_fbwcard, #b_results li.b_algo h2 a')].slice(0,20).map(a=>{const card=a.closest('.news-card, .b_algo'); const block=a.matches('.news_fbwcard') ? a : card || a.parentElement; const title=a.querySelector('h2,h3,.title')?.innerText || a.closest('h2,h3')?.innerText || a.textContent.trim() || card?.innerText.split('\\n').filter(Boolean)[0] || block.innerText.split('\\n').filter(Boolean)[0]; return {url:a.href,title,content:block.innerText.slice(0,1000),published_date:null}})""")
                await page.wait_for_function("document.querySelector('#rso') || document.querySelector('form[action*=sorry]') || document.querySelector('#recaptcha') || document.querySelector('#topstuff')")
                if await page.locator('form[action*=sorry], #recaptcha').count(): raise WebError('web_access_blocked')
                if await page.locator('#rso').count()==0: return []
                return await page.evaluate('''() => [...document.querySelectorAll('#rso a[href]')].flatMap(a => {
                    const heading=a.querySelector('h3, [role="heading"]');
                    if (!heading && !a.matches('[jsname="YKoRaf"]')) return [];
                    const lines=a.innerText.split('\\n').map(s=>s.trim()).filter(Boolean);
                    const title=heading?.innerText || lines[1] || lines[0];
                    const block=a.matches('[jsname="YKoRaf"]') ? a : a.closest('div.MjjYud') || a.parentElement;
                    return [{url:a.href,title,content:block.innerText.slice(0,1000),published_date:null}];
                }).slice(0,20)''')
            finally:
                await browser.close()
    except BrowserTimeout:
        raise WebError('web_timeout') from None
    except BrowserError:
        raise WebError('web_browser_unavailable') from None
