"""公开 HTTPS 正文：DNS 固定连接、逐跳验证、限长；不执行网页脚本。"""
import asyncio
from datetime import datetime
from html.parser import HTMLParser
import ipaddress
import json
import re
import socket
from urllib.parse import urljoin, urlsplit

import httpx
from .policy import public_url


_READ_SLOTS = asyncio.Semaphore(4)


async def _resolve(host: str) -> list[str]:
    answers = await asyncio.get_running_loop().getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    addresses=list(dict.fromkeys(row[4][0] for row in answers))
    fake_network=ipaddress.ip_network('198.18.0.0/15')
    if addresses and all(ipaddress.ip_address(ip).version==4 and ipaddress.ip_address(ip) in fake_network for ip in addresses):
        return await _public_doh(host)
    return addresses


async def _public_doh(host: str, *, transport=None) -> list[str]:
    from .provider import WebError
    # Fixed trusted resolver; never accept a model-supplied resolver URL.
    async with httpx.AsyncClient(timeout=5,transport=transport,trust_env=False,follow_redirects=False) as client:
        async with client.stream('GET','https://dns.google/resolve',params={'name':host,'type':'A','edns_client_subnet':'0.0.0.0/0'},headers={'Accept-Encoding':'identity'}) as response:
            if response.status_code!=200 or response.headers.get('content-encoding','identity').lower() not in ('','identity'):
                raise WebError('web_unavailable')
            body=bytearray()
            async for chunk in response.aiter_bytes():
                body.extend(chunk)
                if len(body)>16384: raise WebError('web_bad_response')
            try:
                data=json.loads(body)
                if data.get('Status')!=0 or data.get('TC') or not any(q.get('name','').rstrip('.').lower()==host.rstrip('.').lower() and q.get('type')==1 for q in data.get('Question',[])):
                    raise WebError('web_invalid_source')
                addresses=list(dict.fromkeys(row['data'] for row in data.get('Answer',[]) if row.get('type')==1))
                if not addresses or any(not ipaddress.ip_address(ip).is_global for ip in addresses):
                    raise WebError('web_invalid_source')
                return addresses
            except (ValueError,TypeError,AttributeError,KeyError):
                raise WebError('web_bad_response') from None


async def fetch_public_page(url: str, *, resolver=None, transport=None) -> str:
    from .provider import WebError
    resolve = resolver or _resolve
    try:
        async with asyncio.timeout(12), _READ_SLOTS, httpx.AsyncClient(transport=transport, timeout=12, trust_env=False, follow_redirects=False) as client:
            for _ in range(4):
                if not public_url(url):
                    raise WebError('web_invalid_source')
                parsed = httpx.URL(url)
                host = parsed.host.encode('idna').decode('ascii')
                addresses = await resolve(host)
                if not addresses or any(not ipaddress.ip_address(ip).is_global for ip in addresses):
                    raise WebError('web_invalid_source')
                address = next((ip for ip in addresses if ':' not in ip), addresses[0])
                # Connect to the checked IP; Host and TLS SNI retain the original hostname.
                target = parsed.copy_with(host=address)
                client.cookies.clear()
                async with client.stream('GET', target, headers={'Host': host, 'User-Agent':'VeraBot/0.1 (public page reader)', 'Accept':'text/html,text/plain', 'Accept-Encoding':'identity'}, extensions={'sni_hostname':host}) as response:
                    if response.status_code in (301,302,303,307,308):
                        location = response.headers.get('location')
                        if not location:
                            raise WebError('web_bad_response')
                        url = urljoin(url, location)
                        continue
                    if response.status_code in (401,403,429):
                        raise WebError('web_access_blocked')
                    if response.status_code != 200:
                        raise WebError('web_unavailable')
                    if response.headers.get('content-encoding','identity').lower() not in ('', 'identity'):
                        raise WebError('web_bad_response')
                    kind=response.headers.get('content-type','').lower()
                    if not any(t in kind for t in ('text/html','application/xhtml+xml','text/plain')):
                        raise WebError('web_bad_response')
                    body=bytearray()
                    async for chunk in response.aiter_bytes():
                        body.extend(chunk)
                        if len(body)>1024*1024:
                            raise WebError('web_bad_response')
                    charset=re.search(r'charset\s*=\s*["\']?([\w-]+)',kind)
                    if not charset:
                        charset=re.search(rb'charset\s*=\s*["\']?([\w-]+)',body[:8192],re.I)
                    encoding=charset.group(1) if charset else 'utf-8'
                    if isinstance(encoding,bytes): encoding=encoding.decode('ascii')
                    try: return body.decode(encoding,errors='replace')
                    except LookupError: return body.decode('utf-8',errors='replace')
            raise WebError('web_bad_response')
    except (TimeoutError,httpx.TimeoutException):
        raise WebError('web_timeout') from None
    except (httpx.HTTPError,OSError,ValueError):
        raise WebError('web_unavailable') from None


class _ArticleParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.stack=[]
        self.parts=[]
        self.published=None

    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='meta' and (attrs.get('property') or attrs.get('name','')).lower() in ('article:published_time','datepublished','pubdate','publishdate'):
            value=attrs.get('content','')[:128]
            try:
                datetime.fromisoformat(value.replace('Z','+00:00'))
                self.published=value
            except ValueError: pass
        hidden=('hidden' in attrs or attrs.get('aria-hidden')=='true' or re.search(r'display\s*:\s*none|visibility\s*:\s*hidden',attrs.get('style',''),re.I))
        skip=tag in ('script','style','noscript','nav','footer','header','form','head','svg','iframe') or hidden or bool(self.stack and self.stack[-1][1])
        article=tag=='article' or bool(self.stack and self.stack[-1][2])
        main=tag=='main' or bool(self.stack and self.stack[-1][3])
        if tag not in ('area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'):
            self.stack.append((tag,skip,article,main))

    def handle_endtag(self,tag):
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0]==tag:
                del self.stack[i:]
                break

    def handle_data(self,data):
        if self.stack and self.stack[-1][1]: return
        text=' '.join(data.split())
        if text:
            self.parts.append((text,bool(self.stack and self.stack[-1][2]),bool(self.stack and self.stack[-1][3])))


def extract_article(html: str) -> dict:
    parser=_ArticleParser()
    parser.feed(html)
    preferred=[text for text,article,main in parser.parts if article]
    if not preferred: preferred=[text for text,article,main in parser.parts if main]
    if not preferred: preferred=[text for text,article,main in parser.parts]
    return {'raw_content':'\n'.join(preferred)[:4000], 'published_date':parser.published}
