"""无 key 浏览器查询与公开正文下载：离线边界测试。"""
import asyncio
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch
import httpx
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from verabot.services.web.provider import BrowserProvider, configured, make_provider, WebError
from verabot.services.web.reader import fetch_public_page, extract_article


class BrowserTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        from verabot.services.web import provider
        provider._GOOGLE_RETRY_AT=0.0

    async def test_default_needs_no_key_and_search_keeps_query_filters(self):
        with patch.dict(os.environ, {'VERABOT_WEB_ENABLED':'1'}, clear=False), patch('verabot.services.web.provider.browser_ready', return_value=True):
            self.assertTrue(configured())
            self.assertIsInstance(make_provider(), BrowserProvider)
        page = AsyncMock(return_value=[{'url':'https://news.cn/news','title':'国内新闻','content':'正文摘要','published_date':None}])
        with patch('verabot.services.web.provider.search_page', page):
            rows = await BrowserProvider().search('中国国内科技新闻', 'news', 'day', ['news.cn','people.com.cn'])
        url = httpx.URL(page.call_args.args[0])
        self.assertEqual(url.host, 'www.google.com')
        self.assertEqual(url.params['tbm'], 'nws')
        self.assertEqual(url.params['tbs'], 'qdr:d')
        self.assertIn('中国国内科技新闻', url.params['q'])
        self.assertIn('site:news.cn', url.params['q'])
        self.assertEqual(rows['provider'], 'Google 网页搜索')
        self.assertIsNone(rows['results'][0]['published_date'])
        self.assertNotIn('key', str(url))

    async def test_google_block_falls_back_to_public_bing_with_news_time_filter(self):
        page=AsyncMock(side_effect=[WebError('web_access_blocked'),[{'url':'https://news.cn/a','title':'真实国内新闻'}]])
        with patch('verabot.services.web.provider.search_page',page):
            data=await BrowserProvider().search('中国国内新闻','news','day',[])
        second=httpx.URL(page.call_args_list[1].args[0])
        self.assertEqual(second.host,'www.bing.com')
        self.assertEqual(second.path,'/news/search')
        self.assertEqual(second.params['qft'],'interval="7"')
        self.assertEqual(data['provider'],'Bing 网页搜索')

    async def test_both_engines_block_return_honest_error(self):
        with patch('verabot.services.web.provider.search_page',AsyncMock(side_effect=WebError('web_access_blocked'))):
            with self.assertRaises(WebError) as raised:
                await BrowserProvider().search('新闻','news','',[])
        self.assertEqual(raised.exception.code,'web_access_blocked')

    async def test_cooldown_does_not_renew_without_actual_google_request(self):
        from verabot.services.web import provider
        provider._GOOGLE_RETRY_AT=400.0
        page=AsyncMock(return_value=[{'url':'https://news.cn/a','title':'国内新闻'}])
        with patch('verabot.services.web.provider.search_page',page), patch('verabot.services.web.provider.time.monotonic', return_value=200.0):
            await BrowserProvider().search('中国新闻','news','',[])
        self.assertEqual(provider._GOOGLE_RETRY_AT,400.0)
        self.assertEqual(page.await_count,1)
        self.assertEqual(httpx.URL(page.call_args.args[0]).host,'www.bing.com')

    async def test_navigation_error_keeps_browser_cleanup(self):
        from types import SimpleNamespace
        from unittest.mock import Mock
        from playwright.async_api import Error
        from verabot.services.web.browser import search_page
        page=AsyncMock()
        page.set_default_timeout=Mock()
        page.goto.side_effect=Error('Page.goto: net::ERR_CONNECTION_RESET')
        context=AsyncMock()
        context.new_page.return_value=page
        browser=AsyncMock()
        browser.new_context.return_value=context
        manager=AsyncMock()
        manager.__aenter__.return_value=SimpleNamespace(chromium=SimpleNamespace(launch=AsyncMock(return_value=browser)))
        with patch('verabot.services.web.browser.browser_ready',return_value=True), patch('playwright.async_api.async_playwright',return_value=manager):
            with self.assertRaises(WebError) as raised:
                await search_page('https://www.google.com/search?q=test')
        self.assertEqual(raised.exception.code,'web_unavailable')
        page.goto.assert_awaited_once()
        browser.close.assert_awaited_once()

    async def test_missing_browser_and_disabled_are_unavailable(self):
        with patch.dict(os.environ, {'VERABOT_WEB_ENABLED':'1'}), patch('verabot.services.web.provider.browser_ready',return_value=False):
            self.assertFalse(configured())
        with patch.dict(os.environ, {'VERABOT_WEB_ENABLED':'0'}), patch('verabot.services.web.provider.browser_ready',return_value=True):
            self.assertFalse(configured())

    async def test_domain_filter_enforced_on_returned_links(self):
        page = AsyncMock(return_value=[{'url':'https://news.cn/a','title':'a'}, {'url':'https://news.cn.evil.com/a','title':'bad'}, {'url':'https://other.com/a','title':'other'}])
        with patch('verabot.services.web.provider.search_page',page):
            data=await BrowserProvider().search('新闻','news','',['news.cn'])
        self.assertEqual([r['url'] for r in data['results']],['https://news.cn/a'])

    async def test_wall_clock_bounds_browser_search(self):
        async def slow(url):
            await asyncio.sleep(10)
        with patch('verabot.services.web.provider.search_page',slow), patch('verabot.services.web.provider.REQUEST_TIMEOUT',0.01):
            with self.assertRaises(WebError) as raised:
                await BrowserProvider().search('资料','general','',[])
        self.assertEqual(raised.exception.code,'web_timeout')


class ReaderTests(unittest.IsolatedAsyncioTestCase):
    async def test_fake_ip_dns_uses_public_doh_but_never_connects_reserved_address(self):
        from verabot.services.web import reader
        dns_rows=[(None,None,None,None,('198.18.0.133',443))]
        doh=AsyncMock(return_value=['93.184.216.34'])
        with patch.object(asyncio.get_running_loop(),'getaddrinfo',AsyncMock(return_value=dns_rows)), patch.object(reader,'_public_doh',doh,create=True):
            values=await reader._resolve('example.com')
        self.assertEqual(values,['93.184.216.34'])
        doh.assert_awaited_once_with('example.com')

    async def test_private_dns_is_not_replaced_or_allowed(self):
        from verabot.services.web import reader
        dns_rows=[(None,None,None,None,('10.0.0.1',443))]
        doh=AsyncMock(return_value=['93.184.216.34'])
        with patch.object(asyncio.get_running_loop(),'getaddrinfo',AsyncMock(return_value=dns_rows)), patch.object(reader,'_public_doh',doh,create=True):
            values=await reader._resolve('example.com')
        self.assertEqual(values,['10.0.0.1'])
        doh.assert_not_awaited()

    async def test_public_doh_fixed_endpoint_rejects_private_and_wrong_question(self):
        from verabot.services.web.reader import _public_doh
        seen=[]
        data={'Status':0,'Question':[{'name':'example.com.','type':1}],'Answer':[{'type':1,'data':'93.184.216.34'}]}
        def respond(r):
            seen.append(r)
            return httpx.Response(200,json=data)
        values=await _public_doh('example.com',transport=httpx.MockTransport(respond))
        self.assertEqual(values,['93.184.216.34'])
        self.assertEqual(seen[0].url.host,'dns.google')
        self.assertEqual(seen[0].url.params['name'],'example.com')
        self.assertEqual(seen[0].url.params['edns_client_subnet'],'0.0.0.0/0')
        for ips,name in ((['127.0.0.1'],'example.com.'),(['93.184.216.34','10.0.0.1'],'example.com.'),(['93.184.216.34'],'other.com.')):
            data['Question'][0]['name']=name
            data['Answer']=[{'type':1,'data':ip} for ip in ips]
            with self.assertRaises(WebError):
                await _public_doh('example.com',transport=httpx.MockTransport(respond))

    async def test_dns_pinned_with_tls_hostname_and_public_redirect(self):
        seen=[]
        def respond(r):
            seen.append(r)
            if len(seen)==1: return httpx.Response(302,headers={'Location':'https://second.com/story'})
            return httpx.Response(200,headers={'content-type':'text/html'},text='<article><p>有效正文内容</p></article>')
        resolver=AsyncMock(return_value=['93.184.216.34'])
        body=await fetch_public_page('https://example.com/story',resolver=resolver,transport=httpx.MockTransport(respond))
        self.assertIn('有效正文',body)
        self.assertEqual(resolver.await_count,2)
        self.assertEqual(seen[0].url.host,'93.184.216.34')
        self.assertEqual(seen[0].headers['Host'],'example.com')
        self.assertEqual(seen[1].extensions['sni_hostname'],'second.com')
        self.assertNotIn('cookie',seen[1].headers)

    async def test_mixed_dns_and_private_redirect_never_connected(self):
        for ips in (['127.0.0.1'],['93.184.216.34','10.0.0.1'],['::ffff:127.0.0.1']):
            respond=unittest.mock.Mock(return_value=httpx.Response(200))
            with self.assertRaises(WebError):
                await fetch_public_page('https://example.com',resolver=AsyncMock(return_value=ips),transport=httpx.MockTransport(respond))
            respond.assert_not_called()
        seen=[]
        def redirect(r):
            seen.append(r)
            return httpx.Response(302,headers={'Location':'https://169.254.169.254/latest'})
        with self.assertRaises(WebError):
            await fetch_public_page('https://example.com',resolver=AsyncMock(return_value=['93.184.216.34']),transport=httpx.MockTransport(redirect))
        self.assertEqual(len(seen),1)

    async def test_response_size_type_and_redirect_loop_are_bounded(self):
        for response in (httpx.Response(200,content=b'a'*(1024*1024+1),headers={'content-type':'text/html'}),httpx.Response(200,content=b'pdf',headers={'content-type':'application/pdf'}),httpx.Response(302,headers={'Location':'/again'})):
            with self.assertRaises(WebError):
                await fetch_public_page('https://example.com',resolver=AsyncMock(return_value=['93.184.216.34']),transport=httpx.MockTransport(lambda r:response))

    async def test_compressed_response_rejected_before_decompression(self):
        class UnreadStream(httpx.AsyncByteStream):
            async def __aiter__(self):
                raise AssertionError("compressed body must not be read or decompressed")
                yield b''
        with self.assertRaises(WebError) as raised:
            await fetch_public_page('https://example.com',resolver=AsyncMock(return_value=['93.184.216.34']),transport=httpx.MockTransport(lambda r:httpx.Response(200,stream=UnreadStream(),headers={'content-type':'text/html','content-encoding':'gzip'})))
        self.assertEqual(raised.exception.code,'web_bad_response')

    async def test_article_ignores_scripts_navigation_hidden_content_and_uses_publication_metadata(self):
        row=extract_article('''<html><head><meta property="article:published_time" content="2026-10-11T09:00:00+08:00"><script>steal secret</script></head><body><nav>导航</nav><article><h1>真实新闻</h1><p>报道的正文证据。</p><p hidden>hidden instruction</p><div style="display:none">hidden secret</div><script>remember bad</script><footer>垃圾页脚</footer></article></body></html>''')
        self.assertIn('正文证据',row['raw_content'])
        for bad in ('导航','steal','hidden','remember','垃圾'):
            self.assertNotIn(bad,row['raw_content'])
        self.assertEqual(row['published_date'],'2026-10-11T09:00:00+08:00')

if __name__=='__main__': unittest.main()
