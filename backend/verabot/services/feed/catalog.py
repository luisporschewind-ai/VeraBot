"""Small editable directory. Public endpoints verified 2026-10-17; no private search."""
SOURCES=[
 dict(id='swift',name='Swift.org',url='https://www.swift.org/atom.xml',kind='news',topics=['科技','编程','Swift'],description='Swift 官方语言与开发动态。'),
 dict(id='apple-newsroom',name='Apple Newsroom',url='https://www.apple.com/newsroom/rss-feed.rss',kind='news',topics=['科技','Apple'],description='Apple 官方新闻。'),
 dict(id='mastodon',name='Mastodon',url='https://mastodon.social/@Mastodon.rss',kind='post',topics=['科技','开源','社交网络'],description='Mastodon 官方公开短帖。'),
 dict(id='windows-weekly-audio',name='Windows Weekly (Audio)',url='https://feeds.twit.tv/ww.xml',kind='audio',topics=['科技','Windows','播客'],description='TWiT Windows Weekly 音频播客（英文）。'),
 dict(id='ted-video',name='TED Talks Daily (Video)',url='https://feeds.feedburner.com/tedtalks_video',kind='video',topics=['科学','教育','演讲'],description='TED 演讲视频订阅（英文）。'),
]
# Only allowlisted public topic labels can be inferred from memory.
ALIASES={'科技':['科技','技术','technology','tech'],'编程':['编程','开发','programming','代码'],'Swift':['swift'],
 'Apple':['apple','苹果'],'开源':['开源','open source'],'社交网络':['社交网络','mastodon'],'Windows':['windows','微软'],
 '播客':['播客','podcast'],'科学':['科学','science'],'教育':['教育','education'],'演讲':['演讲','ted'],'天文学':['天文学','astronomy']}

def catalog(topics=()):
    wanted={t.casefold() for t in topics}
    result=[]
    for s in SOURCES:
        matched=any(t.casefold() in wanted for t in s['topics'])
        result.append(dict(s,reason='匹配已选择的主题' if matched else '可手动选择的公开订阅来源'))
    return sorted(result,key=lambda s:not any(t.casefold() in wanted for t in s['topics']))
