# 2026-10-17 Feed 验证记录

状态：后端与前端实现已就绪；自动化与隔离联调通过；ChatView 编译拆分与 SSRF 加固已合入本工作区。本记录不代表 Boss 验收。未迁正式库、未起正式 feed worker。

## 隔离与基线

- 基于 main `2564282` 的独立工作区，正式数据库与 8000 端口的服务保持原状。
- 新功能迁移目标 v36，迁移、接口和工作线程测试必须使用临时数据库。
- 基线 `scheduled_task_*_test.py`：36 项通过（2026-10-17）。
- Swift Kit 基线：此前完整套件通过（含 Feed / 草稿专项）；本轮新增草稿账号切换用例，完整 `swift test` / `xcodebuild` 由控制方执行。

## 真实来源探测

2026-10-17 在本机直接读取并解析 XML，以下是探测快照，不代表未来持续可用或所有来源都适合每位用户：

- [Swift.org](https://www.swift.org/atom.xml)：HTTP 200，20 个 entry，607802 字节。
- [Apple Newsroom](https://www.apple.com/newsroom/rss-feed.rss)：HTTP 200，20 个 item，18817 字节。
- [GitHub Blog](https://github.blog/feed/)：HTTP 200，10 个 item，1526027 字节。
- [Mastodon](https://mastodon.social/@Mastodon.rss)：HTTP 200，20 个 item，30485 字节；作为公开短帖的实际来源。
- [Windows Weekly Audio](https://feeds.twit.tv/ww.xml)：HTTP 200，20 个 audio/mpeg enclosure，312295 字节。
- [Windows Weekly Video](https://feeds.twit.tv/ww_video_hd.xml)：HTTP 200，20 个 video/mp4 enclosure，311887 字节。
- [TED Talks Daily SD video](https://feeds.feedburner.com/tedtalks_video)：HTTP 200，58 个 video/mp4 enclosure，143958 字节。

候选排除或降级：The Daily 的某订阅超过 20MB，不适合作为默认有界采集源；测试的 Google Developers YouTube RSS 地址返回404；NASA 的候选订阅不含音频 enclosure，不能当作已支持音频的证据。

## 自动化测试（本轮）

| 套件 | 结果 | 说明 |
| --- | --- | --- |
| `feed_*_test.py` | **32/32 通过** | 含计划/租约/在途暂停、记忆开关、SSRF（含 `127.1` / 映射 IPv6 / NAT64）、解析与 gzip 有界 |
| Swift Kit / Intel `xcodebuild` | **待控制方执行** | 本轮按要求未跑 git / xcodebuild / swift test |
| 正式库迁移 / 正式 worker | **未做** | 见下方部署待办 |

## 用户手动验收（待 Boss）

1. 底部「发现」可进入，原有助理、提醒、游乐场、探索保持可用。
2. 选择供稿 Bot，根据允许使用的记忆建议主题，修改兴趣和来源后启用。
3. 等待采集，四类筛选、来源时间、推荐理由与内容依据正确；无数据时不出现假内容。
4. 原文/播放跳原站，收藏、已读、不感兴趣和来源暂停在重进后保持。
5. 问 Bot 草稿含真实引用，需要用户发送，原有未发送草稿不会被覆盖。
6. 暂停或换账号后不出现不属于当前权限的数据；断网/来源失败保留可读内容并提示原因。

安装、启动、自动测试和来源读取不等同于上述用户交互验收通过。

## 本机 DNS 兼容问题

首次通过产品采集器读取四类来源均被公网检查拒绝：系统将 www.apple.com 解析为198.18.0.47。已确认固定公网解析器、保留原始 TLS 主机名的请求可获得真实公网地址（Cloudflare1.1.1.1 / Google8.8.8.8 实测返回200）。实现会保留私网/保留地址拦截，增加显式公网解析模式，随后重跑实际采集；此前 httpx 的可读取结果不算产品采集器已通过。

## 后端 Task 1

Feed 单测现 32/32、定时任务36/36、资料库26/26 曾通过；SQL-LAYER-01/02通过。真实 v35（没有 Feed 表）→v36 及重复初始化通过。

修复后使用实际产品采集器与 VERABOT_FEED_DOH=1：Swift20 news、Apple20 news、Mastodon20 post/video、Windows Weekly20 audio、TED58 video。无标题短帖取原文简介首段；Media RSS视频 enclosure 优先于来源默认post。Swift返回gzip已做有界解压，压缩与解压后均不超过2,000,000字节。

## 全库回归与基线比对

独立进程离线 runner 曾完成：64个脚本通过、3个失败、6个跳过。auth_stability_test 首轮并发失败锁账号遇到 SQLite database is locked；原基线2564282归档与当前版本独立复跑均6/6通过。group_store_test / memory_m2_test 失败在原基线归档复现，本轮不扩大修改。不能称全库全绿。

## 隔离 HTTP / 真实后台联调（2026-10-17）

独立API为127.0.0.1:58765，独立Feed worker开启VERABOT_FEED_DOH=1，两者只使用工作区backend/data/feed-preview/verabot.db。正式8000服务和数据库保持原状。测试账号feed-preview、资讯助理Bot、显式主题与4个公开来源；没有模型密钥，未测试真实模型回答。

实际后台抓取后，GET /api/feed/items返回20条，news/post/audio/video各5条，4个来源last_success_at均有真实时间且last_error=null。验证了收藏+已读持久化、收藏列表、引用草稿包含真实URL、不感兴趣隐藏及恢复、音频源暂停隐藏和恢复、旧计划expected_version返回409。恢复后仍20条，没有因重复采集或恢复重复发布。

## iOS

前端含发现 Tab（tag=5）、计划/来源、阅读与反馈、问 Bot 草稿；共享草稿跨入口修复见 `858d368`。账号/服务器切换由 `FeedViewModel.configure` 与 `.task(id:)` / `sessionGeneration` 丢弃在途结果与草稿。ChatView body 已拆分为 `presentedChat` / `chatShell` / `messageScroll` 等，以消除类型检查超时。

截图：[发现](../../assets/screenshots/ios/2026-10-17-feed/discover.jpg)、[关注计划](../../assets/screenshots/ios/2026-10-17-feed/plan.jpg)、[问Bot草稿](../../assets/screenshots/ios/2026-10-17-feed/ask-bot-draft.jpg)。

## 本版未接入

- 凭据平台（X 等）、全网自动发现。
- 音视频自动转写、模型摘要、站内播放器。
- 正式环境 v36 迁移与 feed worker 常驻（见下）。

## 正式环境部署待办（未执行）

1. **备份**正式 `backend/data/verabot.db`（及惯用备份命名）。
2. 升级 schema 至 **v36**（仅在确认备份后）。
3. 新开 screen 运行：`python -m verabot.services.feed`（类比 vbworker/vbowned/vbscheduled），日志写入 `data/feed-worker.log`；本机 DNS 异常时可设 `VERABOT_FEED_DOH=1`。
4. 重启后端 API 进程以加载 Feed 路由。

## 终轮复核摘要

| 项 | 严重度 | 处理 |
| --- | --- | --- |
| `validate_url` 放行 `127.1` / `0x7f.0.0.1` / `0177.0.0.1` 等歧义数字主机 | 高（SSRF 面） | **已修**，单测覆盖 |
| IPv4-mapped / 6to4 / NAT64 嵌入私网 | 中（防御纵深） | **已加固** `public_ip` |
| 记忆总开关 / Bot scope / 过期·敏感·未确认 | — | 已有实现与测试；计划 `use_memory=false` 拦截补测 |
| 在途暂停/删除/租约过期丢弃结果 | — | 已有实现与测试，无新缺陷 |
| iOS 账号切换丢弃列表/反馈/草稿 | — | 已有实现与测试；补草稿 leave 用例 |
| ChatView 类型检查超时 | 构建阻断 | **已拆分** body（待重编确认） |
