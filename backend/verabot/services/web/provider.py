"""无 key 搜索：真实浏览器搜索页与公开页面读取。"""
from typing import Protocol
import asyncio
import os
import time
from urllib.parse import urlencode,urlsplit,parse_qs
import base64

from .browser import browser_ready,search_page
from .policy import public_url
from .reader import fetch_public_page,extract_article

REQUEST_TIMEOUT=30
_GOOGLE_RETRY_AT=0.0

class WebError(Exception):
    def __init__(self,code:str):
        self.code=code
        super().__init__(code)

class WebProvider(Protocol):
    async def search(self,query:str,topic:str,time_range:str,domains:list[str])->dict: ...
    async def extract(self,url:str)->dict: ...

def configured()->bool:
    return os.getenv('VERABOT_WEB_ENABLED','1')=='1' and browser_ready()

def unavailable_code()->str:
    return 'web_unavailable' if os.getenv('VERABOT_WEB_ENABLED','1')!='1' else 'web_browser_unavailable'

def make_provider()->WebProvider:
    return BrowserProvider()

class BrowserProvider:
    async def search(self,query:str,topic:str,time_range:str,domains:list[str])->dict:
        if domains: query+=' ('+' OR '.join('site:'+d for d in domains)+')'
        params={'q':query,'hl':'zh-CN','pws':'0'}
        if topic=='news': params['tbm']='nws'
        if time_range: params['tbs']='qdr:'+{'day':'d','week':'w','month':'m','year':'y'}[time_range]
        global _GOOGLE_RETRY_AT
        provider='Google 网页搜索'
        try:
            async with asyncio.timeout(REQUEST_TIMEOUT):
                google_attempted=False
                try:
                    if time.monotonic() < _GOOGLE_RETRY_AT: raise WebError('web_access_blocked')
                    google_attempted=True
                    rows=await search_page('https://www.google.com/search?'+urlencode(params))
                except WebError as exc:
                    # Never solve/bypass a challenge. Use another public search page.
                    if exc.code not in ('web_access_blocked','web_timeout','web_unavailable') or time_range=='year': raise
                    if google_attempted and exc.code=='web_access_blocked': _GOOGLE_RETRY_AT=time.monotonic()+300
                    fallback={'q':query,'setlang':'zh-Hans'}
                    if time_range:
                        if topic=='news': fallback['qft']='interval="'+{'day':'7','week':'8','month':'9'}[time_range]+'"'
                        else: fallback['filters']='ex1:"'+{'day':'ez1','week':'ez2','month':'ez3'}[time_range]+'"'
                    path='/news/search' if topic=='news' else '/search'
                    rows=await search_page('https://www.bing.com'+path+'?'+urlencode(fallback))
                    provider='Bing 网页搜索'
        except TimeoutError:
            raise WebError('web_timeout') from None
        results=[]
        for row in rows:
            raw=row.get('url')
            if isinstance(raw,str):
                parsed=urlsplit(raw)
                if parsed.hostname in ('www.bing.com','cn.bing.com') and parsed.path=='/ck/a':
                    encoded=parse_qs(parsed.query).get('u',[''])[0]
                    try: raw=base64.urlsafe_b64decode(encoded[2:]+'='*((-len(encoded[2:]))%4)).decode('utf-8') if encoded.startswith('a1') else None
                    except (ValueError,UnicodeError): raw=None
            url=public_url(raw)
            if not url: continue
            host=urlsplit(url).hostname.lower().rstrip('.')
            if domains and not any(host==d or host.endswith('.'+d) for d in domains): continue
            results.append({**row,"url":url})
        return {'results':results,'provider':provider}

    async def extract(self,url:str)->dict:
        html=await fetch_public_page(url)
        return {'results':[{'url':url,**extract_article(html)}]}
