# Bot 联网与实时查询设计

用户已确认：通用查询覆盖新闻、资料、天气；2026-10-11 明确要求规划任务并开始执行。

## 目标与范围
复用后端工具路由、Bot 白名单、SSE 调用记录与 iOS 原生界面。第一批交付 web_search、web_read_result、真实来源卡片、天气时效。仅用户直接私聊可用；群聊与委派不开放联网。专项 API、定期监控与推送为后续阶段。

## 新闻查询优先级
2026-10-11 用户明确：首选国内新闻，其次国际新闻。通过模型查询策略实现：未指定地区时首次中文查询明确中国国内事件；综合新闻或国内结果不足时，第二次查询国际新闻；综合回答国内在前、国际在后。用户指定地区/来源优先。不默认限制固定媒体名单，也不把中文报道等同国内事件。该策略不承诺供应商的国内收录覆盖；真实验收优先检查国内新闻。

## 数据与接口
web_search(query: str, time_range: str = "", topic: str = "general", domains: list[str] | None = None, refresh: bool = False) -> dict。
支持 topic general/news，time_range 空/day/week/month/year，查询 1–400 字，域名最多 5 个。
web_read_result(query_id: str, result_id: str) -> dict；仅可读取当前 turn 当前 user/bot 搜索返回的结果。不接受任意 URL。
来源：query_id、result_id、title、url、publisher、published_at（允许 null）、queried_at、fetched_at、cache_hit、content、citation_number。搜索最多 5 个来源，摘要每条 500 字；正文最多 4000 字。发布与查询时间不能混淆。
返回数据保存在已有 message.traces，随消息读取与删除，不新增搜索索引或长期记忆。模型消息以完整 JSON 的不可信内容封装发送，禁止截断成无效 JSON；UI 来源直接使用工具结果，不由模型生成。

## 搜索与正文读取（用户修订：无需搜索 key）
用户明确要求像普通用户搜索网页一样查询，替换此前 Tavily 方案。定义 WebProvider，默认 BrowserProvider 使用 Playwright Chromium 的独立匿名上下文打开 Google 公开网页/新闻搜索。不会读取用户浏览器配置、账号、Cookie 或历史。搜索页网络仅允许固定搜索/静态资源域名，阻止任意结果页面导航、WebSocket与ServiceWorker。Google访问验证或网络失败时备用公开Bing搜索；不绕过验证码。Google验证冷却5分钟且不因备用查询续期；Bing不支持year备用，保留明确原错误。

正文使用独立公开HTTPS下载器，仅接受本轮结果；全量DNS地址均须公开，固定连接IP，TLS SNI/Host保留原域名，逐跳重新验证，最多4次响应。响应最大1MiB，读取前拒绝非identity压缩；正文4000字，跳过脚本、隐藏与导航内容，不执行文章脚本。正文全局并发4，浏览器搜索并发2。

无需任何搜索服务凭据。VERABOT_WEB_ENABLED默认1，0关闭。部署安装精确版本Playwright与Chromium，不在查询时下载。缺浏览器返回web_browser_unavailable，网站验证/限制返回web_access_blocked，不把环境问题说成要配置搜索key。真实环境的可达性、新闻时效、模型引用与原生UI验收仍须实测。

## 预算、缓存与隐私
每 turn 搜索最多 2 次、读取最多 3 次；整轮联网累计墙钟预算 45 秒；单次搜索最多30秒，正文下载12秒；账户 UTC 每日外部请求上限默认 50，可配置为 0 关闭。请求预先以 BEGIN IMMEDIATE 在 audit_log 原子预约，失败不返还；跨 worker/重启继续生效。预算仅限搜索服务，非模型 token 账单。
搜索缓存 5 分钟，进程内最多 128 条，按 user/bot、query、topic、time_range、domains 隔离。新闻、带时间范围、refresh=true 以及用户明确重新查询/最新/今天/现在的请求绕过缓存。正文只在当前 turn 内复用。每日请求额度指实际外部尝试；缓存无需消耗。
工具开关默认关闭；两项读取工具在 Bot 的工具权限中显式开启。工具说明展示必要查询内容会发送到公开搜索引擎，结果会交给模型。不会由后端自动发送整段会话、记忆或附件；模型生成的查询仍是外发内容，用户应可在调用记录查看。
外部内容视为不可信，触发本轮 taint；不能据此外发/委派，提醒与记忆写操作被阻止，MCP 写操作继续走已有冻结参数确认卡片。

## iOS 与天气
沿用工具权限页面与 Bot 状态，不新增独立联网模式。调用行显示“联网查询/读取资料”，来源列表显示标题、来源、发布时间、查询时间、缓存标记，链接只允许公开 HTTP(S)（后端网页来源限定 HTTPS）。历史 ToolTrace 同样可解码，无效来源不显示链接。
天气不重写业务逻辑；补 queried_at/fetched_at/cache_hit、timezone、数据时间与来源链接，保留现有字段与 10 分钟缓存。当前 Open-Meteo 数据来自模型，不标为气象站实测。

## 验收
未授权、委派、不可用配置、非法参数、伪造结果 ID 与额度耗尽均零外部调用；时效查询绕过缓存；两个账户/两个 Bot 隔离；超时与无结果明确；原子并发预约不超限；恶意标记完整封装且写操作拦截；消息落库后来源恢复；旧 trace 兼容；天气主/备源时间元数据一致；Swift 全套测试及模拟器编译安装启动。真实新闻质量、服务费用、真实模型引用准确性与人工 UI 验收分别记录。
