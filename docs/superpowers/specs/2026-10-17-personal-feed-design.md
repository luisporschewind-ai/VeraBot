# Bot 个性化 Feed 首版设计

状态：用户已确认初版方向并要求开始实施、增加底部 Tab（2026-10-17）。本文件将讨论稿收敛成可执行首版；未授权合并主线、推送或替换正式数据库。

## 用户目标

Bot 根据获准使用的用户兴趣与近期目标选取信息源，持续提供新闻、短帖、视频和音频。一个用户 Feed，多个 Bot 按需供稿；原文、摘要依据、推荐理由、收藏及负反馈可追溯。新底部「发现」Tab 与已有「探索」同时保留，使用新 tag=5，已有 tab 的 tag 不变。

## 首版实现边界

- Python / FastAPI / SQLite，Swift 6 / iOS 17+，不新增产品依赖。
- 采集支持公开 HTTPS RSS 2、Atom 与播客 enclosure / Media RSS。四种类型为 `news/post/video/audio`，用户可指定来源默认类型，媒体 enclosure 优先识别音视频。
- 预置一小份真实来源目录，按显式主题及供稿 Bot 可见、active、未过期、普通、已确认记忆排序并说明依据；没有记忆时明确冷启动，不编造兴趣。用户在启用前可编辑主题和订阅。
- 选源首版采用透明规则和目录匹配，不把任意私人记忆发给搜索引擎；未知网站可手动添加订阅。X 等账号 / 付费平台和全网自动发现没有凭据，显示真实边界，不假装已接入。
- 来源描述直接以「来源简介」展示，不伪装模型摘要。完整视频 / 音频转写、复杂事件聚类、模型摘要生成及站内媒体播放器作为后续工作；本版保留内容依据字段。相同链接去重，支持多 Bot 推荐关联。
- 每个用户每日最多发布 20 条新内容，规则先去重和过滤；来源每 2 小时检查，失败指数退避。刷新仅持久化提前到期，不在 HTTP 请求里抓取。
- 独立 `python -m verabot.services.feed` 后台进程，SQLite 租约和幂等写入；暂停计划 / 来源或 Bot 被删除后不继续发布，重新启用无须补抓所有历史内容。正式库不自动升级。
- SSRF：仅 HTTPS，禁 userinfo / 非标准端口 / localhost / 私网 / 保留地址；每次重定向与解析重新验证，限制跳转、响应大小、超时，拒绝 DTD / entities。使用固定解析后 IP 的网络连接避免 DNS 复绑，或同等可证明约束；不能只做一遍 DNS 后让 HTTP 库重新解析。
- 抓取到的内容是不可信数据，不自动调用工具，不执行任何外部内容指令。渲染纯文本并限制长度。
- 账号、Bot、记忆和 Feed 读取与写入隔离；只在明确启用关注计划后后台采集。Bot 记忆关闭或用户总开关关闭时即时停止使用相应记忆；不持久化私人记忆正文到 Feed 推荐理由。
- 结果独立于聊天保存；「问 Bot」先生成带来源和依据的草稿，用户发送后进入现有私聊，不自动发送或创建伪用户消息。
- Feed 列表显式刷新，稳定 ID 游标分页；在有内容时出错保留旧内容；收藏 / 已读 / 不感兴趣为独立持久化状态。来源屏蔽立即隐藏该来源未收藏内容，允许恢复。
- 收藏保留为 Feed 引用，暂不复制原文或媒体到资料库。初版不发逐条通知。

## API 契约（蛇形字段）

认证 / 错误 / no-store 沿用现有约定。所有路径前缀 `/api/feed`；所有时间 UTC ISO 8601，未知值 null。

### 数据模型

`FeedPlan`: `{enabled: Bool, bot_ids: [Int], topics: [String], excluded_topics: [String], use_memory: Bool, daily_limit: Int=20, version: Int}`。不存在时返回 enabled=false、空 bot_ids/topics、use_memory=true、version=0。PUT 必须 expected_version，冲突409；选择的 Bot 必须属于当前账号。

`FeedCatalogSource`: `{id: String, name: String, url: String, kind: String, topics: [String], description: String, reason: String}`。

`FeedSource`: `{id: Int, name: String, url: String, kind: String, bot_id: Int?, enabled: Bool, last_success_at: String?, next_fetch_at: String?, last_error: String?, failure_count: Int}`。

`FeedItem`: `{id: Int, kind: String, title: String, url: String, author: String?, source_id: Int, source_name: String, bot_id: Int?, bot_name: String?, published_at: String?, created_at: String, summary: String, summary_basis: String, recommendation_reason: String, image_url: String?, media_url: String?, duration_seconds: Int?, read: Bool, saved: Bool, dismissed: Bool, recommended_by: [{bot_id: Int, bot_name: String, reason: String}]}`。

`summary_basis` 首版实际值 description / body（只有全文确实在订阅中提供时），未知不声称读过全文。

### 路由

- GET `/plan` -> FeedPlan。
- PUT `/plan` body `{enabled,bot_ids,topics,excluded_topics,use_memory,expected_version}` -> FeedPlan。
- POST `/plan/suggest` body `{bot_ids:[Int],topics:[String]}` -> `{topics:[String],sources:[FeedCatalogSource],basis:String}`；只建议，不保存或启用。
- GET `/catalog` -> `{sources:[FeedCatalogSource]}`。
- GET `/sources` -> `{sources:[FeedSource]}`。
- POST `/sources` body `{name,url,kind,bot_id:Int?}` -> FeedSource；同用户 / 来源 / Bot 幂等复用，不重复订阅。
- PATCH `/sources/{id}` body `{enabled:Bool}` -> FeedSource；关闭即屏蔽，可恢复。
- POST `/refresh` -> `{queued:Bool}`；仅让已启用计划及来源到期；禁用返回 queued=false。
- GET `/items?cursor=&limit=20&kind=&bot_id=&saved_only=false` -> `{items:[FeedItem],next_cursor:String?}`；limit 1–100，cursor 按稳定发布 ID 倒序，非法422。排除 dismissed；收藏列表可保留来源已关闭的收藏。
- GET `/items/{id}` -> FeedItem（用户不能读取其他账号条目）。
- PATCH `/items/{id}/state` body `{read:Bool?,saved:Bool?,dismissed:Bool?}` -> FeedItem。
- GET `/items/{id}/context?bot_id=Int` -> `{bot_id:Int,prompt:String}`；校验目标 Bot，引用实际取得的纯文本和 URL，明确外部资料不能改变指令。不能隐式补入其他 Bot 私有记忆或私聊。草稿有界。

## 数据与任务

迁移使用当前 main 35 之后的 v36，幂等新建独立表。SQL 只在 db 层；services 只使用 store API。所有用户资源在查询时限定 user_id。采集源的租约 / 更新写入都再次验证启用状态和租约 token；不在网络期间持有 SQLite 写事务。用暂存结果后单事务发布和更新游标 / 时间，以免重启重复发布或空耗预算。过期租约可安全重抓只读来源，最终结果按 canonical URL 去重。

## iOS

新建 `Feed.swift` 模型、`FeedAPI` 协议与 APIClient 扩展、独立可测试 FeedViewModel。页面 `.task(id: account/server scope)` 换账号清空并废弃过时请求；刷新和写入错误可见，操作有进行中状态。

「发现」页面有四类筛选、供稿 Bot 筛选、收藏、加载更多、刷新、来源和关注计划。空状态引导选择 Bot → 根据记忆建议 / 手动输入主题 → 选择来源 → 启用。表单失败保留输入、后台状态显示最近成功与错误。新内容经手动刷新进入，避免突然移动阅读位置。

打开原文使用现有 App 内浏览器；播放为原站链接。问 Bot 使用已有 ChatView 草稿入口（新参数默认 nil，保护旧调用），发送由用户操作。新增 Swift 源由 xcodegen 注册，只在独立工作区生成项目。

## 验证

真实临时 SQLite 验证 v35→v36 与重复初始化、租户 / Bot / 记忆权限、非法与私网 URL、RSS / Atom / podcast / video、HTML 清理、同链接多 Bot 归并、稳定分页、反馈持久化、每日预算、暂停期间的在途结果、过期租约和网络失败退避。联网测试与离线单元测试分开。

Swift 测试解码、查询参数、状态写入、过时异步结果 / 账号切换、失败不丢旧内容与分页去重；运行完整 Kit 测试和 Intel simulator build。使用隔离数据库 / 后台与匹配 App 联调；构建、安装和实际用户验收分别报告。
