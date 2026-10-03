# 账号体系改造：邮箱 / 手机号登录 (Auth refactor) — 方案 v0.1 (草案，待 Boss 决定)

> 2026-10-03 (UTC+8)。只是方案，**没有改代码**。schema 版本号：MCP M2 (PR #5) 占用 v8，本方案按 **v9** 写；如果顺序变了，实施时再顺延。Web 冻结，不做 Web 界面。

## 1. 现状 (Audit)

| 项 | 现在的实现 | 位置 |
|---|---|---|
| 账号标识 | `users.username`，3–32 字符，中英文 / 数字 / `_` / `-`，`UNIQUE`，注册后不能改 | `db/schema.py`、`api/schemas.py Credentials`、`api/routers/auth.py` |
| 密码 | 6–128 字符；bcrypt (`gensalt()` 默认 cost 12) | `core/security.py` |
| 令牌 | JWT HS256，`sub`=user id、`name`=username，有效期 `VERABOT_TOKEN_TTL_HOURS` (默认 720 h = 30 天)；没有刷新令牌，也没有吊销列表 | `core/security.py`、`core/config.py` |
| 接口 | `POST /api/auth/register`、`POST /api/auth/login` (`{username,password}` → `{token,user}`)、`GET /api/me`、`PATCH /api/me` (昵称) | `api/routers/auth.py` |
| 错误 | 用户名或密码错 → 401「用户名或密码错误」(不区分用户是否存在)；重名 → 409 | 同上 |
| 限流 | **没有**。登录 / 注册可以无限次尝试；只有聊天有每日 Token 额度 (429) | — |
| users 表 | `id, username, password_hash, created_at`，后续加了 `nickname`、`avatar_updated_at`、`token_budget`、`memory_enabled` | `db/schema.py` |
| iOS | `Credentials(username,password)`；Token 存在 `UserDefaults` 的 `vb_token` (代码注释写明生产应改 Keychain)；401 时自动退出到登录页；设置页显示「用户名 demo」 | `VeraBotCore/Models.swift`、`App/AppState.swift`、`Settings/UserProfileEditor.swift` |
| 现有账号 | 本机库只有 demo (密码 verabot2026) 和测试脚本临时建的账号 | `backend/data/verabot.db` |

问题：用户名不能找回密码、不能验证是本人；没有限流，弱密码可被暴力尝试；Token 存在 UserDefaults 不够安全；30 天 Token 无法单独吊销。

## 2. 目标模型

`users` 新增列 (v9，只加列、幂等，保留 `username`)：

| 列 | 类型 | 说明 |
|---|---|---|
| `email` | TEXT NULL | 存规范化后的值 (trim + 小写)；`CREATE UNIQUE INDEX ... WHERE email IS NOT NULL` |
| `email_verified_at` | TEXT NULL | UTC ISO；NULL = 未验证 |
| `phone` | TEXT NULL | E.164 (`+8613800138000`)；部分唯一索引 |
| `phone_verified_at` | TEXT NULL | 同上 |
| `token_version` | INTEGER NOT NULL DEFAULT 0 | 写进 JWT (`tv`)；改密码 / 「退出所有设备」时 +1，旧 Token 立即失效 |
| `failed_logins` / `locked_until` | INTEGER / TEXT | 账号级登录失败计数与临时锁定 |

新表 `auth_codes (id, user_id NULL, channel 'email'|'sms', target, purpose 'verify'|'login'|'reset', code_hash, expires_at, attempts, created_at, consumed_at)`：验证码只存哈希，10 分钟过期，最多试 5 次。

`username` 保留为内部 / 兼容字段 (老客户端、demo 账号仍可用)，界面不再展示；以后新注册自动生成 (如 `u_<id>`)，不再让用户填。

## 3. 登录 / 注册流程 (分阶段)

1. **阶段 1：邮箱 + 密码** (不依赖短信供应商)
   - 注册：邮箱 + 密码 (≥ 8 位) → 建号，`email_verified_at = NULL`，发验证邮件 (6 位码)。未验证也能先用，设置页提示「邮箱未验证」。
   - 登录：一个输入框「邮箱或用户名」+ 密码；后端按是否含 `@` 查 `email` 或 `username`。
   - 忘记密码：邮箱验证码 → 设新密码 → `token_version + 1`。
2. **阶段 2：邮箱验证码登录** (免密码，可选)。
3. **阶段 3：手机号 + 短信验证码**：需要国内短信服务 (阿里云 / 腾讯云) 和签名、模板审核，费用和合规由 Boss 决定后再做。

发信：先接 SMTP (`VERABOT_SMTP_*` 环境变量，`.env.example` 写占位)；开发环境没配 SMTP 时把验证码打印到后端日志 (仅 debug)，测试用假发信器。

## 4. 演示账号 demo 的迁移

- v9 迁移只加列，demo 的 `email/phone` 为 NULL，**用户名 demo + 密码继续能登录**，数据 (Bot、记忆、MCP 授权) 不动。
- 迁移前照例备份 `backend/data/verabot.db.bak-before-v9-<时间>`。
- 登录后设置页显示「绑定邮箱」入口；绑定并验证后即可用邮箱登录。是否给 demo 预置一个邮箱，由 Boss 决定 (见 §8)。

## 5. API 变更 (向后兼容)

| 接口 | 变更 |
|---|---|
| `POST /api/auth/register` | 接受 `{email, password}` (新) 或 `{username, password}` (旧，保留)；返回不变 `{token, user}` |
| `POST /api/auth/login` | 接受 `{identifier, password}` (新) 或 `{username, password}` (旧)；401 文案改为「账号或密码错误」 |
| `POST /api/auth/email/send-code` | `{email, purpose}`；无论邮箱是否存在都返回 202 (防枚举) |
| `POST /api/auth/email/verify` | `{email, code}` → 标记已验证 (已登录) |
| `POST /api/auth/password/reset` | `{email, code, new_password}` |
| `POST /api/auth/logout-all` | `token_version + 1` |
| `GET /api/me` / `public_user` | 新增 `email`、`email_verified`、`phone` (脱敏 `+86 138****8000`)、`phone_verified`；`username` 保留 |

iOS 同步：`VeraBotCore` 新增 `LoginRequest(identifier,password)`、`User.email / emailVerified / phone / phoneVerified` (旧后端缺字段时为 nil / false)；`VeraBotAPI` 增加对应方法。**契约测试**：新增 `backend/scripts/test/auth_test.py` (AUTH-01~)，含读取 iOS `Models.swift` CodingKeys 与 `/api/me` JSON 键对照 (同 PIN-08 / MCP-CONTRACT 的做法)；Kit 增加解码测试。

## 6. iOS 界面

- 登录页：「邮箱」输入框 (`.textContentType(.emailAddress)`、`.keyboardType(.emailAddress)`)，旁边小字「也可以用用户名登录」；注册页只要邮箱 + 密码；「忘记密码？」按钮。原生控件，沿用 Theme。
- 设置 › 账号：名称下面一行从「用户名 demo」改为邮箱 (未绑定时显示「绑定邮箱」按钮，未验证显示「未验证」)；之后加手机号行。
- Token 改存 Keychain (`kSecClassGenericPassword`，`AfterFirstUnlockThisDeviceOnly`)，首次启动把 UserDefaults 里的旧 Token 迁过去并删除。

## 7. 安全

- 密码：bcrypt 保留 (cost 12)，新注册最少 8 位；拒绝常见弱密码表前 1000 项。
- 限流 (先做进程内内存版，单机够用)：登录按 IP 每分钟 10 次、按账号连续失败 5 次锁 15 分钟；发验证码按目标 60 秒 1 次、每天 10 次；超限 429 中文提示。
- 防枚举：登录统一「账号或密码错误」，发码 / 找回密码统一 202。
- 验证码：6 位数字，只存哈希，10 分钟，5 次错误作废，用后即焚。
- JWT：加 `tv` (token_version)；有效期是否从 30 天缩短，见 §8。
- 审计：登录成功 / 失败、改密、绑定写审计日志 (不写密码 / 验证码)。

## 8. 待 Boss 决定

1. 先只做 **邮箱 + 密码** (推荐)，手机号短信放到阶段 3？短信供应商选哪家？
2. 用户名要不要彻底不展示 / 不能用来登录 (推荐：保留兼容登录，界面不展示)？
3. demo 账号是否预置邮箱 (例如 Boss 指定的邮箱)，还是保持用户名登录？
4. 发信方式：SMTP 账号由谁提供 (企业邮箱 / 第三方如 SendGrid、阿里云邮件推送)？
5. Token 有效期：维持 30 天，还是 7 天 + 刷新令牌？
6. 未验证邮箱能不能使用全部功能 (推荐：可以，仅找回密码需要已验证)？

## 9. 里程碑

| 编号 | 内容 | 测试 |
|---|---|---|
| AUTH-M1 | schema v9 加列 + `auth_codes` 表；`identifier` 登录；`/api/me` 新字段；限流与锁定；契约测试 | `auth_test.py` AUTH-01~12，回归全部后端用例 |
| AUTH-M2 | 邮箱验证码 (发信抽象 + SMTP + 假发信器)、验证、找回密码、`logout-all` | AUTH-13~20 |
| AUTH-M3 | iOS：登录 / 注册 / 找回密码页、设置页邮箱行、Keychain 迁移 | Kit 解码测试；模拟器截图验收 |
| AUTH-M4 | 手机号 + 短信 (依赖 §8-1) | 假短信网关用例 |
| AUTH-M5 | (可选) 邮箱验证码免密登录、Sign in with Apple | — |

Web 冻结：不改 Web 登录页；旧的 `{username,password}` 接口保留，所以 Web 仍然能登录。
