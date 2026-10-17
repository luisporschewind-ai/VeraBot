"""Extract source-provided text only. XML/HTML is data, never instructions."""
from datetime import datetime,timezone
from email.utils import parsedate_to_datetime
from html.parser import HTMLParser
from urllib.parse import urljoin
import xml.etree.ElementTree as ET
from .fetcher import validate_url,MAX_BYTES

class PlainText(HTMLParser):
    def __init__(self): super().__init__(convert_charrefs=True); self.parts=[]; self.hidden=0
    def handle_starttag(self,tag,attrs):
        if tag in ('script','style'): self.hidden+=1
        elif tag in ('p','br','div','li'): self.parts.append(' ')
    def handle_endtag(self,tag):
        if tag in ('script','style'): self.hidden=max(0,self.hidden-1)
        elif tag in ('p','div','li'): self.parts.append(' ')
    def handle_data(self,data):
        if not self.hidden: self.parts.append(data)

def text(value,limit=4000):
    cleaner=PlainText(); cleaner.feed(value or '')
    return ' '.join(''.join(cleaner.parts).split())[:limit]

def local(tag): return tag.rsplit('}',1)[-1]

def child(node,*names):
    return next((c for c in node if local(c.tag) in names),None)

def value(node,*names):
    c=child(node,*names)
    return ''.join(c.itertext()) if c is not None else ''

def date(value):
    if not value: return None
    try: d=datetime.fromisoformat(value.strip().replace('Z','+00:00'))
    except ValueError:
        try: d=parsedate_to_datetime(value)
        except (ValueError,TypeError,OverflowError): return None
    if d.tzinfo is None: d=d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc).isoformat(timespec='seconds')

def safe_url(value,base):
    if not value: return None
    try: return validate_url(urljoin(base,value.strip()))
    except ValueError: return None

def duration(raw):
    try:
        numbers=[int(x) for x in raw.split(':')]
        if not 1<=len(numbers)<=3 or any(x<0 for x in numbers): return None
        result=0
        for n in numbers: result=result*60+n
        return result if result<=604800 else None
    except (ValueError,AttributeError): return None

def parse(payload,base_url,default_kind='news'):
    if len(payload)>MAX_BYTES or b'\x00' in payload: raise ValueError('XML too large or unsupported encoding')
    lowered=payload.lower()
    if b'<!doctype' in lowered or b'<!entity' in lowered: raise ValueError('DTD/entities forbidden')
    try: root=ET.fromstring(payload)
    except ET.ParseError as e: raise ValueError('invalid XML') from e
    if local(root.tag) not in ('rss','feed','RDF'): raise ValueError('not an RSS/Atom feed')
    entries=[]
    for node in root.iter():
        if local(node.tag) not in ('item','entry'): continue
        if len(entries)>=200: break
        atom=local(node.tag)=='entry'
        link=value(node,'link')
        if atom:
            link=next((c.get('href','') for c in node if local(c.tag)=='link' and c.get('rel','alternate')=='alternate'),'')
        url=safe_url(link,base_url)
        if not url: continue
        title=text(value(node,'title'),300)
        full=child(node,'encoded','content')
        # Media RSS <media:content url=...> is media, not article body.
        if full is not None and (full.get('url') or full.tag.startswith('{http://search.yahoo.com/mrss/')): full=None
        if full is not None:
            raw=''.join(full.itertext()); basis='body'
            if list(full): raw=ET.tostring(full,encoding='unicode')
        else: raw=value(node,'description','summary'); basis='description'
        summary=text(raw)
        if not title and default_kind=='post': title=summary[:80]
        if not title: continue
        media_url=image_url=None; kind=default_kind
        for c in node.iter():
            name=local(c.tag)
            if name=='thumbnail': image_url=safe_url(c.get('url'),base_url)
            if name=='image' and c.get('href'): image_url=safe_url(c.get('href'),base_url)
            enclosure=name=='enclosure' or name=='link' and c.get('rel')=='enclosure' or name=='content' and c.get('url')
            if not enclosure: continue
            candidate=safe_url(c.get('url') or c.get('href'),base_url)
            mime=c.get('type','').lower(); medium=c.get('medium','')
            if candidate and (mime.startswith(('audio/','video/')) or medium in ('audio','video')):
                media_url=candidate; kind='video' if mime.startswith('video/') or medium=='video' else 'audio'
            elif candidate and mime.startswith('image/'): image_url=candidate
        author=value(node,'creator','author')
        entries.append(dict(kind=kind,title=title,url=url,author=text(author,200) or None,
            published_at=date(value(node,'pubDate','published','updated','date')),summary=summary,summary_basis=basis,
            image_url=image_url,media_url=media_url,duration_seconds=duration(value(node,'duration'))))
    return entries
