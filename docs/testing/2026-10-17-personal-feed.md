# 2026-10-17 Feed 验证记录

## 最新状态（2026-10-18）

首版已实现；下文的进行中状态为实施过程快照，以本节和末尾收尾记录为准。共享草稿修复858d368新增5项专项通过，完整Swift368项通过。用户要求「不用过多验证」，停止追加界面走查、扩展回归或新复核，仅完成必要编译与交付记录。

后端和前端专项复核通过；整体复核追加的共享草稿问题已修复，修复后的外部定向复核因额度中断未完成，不标记为整体最终批准。用户手动验收仍待进行。

状态：后端复核通过；iOS 首版 89713a6 已通过原生编译，前端竞态修复 be61da2 与定向复核通过；本记录不代表用户验收。

## 隔离与基线

- 基于 main `2564282` 的独立工作区，正式数据库与 8000 端口的服务保持原状。
- 新功能迁移目标 v36，迁移、接口和工作线程测试必须使用临时数据库。
- 基线 `scheduled_task_*_test.py`：36 项通过（2026-10-17）。
- Swift Kit 基线：Swift Testing 349 项通过；现有 XCTest 同样通过（完整输出保存在本会话的 feed-baseline-swift.log）。

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

## 验证进度

后端测试、迁移、真实采集和 HTTP 状态联调已完成，详见后文。Swift Kit 最终363项通过，Intel模拟器首次编译通过；前端复核修复通过，最终重编、原生界面检查与整体复核尚在进行。

## 用户手动验收

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

Feed 26/26、定时任务36/36、资料库26/26 通过；SQL-LAYER-01/02通过。真实 v35（没有 Feed 表）→v36 及重复初始化通过。修复了旧资料库测试中固定 schema35 的过时断言，改为当前 SCHEMA_VERSION，原回填和幂等断言保留。

修复后使用实际产品采集器与 VERABOT_FEED_DOH=1：Swift20 news、Apple20 news、Mastodon20 post/video、Windows Weekly20 audio、TED58 video。无标题短帖取原文简介首段；Media RSS视频 enclosure 优先于来源默认post。Swift返回gzip已做有界解压，压缩与解压后均不超过2,000,000字节。此前0条/失败记录是修复前快照。

## 全库回归与基线比对

独立进程离线 runner 完成：64个脚本通过、3个失败、6个跳过。auth_stability_test 首轮并发失败锁账号遇到 SQLite database is locked；原基线2564282归档与当前版本独立复跑均6/6通过，保留首轮偶发锁冲突记录，未改登录实现。

group_store_test 的2个失败（旧迁移复制连接未设置Row导致v34按列名访问异常、旧断言仍要求清群删除已独立归档附件）在原基线归档原样复现。memory_m2_test 的MEM-41d/MEM-44失败也在原基线归档原样复现（均16/18）。这些测试/运行路径没有Feed改动；本轮记录为既有遗留，不宣称全库全绿，不扩大范围修改群聊/记忆行为。

Feed修复后31/31通过，stale_work_trace_slim19/19通过，独立复核已批准；音视频候选不会因额度与304丢失，每来源有发布份额。

## 隔离 HTTP / 真实后台联调（2026-10-17）

独立API为127.0.0.1:58765，独立Feed worker开启VERABOT_FEED_DOH=1，两者只使用工作区backend/data/feed-preview/verabot.db。正式8000服务和数据库保持原状。测试账号feed-preview、资讯助理Bot、显式主题与4个公开来源；没有模型密钥，未测试真实模型回答。

实际后台抓取后，GET /api/feed/items返回20条，news/post/audio/video各5条，4个来源last_success_at均有真实时间且last_error=null。验证了收藏+已读持久化、收藏列表、引用草稿包含真实URL、不感兴趣隐藏及恢复、音频源暂停隐藏和恢复、旧计划expected_version返回409。恢复后仍20条，没有因重复采集或恢复重复发布。

## iOS 共享模块

前端提交89713a6，build2026101701；完整SwiftKit359项通过，含10项Feed测试，日志task-2-swift.log已保存。覆盖蛇形/可空字段、实际认证transport与查询参数、稀疏反馈、分页去重、切换账号/筛选/取消后的迟到结果、记忆关闭请求、既有草稿保留、发现内私聊可见性，以及元数据错误不被成功列表请求遮盖。

底部发现位于第五项，原0/1/2/4标签与顺序保留，新tag5。共享ConversationVisibilityPolicy使发现内私聊可正常处理已读和匹配通知；群聊仍限定助理tab，原页面/前台/无遮挡约束保留。UI语法解析不代替App编译；Intel iPhone 17 / iOS26 x86_64 首次编译通过（183.3秒），7条警告均来自既有 MessageMarkdown/ConversationReadVisibility。独立 bundle com.verabot.feedpreview 已安装启动，使用独立后端58765；前端复核修复和最终重编尚在进行，不宣称交互验收。


## 前端复核修复（be61da2）

复核确认并复现4处失败断言：加载前打开计划表单、迟到设置读取覆盖已保存来源/计划、成功列表清掉并发反馈失败。修复后14项Feed专项与完整363项Swift Kit通过（退出0）；另为取消问Bot保留并取消任务，回调重验sheet呈现状态。独立定向复核已批准，未重复构建。

初次模拟器登录输入后App回到主屏，登录流程未计为通过。随后仅在隔离预览bundle中通过已有令牌迁移入口载入本地测试账号，进入首页与发现，实际UI确认第五项Tab、四类筛选、真实TED列表、证据和Bot归因。这不代表登录修复或正式账号验收。


## 原生预览检查（隔离账号 / be61da2）

- 最终修复版Intel增量编译通过（33.8秒，无新增诊断），独立bundle重新安装启动。此后整体复核又发现跨入口共享草稿问题，修复后需再次编译，不把本次当作最终版本。
- 发现第五Tab进入成功，真实TED列表显示已读/收藏、来源简介、Bot归因；音频筛选返回Windows Weekly及正文节选。
- 关注计划菜单正常打开，显示服务器已保存的启用状态、资讯助理、科技/科学/播客主题、记忆关闭和4个来源。只读查看，没有覆盖计划。
- 详情显示来源、发布时间、时长、原站播放链接；问Bot→选择资讯助理→打开草稿，聊天输入框出现实际TED标题/URL/引用和外部文本边界，没有点击发送。没有模型密钥，不宣称生成回答通过。
- 截图：[发现](../../assets/screenshots/ios/2026-10-17-feed/discover.jpg)、[关注计划](../../assets/screenshots/ios/2026-10-17-feed/plan.jpg)、[问Bot草稿](../../assets/screenshots/ios/2026-10-17-feed/ask-bot-draft.jpg)。用户手动验收、原站媒体播放、正式登录/真机、持续后台运行仍待验证。
- 整体复核发现同Bot两入口保留页面可能写回旧草稿；后续已由858d368修复，见收尾记录。

## 2026-10-18 收尾记录

共享草稿问题已由858d368修复：两入口每次入场读取共享草稿，引用只插入一次；加载中输入保留，未加载/失活页面不写回，延迟保存按入场代次隔离。新增5项专项及完整Swift368项通过，日志task-2-swift-draft-fix.log已归档。下文不再追加双入口原生走查或重复全量测试。

修复后的必要编译暴露ChatView大表达式的类型推断耗时错误；仅将消息视口与入场异步逻辑提取为独立属性/方法，保持原有交互和草稿逻辑。最终编译结果见后续记录。此前截图对应已运行的be61da2预览，不作为最终草稿修复的人工验收证据。

所有代码保留在personal-feed独立工作区，未合入main、未推送、未迁移正式库或替换正式服务/真机App。整体复核后的外部定向复核因额度中断未完成，按用户要求不重新追加；不宣称整体最终批准或用户验收通过。

最终结果：Intel iPhone17 / iOS26模拟器编译通过（61.7秒）；剩余6条警告来自既有ConversationReadVisibility。独立预览bundle `com.verabot.feedpreview` 已重新安装并启动，连接隔离后端58765，未再次执行界面走查。消息视口、界面配置、生命周期和入场方法只做表达式拆分，不改草稿行为；368项测试对应858d368，拆分后仅执行必要App编译。最终日志已归档为feed-evidence/feed-final-simulator-build.log。
