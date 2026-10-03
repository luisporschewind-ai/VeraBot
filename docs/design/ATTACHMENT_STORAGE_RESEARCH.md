# 聊天图片附件存储方案调研 (Attachment Storage Research)

> 状态：**调研完成，Boss 已采纳（2026-10-03，设计稿 v1.0 Q5）**；§10 修订建议已并入 [ATTACHMENTS_DESIGN.md](ATTACHMENTS_DESIGN.md) v1.0 §5.2、§5.4–§5.6、§9；未写代码。
> 调研日期：2026-10-03（Asia/Shanghai）　调研人：Sonic　基线：main `502e11e`（只读）
> 关联：[ATTACHMENTS_DESIGN.md](ATTACHMENTS_DESIGN.md) v0.1 §5.2、§5.4、§5.5；Boss 已定方向「图片存磁盘、数据库只存元数据」。
> 前提：后端 FastAPI + SQLite，单机自托管（self-hosted）在 Boss 的 Intel Mac；第一期每条消息最多 1 张图；模型 `deepseek-flash`，图片以 base64 传给模型。

## 0. 结论摘要 (TL;DR)

- **推荐：本地磁盘目录 + SQLite 元数据**，并在代码里加一层很薄的存储接口（Storage Provider 抽象），以后换成兼容 S3 的对象存储只需新增一个实现。这和 Open WebUI、LibreChat、Dify 的默认做法一致。
- **不引入新依赖**：Pillow（图片处理）、cryptography（如需加密）已在 `requirements.txt` 中；不需要 MinIO、不需要 Homebrew。
- **目录**：`data/attachments/<user_id>/<前2位>/<att_id>.jpg` + `..._thumb.jpg`；文件名只用服务器生成的随机 id。**去重只在同一用户内做**，不跨用户。
- **访问**：后端鉴权后直接返回文件（`FileResponse`），`Cache-Control: private, no-store`；**不用签名 URL**（Signed URL）。
- **一致性**：「先写临时文件 → 原子改名 → 再写数据库」；删除时「先删数据库行 → 再删文件」；启动时和每日做一次孤儿文件（orphan file）对账。
- **备份**：SQLite 用在线备份（Online Backup API）出快照，再复制 `attachments/` 目录；允许「文件多于记录」，不允许「记录指向不存在的文件」。
- **加密**：P1 不做应用层加密，依赖 macOS 文件保险箱（FileVault，全盘加密）+ 目录权限 `0700`；P2 可选用 cryptography 做逐文件加密。
- **工作量**：约 **1.5 人日**（后端存储层 1、测试 0.5），已包含在设计稿 P1 的 4 人日之内，不额外增加。

## 1. 业内产品怎么做

| 产品 | 默认存储 | 可选后端 | 访问方式 | 来源 |
| --- | --- | --- | --- | --- |
| **Open WebUI**（自托管） | 本地目录 `DATA_DIR/uploads`，元数据在数据库 | `STORAGE_PROVIDER=s3/gcs/azure`；即使用 S3 也会先在本地留一份处理用副本 | 后端鉴权后返回 | [config.py](https://github.com/open-webui/open-webui/blob/ecd48e2f/backend/open_webui/config.py)、[provider.py](https://github.com/open-webui/open-webui/blob/main/backend/open_webui/storage/provider.py)、[S3 教程](https://github.com/open-webui/docs/blob/main/docs/tutorials/maintenance/s3-storage.md) |
| **LibreChat**（自托管） | `local`，Docker 挂载 `./images`、`./uploads` | `s3`、`firebase`、`azure_blob`、`cloudfront`；可按类型分别配置（`fileStrategies`） | S3 用预签名 URL（Presigned URL），官方提示过期后图片会显示为破图，**不建议图片用 S3 直链** | [Config Structure](https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/config)、[Amazon S3](https://www.librechat.ai/docs/configuration/cdn/s3)、[Azure Blob](https://www.librechat.ai/docs/configuration/cdn/azure) |
| **Dify**（自托管） | `STORAGE_TYPE=opendal`，`OPENDAL_SCHEME=fs`，即本地 `storage` 目录 | S3、阿里云 OSS、腾讯云 COS、火山引擎 TOS 等十余种 | 后端鉴权 / 签名 | [Dify 环境变量](https://docs.dify.ai/en/self-host/deploy/configuration/environments)、[api/.env.example](https://github.com/langgenius/dify/blob/main/api/.env.example) |
| **ChatGPT**（云服务） | 云端对象存储（内部实现未公开） | — | 删除对话后 30 天内永久删除；「资料库（Library）」里的文件需单独删除 | [Chat and File Retention](https://help.openai.com/en/articles/8983778-chat-and-file-retention-policies-in-chatgpt) |
| **Claude API**（云服务） | Files API：上传一次得到 `file_id`，消息里引用 | — | 文件保留到显式删除或到期（可设 1 小时至 90 天） | [Files API](https://docs.anthropic.com/en/docs/build-with-claude/files) |

**共同模式**：文件内容和元数据分开存；单机默认本地目录；通过一个存储抽象层切换到对象存储；文件名使用系统生成的 id。云服务的共同点是「文件跟随对话删除，并有明确的保留期」。

## 2. 存储方式对比

| 维度 | A. 本地磁盘目录（推荐） | B. SQLite BLOB | C. 兼容 S3 的对象存储（MinIO 等） |
| --- | --- | --- | --- |
| 性能 | 单图约 0.3–1.5 MB，大于 100 KB 时独立文件读取更快 | SQLite 官方测试：**小于 100 KB** 时存库内更快，大于 100 KB 时文件更快 | 多一跳网络，单机无优势 |
| 数据库体积 | 不影响 | 库文件持续膨胀，备份、`VACUUM` 变慢 | 不影响 |
| 依赖 / 运维 | 无 | 无 | 需要额外运行一个服务；**MinIO 社区版 2025-10 起只提供源码，2025-12 进入维护模式，GitHub 仓库 2026-04-25 已归档** |
| 备份一致性 | 需要对账（见 §7） | 天然一致 | 需要对账 |
| 迁移上云 | 通过存储抽象平滑切换 | 需要导出 | 原生 |
| 适合 | 单机自托管 | 头像这类小图（现状） | 多实例 / 云部署 |

来源：[Internal Versus External BLOBs](https://www.sqlite.org/intern-v-extern-blob.html)、[35% Faster Than The Filesystem](https://sqlite.org/fasterthanfs.html)（只针对约 10 KB 的小 BLOB）、[MinIO Maintenance Mode](https://github.com/minio/minio/issues/21714)、[InfoQ 报道](https://www.infoq.com/news/2025/12/minio-s3-api-alternatives/)、[MinIO Releases（已归档）](https://github.com/minio/minio/releases)。

**结论**：选 A。现有头像保持 BLOB 不动（体积小，符合 SQLite 官方建议）；缩略图约 20–40 KB，理论上可以存库，但为了一致性和简单，与原图一起放磁盘。

## 3. 目录结构与命名

```
backend/data/                      # 已有 DATA_DIR（VERABOT_DATA_DIR 可覆盖），已 gitignore
└── attachments/                   # 权限 0700
    ├── tmp/                       # 上传中的临时文件，启动时清空
    └── u<user_id>/                # 按用户隔离
        └── <id 前 2 位>/           # 分桶，避免单目录文件过多
            ├── att_<随机id>.jpg
            └── att_<随机id>_thumb.jpg
```

- **id**：`att_` + 16 字节随机数的 base32（`secrets.token_bytes`），不可枚举；**不用内容哈希做文件名**，避免同一用户的不同消息共用一个文件后删除时互相影响。
- **原始文件名**：不保存（隐私），设计稿 v0.1 已定。
- **内容哈希**：`sha256` 存在元数据里，用于完整性校验和**同一用户内**的重复检测（重复上传时复用已有文件，引用计数为 2）。**不做跨用户去重**：跨用户去重会让 A 通过「上传是否秒完成」推断 B 是否有同一张图，属于已知的侧信道（side channel）风险。P1 每条消息只有 1 张图，去重收益很小，**建议 P1 只记录哈希，不做去重**，P2 再按需开启。
- **路径安全**：数据库里只存相对路径（`u12/ab/att_xxx.jpg`），读取时拼接到 `ATTACHMENTS_DIR` 后做 `resolve()`，校验仍在根目录内，防止路径穿越（Path Traversal）。

## 4. 缩略图 (Thumbnail)

- 上传时同步生成，不做懒生成：Pillow `ImageOps.exif_transpose` → `thumbnail((320, 320))` → JPEG 质量 75，约 20–40 KB。单图处理在 Intel Mac 上为百毫秒级，放在线程池（`run_in_threadpool`）里执行，不阻塞事件循环。
- 原图：长边 2048 px、JPEG 质量 85、**不写 EXIF**（设计稿 v0.1 §5.2 已定）。
- 列表 / 气泡加载 `/thumb`，点开全屏再加载 `/content`。
- 不做多档尺寸（如 WebP 多分辨率），单机 + 单客户端场景不需要。

## 5. 访问控制：签名 URL 还是后端鉴权代理

| 方式 | 优点 | 缺点 |
| --- | --- | --- |
| **后端鉴权后返回（推荐）** | 与现有 JWT 鉴权、按用户隔离、`no-store` 完全一致；撤销即时生效 | 流量经过后端（单机没有影响） |
| 签名 URL（HMAC 或 S3 预签名） | 适合 CDN 和对象存储直出 | 链接泄露期间任何人可访问；过期后图片破图（LibreChat 官方文档已指出）；本机部署没有 CDN，收益为零 |

- 实现：`GET /api/attachments/{id}/content|thumb` 先按 `id + user_id` 查库，查不到一律 404；用 Starlette `FileResponse` 返回，头部 `Cache-Control: private, no-store`、`X-Content-Type-Options: nosniff`、`Content-Type` 取库里记录的 `mime`。
- iOS 已改为独立、无磁盘缓存的 `URLSession`，图片请求带令牌，正好适用。
- **发给模型**：后端从磁盘读文件转 base64 放进请求，不暴露任何 URL；这也是因为后端在内网，模型拉不到。
- 以后上云：保留「后端代理」为默认；只有确实接入 CDN 时，才增加短时效签名 URL（例如 5 分钟）作为可选实现。

## 6. 删除与孤儿文件清理

**写入顺序（防止「记录指向不存在的文件」）**
1. 写入 `tmp/<随机>.part` → `fsync` → `os.replace` 原子改名到最终路径；
2. 再插入数据库行（`status=pending`）；
3. 第 2 步失败时立即删除第 1 步的文件。

**删除顺序（防止「文件残留无人知晓」可以接受，反之不行）**
1. 在一个事务里删除数据库行（清空对话 / 删除 Bot / 删除账号走级联）；
2. 事务提交后再删文件；删除失败只记日志，留给对账任务。

**对账任务（Reconciler）**，启动时执行一次，此后每天一次（可与提醒 R1 的后台调度器共用）：
- `pending` 超过 24 小时未绑定消息 → 删行、删文件；
- 磁盘上有、库里没有的文件，且修改时间超过 1 小时 → 删除（1 小时宽限避免误删正在上传的文件）；
- 库里有、磁盘上没有 → 记录告警日志，接口对该附件返回「图片已删除或无法加载」，不自动删行；
- 清空 `tmp/`；输出统计（删除数、释放字节数）到日志。

## 7. 备份与一致性

- **数据库**：用 Python 标准库 `sqlite3.Connection.backup()`（[文档](https://docs.python.org/3/library/sqlite3.html#sqlite3.Connection.backup)）做在线快照，不要直接复制正在写入的 `verabot.db`（WAL 模式下可能拿到不一致的文件）。
- **顺序**：先快照数据库，再复制 `attachments/` 目录。这样最坏情况是「备份里文件多于记录」，恢复后由对账任务清理；不会出现「记录指向不存在的文件」。
- **工具**：建议在 `backend/scripts/` 加一个 `backup.sh`（`sqlite3` 快照 + `rsync -a` 或 `ditto` 复制附件目录），全部为 macOS 自带命令，不需要 Homebrew。Time Machine 备份整个 `data/` 目录也可作为第二道保障。
- **恢复校验**：恢复后运行一次对账任务，并用 `sha256` 抽检。

## 8. 是否加密存储

- **P1 不做应用层加密**。理由：单机自托管，后端进程本身必须能读出明文才能发给模型，应用层加密只能防「磁盘文件被单独拷走」，而这一点 macOS 的文件保险箱（FileVault，全盘加密）已经覆盖（[Apple 说明](https://support.apple.com/guide/mac-help/protect-data-on-your-mac-with-filevault-mh11785/mac)）。
- 配套措施：`attachments/` 目录权限 `0700`、文件 `0600`；日志不打印 base64；需要确认 Boss 的 Mac 已开启 FileVault（由 Bob 在本机检查即可）。
- **P2 可选**：用已有依赖 cryptography 的 AES-GCM 做逐文件加密，密钥放在 `data/` 下或 Keychain；或者只对被判定为敏感的图片（化验单、账单）加密，与现有记忆的敏感数据加密规则保持一致。代价是无法直接用 `FileResponse`，需要解密后流式返回，并且备份必须同时带上密钥。

## 9. 以后迁移到云端的路径

1. **P1 就引入存储抽象**（约 60 行）：
   ```python
   class AttachmentStore(Protocol):
       def put(self, key: str, data: bytes, mime: str) -> None: ...
       def open(self, key: str) -> BinaryIO: ...
       def delete(self, key: str) -> None: ...
       def exists(self, key: str) -> bool: ...
   ```
   P1 只实现 `LocalStore`；数据库存 `storage_backend`（默认 `local`）+ `storage_key`（相对路径），不存绝对路径。
2. **上云时**新增 `S3Store`，可对接阿里云 OSS、腾讯云 COS 等兼容 S3 的国内对象存储（届时再加 `boto3` 依赖）。Dify 已支持这些服务，可作参考。
3. **迁移脚本**：逐条读取 `storage_backend=local` 的记录 → 上传 → 校验 `sha256` → 更新为 `s3` → 删除本地文件；可分批、可中断、可重跑。
4. 访问方式不变（后端代理）；需要时再为 CDN 增加短时效签名 URL。

## 10. 推荐方案与实现要点

| 项 | 方案 |
| --- | --- |
| 存储 | 本地磁盘 `DATA_DIR/attachments/u<user_id>/<前2位>/`，库里只存元数据 |
| 抽象 | `AttachmentStore` 协议 + `LocalStore` 实现；表中加 `storage_backend`、`storage_key` |
| 命名 | 随机 `att_` id；不存原始文件名；`sha256` 只用于校验，P1 不去重 |
| 缩略图 | 上传时同步生成 320 px JPEG |
| 访问 | 后端鉴权 + `FileResponse`，`private, no-store`，他人 404 |
| 写入 / 删除 | 临时文件 + 原子改名 → 写库；删库 → 删文件 |
| 清理 | 启动时 + 每日对账（pending 24 小时、孤儿文件 1 小时宽限、清 `tmp/`） |
| 备份 | `sqlite3` 在线快照 → 复制附件目录；附 `scripts/backup.sh` |
| 加密 | P1 依赖 FileVault + `0700/0600`；P2 可选 AES-GCM |
| 依赖 | **无新增**（Pillow、cryptography 已有） |

**对设计稿 v0.1 的修订建议**
1. §5.5 `attachments` 表：`storage_path` 改为 `storage_backend TEXT NOT NULL DEFAULT 'local'` + `storage_key TEXT NOT NULL`，`thumb_path` 改为 `thumb_key`。
2. §5.2 目录改为 `attachments/u<user_id>/<前2位>/`，并增加 `tmp/` 与权限要求。
3. §5.4 增加删除顺序、对账任务和「库里有、磁盘没有」的处理方式。
4. §9 增加测试：ATT-12 原子写入（模拟写库失败时文件被删除）、ATT-13 孤儿文件对账、ATT-14 路径穿越拒绝、ATT-15 备份恢复后一致性。
5. 每条消息图片上限：Boss 已定为 **1 张**（2026-10-03），设计稿 v0.2 统一修改。

**工作量**：约 1.5 人日（存储抽象与本地实现 0.5、写入删除与对账 0.5、备份脚本与测试 0.5），属于设计稿 P1 的后端 1.5 人日范围内，不另外增加。

## 11. 需要确认的事项

1. 是否同意 P1 不做去重、不做应用层加密。
2. Boss 的 Mac 是否已开启 FileVault（可请 Bob 检查）。
3. 备份频率和保留份数（建议每日一次、保留 7 份），以及是否只依赖 Time Machine。
