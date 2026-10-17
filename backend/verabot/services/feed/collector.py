"""One bounded network/parser operation; subprocess contains blocking system DNS."""
import json
import sys
from . import fetcher,parser

def collect(source):
    status,headers,body,url=fetcher.fetch(source['url'],source.get('etag'),source.get('modified'))
    return dict(entries=[] if status==304 else parser.parse(body,url,source['kind']),
                etag=headers.get('etag'),modified=headers.get('last-modified'))

if __name__=='__main__':
    try:
        result=collect(json.loads(sys.stdin.read(10000)))
    except Exception as exc:
        # Public diagnostics contain no URL, body, redirect target or private source metadata.
        print(json.dumps({'error':type(exc).__name__})); sys.exit(1)
    print(json.dumps(result,ensure_ascii=False))
