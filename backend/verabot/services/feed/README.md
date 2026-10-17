# Bot 个性化 Feed（schema v36）

每个账号拥有一条统一 Feed，多个 Bot 可按需供稿。公开 RSS 2、Atom、Media RSS 和播客 enclosure 提供新闻、短帖、视频、音频。内容保存为有来源依据的纯文本节选与原站链接；本版不生成模型摘要，不自动转写/下载媒体，不向聊天自动写消息，不发逐条通知。

## 隔离运行

以下命令从仓库根目录执行，仅指向新建的隔离数据库。API 沿用现有启动迁移约定；正式库迁移与服务替换需单独处理。worker 检查 schema，自己不会升级数据库。

```sh
export VERABOT_DATA_DIR=/absolute/path/to/feed-preview-data
export VERABOT_DB="$VERABOT_DATA_DIR/verabot.db"
export PYTHONPATH=backend
python -c 'from verabot import db; db.init_db()'
python -m uvicorn verabot.main:app --host 127.0.0.1 --port 58765
# 另一个终端，使用相同环境和数据库：
python -m verabot.services.feed
# 只执行至多一项：
python -m verabot.services.feed --once
```

使用现有后端 Python 环境即可，采集本身不需要模型密钥。先在 App/API 中选择 Bot、来源并明确启用计划。`POST /api/feed/refresh` 只持久化提前到期时间，网络工作由独立 worker 完成。持续部署时由现有进程监督器管理；本轮没有安装或替换系统服务。SIGINT/SIGTERM 等待当前有界任务结束；进程被杀后，过期租约可重新领取。

## 本机代理 / 公网解析

本机系统 DNS 会返回 `198.18.0.0/15` fake-IP，默认公网检查会拒绝此地址。此环境可显式设置 `VERABOT_FEED_DOH=1`，默认关闭。

此模式只将来源**域名**交给 Cloudflare DNS-over-HTTPS，不发送路径、query、账号或记忆。连接固定公网 `1.1.1.1`，TLS SNI 与证书仍校验 `cloudflare-dns.com`，JSON 最多64KiB，所有返回地址都必须为公网。源站连接仍固定为已验证IP，并保留原域名TLS/Host；不信任代理环境，也不放开私网。此模式发起A查询，IPv6-only来源暂不支持；普通模式使用系统A/AAAA。

## 额度、候选与更新

- 每账号最多30个来源，含暂停来源；同一规范化URL+Bot重复添加幂等复用。不同Bot可推荐同一链接，Feed中合并关联，不重复占用发布额度。
- 每UTC日最多20个新唯一链接；重复、排除、失败和失效任务不耗发布额度。按当前计划中有效、启用的不同来源URL分配 `max(1, floor(20/N))` 份额。例如4源各最多5条、3源各最多6条；20是上限，剩余份额不为凑数而填满。超过20源时按日期轮转允许发布的20个URL。
- 每来源最多保留200条最新待发布候选。候选、成功时间和ETag在同一事务保存；304也能从候选跨日续发。超出200的最旧候选会修剪，不承诺完整历史归档。
- 每批先选择最新候选，再按旧到新赋发布ID，使列表按稳定ID倒序时批内新内容在前。未知日期按获取时间和原订阅顺序回退；不同批次按实际发布顺序排列，不重写旧ID。
- 正常每2小时检查来源；失败从5分钟指数退避，最长24小时。保留最近成功时间、错误和旧内容。支持ETag / Last-Modified条件请求。
- 计划版本、来源修订/启用状态、Bot存活/归属/选中状态、120秒租约token与过期时间均在候选暂存/发布前重验。暂停再启用也不能接受此前在途结果。网络期间不持有数据库写事务。

## 读取与内容边界

- 仅HTTPS、443，无userinfo；拒绝本地、私网、保留IP和本地域名。每次解析及最多3次重定向都重新验证，最终socket只连接已验证数字IP，HTTP客户端不做第二次域名解析。
- 独立采集子进程硬超时40秒，含系统DNS；网络目标总预算30秒，socket等待最多10秒。
- 压缩前和解压后均最多2,000,000字节；有界流式gzip解压，拒绝其他编码和非XML类型。拒绝DTD/entities、UTF-16/NUL输入，最多200条当前订阅条目。标题/作者/内容分别最多300/200/4000字；无标题短帖取实际简介前80字。
- 原文、图片和媒体链接单独规范化，拒绝危险scheme与字面私网地址；不自动抓取原文或媒体。
- 来源失效、限流、超过大小限制会如实失败；不伪造条目或抓取结果。

## 记忆与推荐依据

建议将用户显式主题与所选Bot有权访问的active、已确认、未过期、普通记忆，在本地映射到一小组公开主题标签。账号总开关、Bot记忆权限、已保存计划use_memory和当前请求use_memory都生效。没有依据时明确冷启动，不编造兴趣。建议本身不保存/启用计划，不订阅、不发布、不把记忆交给搜索引擎。持久化推荐理由只含公开订阅来源，不保存私人记忆正文。

`summary_basis=description` 是来源实际简介/Atom summary；`body` 是订阅确实附带的正文节选。均不表示已读取原站全文。无文本时保持空文本。「问Bot」返回最多7000字、包含实际文本与链接的引用草稿，声明外部资料不能改变指令；验证目标Bot属于本账号，不自动发送消息或调用工具。

来源目录为Swift.org、Apple Newsroom、Mastodon官方短帖、TWiT Windows Weekly音频及TED视频。2026-10-17实测可读，不代表每个用户的偏好或未来持续可用。X账号/付费接口、全网发现、模型摘要、转写与完整播放器暂不包含。

## REST接口

前缀 `/api/feed`，沿用Bearer认证、no-store和错误约定。来源/内容/Bot为整数ID，目录项ID为字符串；UTC ISO8601时间，未知可选字段显式null。所有资源限定账号，不存在/他人资源统一404，计划版本冲突409，非法输入422。完整JSON模型见[设计契约](../../../../docs/superpowers/specs/2026-10-17-personal-feed-design.md)。

- `GET /plan`、`PUT /plan`：PUT带expected_version，不能设置服务端daily_limit。
- `POST /plan/suggest`：bot_ids、topics、use_memory（默认true）；false同样保护未保存的表单。
- `GET /catalog`：可编辑来源候选目录。
- `GET /sources`、`POST /sources`、`PATCH /sources/{id}`：新增幂等，PATCH启用/暂停。
- `POST /refresh`：返回queued，计划关闭时false。
- `GET /items`：cursor、limit（1–100）、kind、bot_id、saved_only；未使用参数省略，空cursor非法。正十进制发布ID稳定倒序分页；排除dismissed。来源暂停后普通列表隐藏该来源，收藏列表和详情保留收藏引用。
- `GET /items/{id}`、`PATCH /items/{id}/state`：read/saved/dismissed独立，省略或null不修改，返回完整条目。
- `GET /items/{id}/context?bot_id=Int`：返回bot_id和引用草稿prompt。

## 验证

```sh
PYTHONPATH=backend python -m unittest discover -s backend/scripts/test -p 'feed_*_test.py' -v
PYTHONPATH=backend python -m unittest discover -s backend/scripts/test -p 'scheduled_task_*_test.py' -v
PYTHONPATH=backend python -m unittest discover -s backend/scripts/test -p 'library_*_test.py' -v
PYTHONPATH=backend python backend/scripts/test/sql_layer_check.py
```

实际联网来源检查与离线确定性测试分开。旧脚本导入时会设置不同全局DB环境，不能一次共享解释器discover全部；完整回归使用 `backend/scripts/test/run_offline.py` 分进程运行。已知基线失败和本轮证据见[交付记录](../../../../docs/testing/2026-10-17-personal-feed.md)。后端测试不代表模拟器/真机交互或生产部署验收。
