"""Bounded HTTPS fetch with validated DNS and an actual fixed-IP TLS connection.

No proxy, cookie jar, environment trust, automatic redirects or secondary DNS lookup.
TLS SNI/certificate validation and HTTP Host still use the original hostname.
"""
import http.client
import json
import os
import ipaddress
import socket
import ssl
import time
import zlib
from urllib.parse import urlsplit, urlunsplit, urljoin, urlencode

MAX_BYTES=2_000_000
MAX_SECONDS=30
MAX_REDIRECTS=3

def public_ip(value):
    address=ipaddress.ip_address(value)
    return address.is_global and not (address.is_multicast or address.is_reserved or address.is_unspecified or address.is_loopback or address.is_link_local)

def validate_url(url):
    if not isinstance(url,str) or len(url)>2048 or any(ord(c)<33 or ord(c)==127 for c in url) or '\\' in url:
        raise ValueError('invalid URL')
    try:
        p=urlsplit(url)
        host=(p.hostname or '').rstrip('.').encode('idna').decode('ascii').lower()
        port=p.port
    except (ValueError,UnicodeError) as e: raise ValueError('invalid URL') from e
    if p.scheme!='https' or p.username is not None or p.password is not None or port not in (None,443) or not host:
        raise ValueError('public HTTPS URL required')
    if '%' in host or host=='localhost' or host.endswith(('.localhost','.local','.internal','.test','.invalid')) or '.' not in host and ':' not in host:
        raise ValueError('non-public hostname')
    try: ipaddress.ip_address(host)
    except ValueError: pass
    else:
        if not public_ip(host): raise ValueError('non-public address')
    netloc='['+host+']' if ':' in host else host
    return urlunsplit(('https',netloc,p.path or '/',p.query,''))

def resolve(url):
    url=validate_url(url); host=urlsplit(url).hostname
    # System DNS may block; worker wraps the complete operation in a hard subprocess deadline.
    if os.getenv('VERABOT_FEED_DOH')=='1':
        # Fixed public bootstrap, verified Cloudflare SNI/certificate, hostname only.
        target='https://cloudflare-dns.com/dns-query?'+urlencode({'name':host,'type':'A'})
        status,_,body=request_ip(target,'1.1.1.1',{'Accept':'application/dns-json','Accept-Encoding':'identity'},time.monotonic()+8)
        if status!=200 or len(body)>65536: raise ValueError('DoH resolution failed')
        try:
            answer=json.loads(body)
            if answer.get('Status')!=0: raise ValueError('DoH resolution failed')
            addresses=[a['data'] for a in answer.get('Answer',[]) if a.get('type') in (1,28)]
        except (TypeError,KeyError,json.JSONDecodeError) as e: raise ValueError('invalid DoH response') from e
        if not addresses or any(not public_ip(a) for a in addresses): raise ValueError('non-public DoH answer')
        return url,addresses[0]
    answers=socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)
    addresses=list(dict.fromkeys(r[4][0] for r in answers))
    if not addresses or any(not public_ip(a) for a in addresses): raise ValueError('non-public DNS answer')
    return url,addresses[0]

class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def __init__(self,host,ip,timeout):
        super().__init__(host,443,timeout=timeout,context=ssl.create_default_context())
        self.ip=ip; self.transport=None
    def connect(self):
        family=socket.AF_INET6 if ':' in self.ip else socket.AF_INET
        raw=socket.socket(family,socket.SOCK_STREAM)
        raw.settimeout(self.timeout)
        try:
            raw.connect((self.ip,443))
            self.sock=self._context.wrap_socket(raw,server_hostname=self.host)
            self.transport=self.sock
        except BaseException:
            raw.close(); raise

def request_ip(url,ip,headers,deadline):
    p=urlsplit(url)
    max_bytes=65536 if headers.get('Accept')=='application/dns-json' else MAX_BYTES
    connection=PinnedHTTPSConnection(p.hostname,ip,min(10,max(.1,deadline-time.monotonic())))
    try:
        connection.request('GET',urlunsplit(('','',p.path or '/',p.query,'')),headers=headers)
        response=connection.getresponse()
        result_headers={k.lower():v for k,v in response.getheaders()}
        if response.status in (301,302,303,307,308,304): return response.status,result_headers,b''
        if response.status!=200: raise ValueError('source HTTP status '+str(response.status))
        encoding=result_headers.get('content-encoding','identity').lower()
        if encoding not in ('identity','gzip'): raise ValueError('unsupported content encoding')
        decoder=zlib.decompressobj(16+zlib.MAX_WBITS) if encoding=='gzip' else None
        length=result_headers.get('content-length')
        if length and int(length)>max_bytes: raise ValueError('source too large')
        content_type=result_headers.get('content-type','').split(';')[0].strip().lower()
        if content_type and content_type not in ('application/rss+xml','application/atom+xml','application/xml','text/xml','application/rdf+xml','application/octet-stream',*(['application/dns-json','application/json'] if max_bytes==65536 else [])):
            raise ValueError('source is not XML')
        chunks=[]; size=0; wire_size=0
        while True:
            remaining=deadline-time.monotonic()
            if remaining<=0: raise TimeoutError('source deadline exceeded')
            connection.transport.settimeout(min(10,remaining))
            block=response.read1(min(65536,max_bytes-size+1))
            if not block: break
            wire_size+=len(block)
            if wire_size>max_bytes: raise ValueError('compressed source too large')
            if decoder: block=decoder.decompress(block,max_bytes-size+1)
            size+=len(block)
            if size>max_bytes or decoder and decoder.unconsumed_tail: raise ValueError('source too large')
            chunks.append(block)
        if decoder and (not decoder.eof or decoder.unused_data): raise ValueError('invalid gzip stream')
        return response.status,result_headers,b''.join(chunks)
    finally: connection.close()

def fetch(url,etag=None,modified=None):
    deadline=time.monotonic()+MAX_SECONDS
    headers={'User-Agent':'VeraBot-Feed/1.0','Accept':'application/rss+xml, application/atom+xml, application/xml, text/xml','Accept-Encoding':'identity'}
    for key,value in [('If-None-Match',etag),('If-Modified-Since',modified)]:
        if value and len(value)<=1024 and '\r' not in value and '\n' not in value: headers[key]=value
    origin=urlsplit(validate_url(url)).netloc
    for redirect in range(MAX_REDIRECTS+1):
        url,ip=resolve(url)
        if time.monotonic()>=deadline: raise TimeoutError('source deadline exceeded')
        status,returned,body=request_ip(url,ip,headers,deadline)
        if status not in (301,302,303,307,308): return status,returned,body,url
        if redirect==MAX_REDIRECTS: raise ValueError('too many redirects')
        location=returned.get('location')
        if not location: raise ValueError('redirect without location')
        url=validate_url(urljoin(url,location))
        if urlsplit(url).netloc!=origin:
            headers.pop('If-None-Match',None); headers.pop('If-Modified-Since',None)
    raise ValueError('redirect failed')
