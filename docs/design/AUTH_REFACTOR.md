# 账号体系改造：邮箱 / 手机号登录 (Auth refactor) — v1.0 (已定稿，AUTH-M1 已实现)

> 2026-10-03 (UTC+8) 定稿。schema **v9**。v0.1 草案的待决定问题已由 Boss 拍板 (§1)，本文描述的是**已实现**的行为。Web 冻结，不改 Web 界面 (旧的 `{username,password}` 接口保留，Web 仍能登录)。

## 1. Boss 的决定

| # | 问题 | 决定 |
|---|---|---|
| 1 | 支持哪些方式 | **邮箱 + 密码**、**邮箱 + 验证码**、**手机号 + 密码** 现在就做。手机号 + 短信验证码**延后** (要短信供应商 + 签名模板审核)；手机号注册目前不验证。 |
| 2 | 用户名 | 数据里保留 `username` (老账号、老客户端、Web)，**界面不展示**；新注册账号自动生成内部用户名 `u_<10 位 hex>`。demo / verabot2026 继续可登录 (邮箱框里填 demo 即可)。 |
| 3 | 发信 | 可插拔：默认 `console` 后端把验证码写进后端日志 (`[DEV MAIL] ... code=123456`)；配环境变量后切到 SMTP。发件人 luisporschewind@gmail.com，**应用专用密码还没有**，所以目前仍是 console。不改 `.env`，变量见 §6。 |
| 4 | 令牌 | 访问令牌 **7 天**；刷新令牌 60 天，每次刷新轮换；iOS 透明刷新；令牌存 **Keychain**。 |
| 5 | 未验证邮箱 | **可以使用全部功能**，设置页显示「邮箱未验证」+「验证」按钮提醒。 |

## 2. 数据模型 (v9，只加列 / 新表，幂等)

`users` 新增列：

| 列 | 类型 | 说明 |
|---|---|---|
| `email` | TEXT NULL | 规范化 (trim + 小写)；部分唯一索引 `idx_users_email` (`WHERE email IS NOT NULL`) |
| `email_verified_at` | TEXT NULL | UTC ISO；NULL = 未验证。验证码登录创建的账号直接视为已验证 |
| `phone` | TEXT NULL | E.164 (`+8613800138000`)；11 位大陆手机号自动补 `+86`，`0086` 前缀转 `+86`；部分唯一索引 `idx_users_phone` |
| `token_version` | INTEGER DEFAULT 0 | 写进 JWT `tv`；「退出所有设备」+1，旧访问令牌立即失效 |
| `failed_logins` / `locked_until` | INTEGER / TEXT | 连续 5 次密码错误锁 15 分钟 |

新表：

- `auth_codes(id, email, purpose 'login'|'verify', code_hash, expires_at, attempts, created_at, consumed_at)`：6 位数字，只存 HMAC 哈希，10 分钟过期，错 5 次作废，用后即焚；同一邮箱同一用途发新码时旧码作废。
- `auth_refresh_tokens(id, user_id, token_hash UNIQUE, expires_at, created_at, revoked_at)`：只存哈希。

迁移 v8 → v9 前备份 `backend/data/verabot.db.bak-before-v9-<时间>`；老账号 (demo) 的 email / phone 为 NULL，数据 (Bot、记忆、MCP 授权) 不动。

## 3. 流程

- **邮箱 + 密码注册**：邮箱 + 密码 (≥ 8 位，≤ 128) → 建号 (未验证) → 返回会话；同时静默发一封验证码邮件 (发信失败不影响注册)。
- **登录 (密码)**：`identifier` + 密码。后端判断：含 `@` → 邮箱；`+` 开头或 ≥ 8 位数字 → 手机号；其他 → 用户名。错误统一「账号或密码错误」(不区分账号是否存在)；旧的 `{username,password}` 仍返回「用户名或密码错误」。
- **邮箱 + 验证码登录**：`send-code` → 输入 6 位码 → 登录；该邮箱还没有账号时**直接创建** (已验证，随机不可用密码)。
- **手机号 + 密码**：注册 / 登录同上，暂不发短信。
- **验证邮箱**：设置 › 账号「邮箱未验证 › 验证」→ 发码 (60 秒内刚发过就直接让用户输入上一封里的码) → 输入 → 已验证。
- **刷新**：访问令牌过期 / 失效 (401) → iOS 用刷新令牌换一对新的 → 原请求重试一次；并发的多个 401 只刷新一次。刷新令牌被拒 (过期 / 已吊销 / 复用) → 请求仍 401 → 回到登录页。
- **刷新令牌复用检测**：已轮换掉的刷新令牌再次出现 → 视为泄露，吊销该用户全部刷新令牌。
- **退出**：iOS 退出时 `POST /api/auth/logout` 吊销本机刷新令牌，删除 Keychain；`POST /api/auth/logout-all` 让所有设备失效 (token_version + 1，吊销全部刷新令牌；iOS 暂无入口)。

## 4. API

| 接口 | 请求 | 返回 / 错误 |
|---|---|---|
| `POST /api/auth/register` | `{email, password}` 或 `{phone, password}`；旧 `{username, password}` (≥ 6 位) 保留 | `AuthSession`；409 `email_taken` / `phone_taken`；422 `invalid_email` / `invalid_phone` / `weak_password` |
| `POST /api/auth/login` | `{identifier, password}`；旧 `{username, password}` | `AuthSession`；401；429 `account_locked` / `rate_limited` |
| `POST /api/auth/refresh` | `{refresh_token}` | `AuthSession` (新的一对)；401 `invalid_refresh` / `refresh_reused` / `refresh_expired` |
| `POST /api/auth/logout` | `{refresh_token}` | `{ok:true}` (令牌不存在也返回 ok) |
| `POST /api/auth/logout-all` | (需登录) | `{ok:true}` |
| `POST /api/auth/email/send-code` | `{email}` | `{ok, expires_in:600, retry_after:60}` (邮箱是否注册都一样，防枚举)；429 `code_cooldown` / `code_daily_limit` / `rate_limited`；503 `mail_failed` |
| `POST /api/auth/email/login` | `{email, code}` | `AuthSession`；400 `code_invalid` / `code_expired` / `code_exhausted` |
| `POST /api/me/email/send-verification` | (需登录) | 同 send-code；已验证时 `{ok, already_verified:true}`；400 `no_email` |
| `POST /api/me/email/verify` | `{code}` (需登录) | `User`；400 同上 |
| `GET /api/me`、`PATCH /api/me` | — | `User` (新增 `email`、`email_verified`、`phone`) |

`AuthSession` = `{token, refresh_token, expires_in, refresh_expires_in, user}`。非 401 错误的 `detail` 是 `{message, code}`；401 的 `detail` 是中文字符串。JWT 声明：`sub`、`name`、`tv`、`typ:"access"`、`exp`；刷新令牌不是 JWT，不能当访问令牌用；v8 签发的不带 `tv` 的旧令牌按 `tv=0` 继续有效。

`display_name` 兜底顺序：昵称 → 邮箱 @ 前部分 → `用户<手机后 4 位>` → 用户名。

## 5. 安全

- 密码 bcrypt (cost 12)；新账号至少 8 位。
- 限流 (进程内内存滑动窗口，单进程够用)：同一 IP 10 分钟内「注册 + 登录失败」≤ 30 次 (`VERABOT_AUTH_IP_LIMIT`)；账号连续 5 次错误锁 15 分钟；验证码同一邮箱 60 秒 1 次、每天 10 次，同一 IP 每小时 30 次。超限 429 中文提示。
- 审计 (`audit_log`)：注册、登录 (方式)、锁定、刷新令牌复用、logout-all、邮箱验证；不写密码 / 验证码。
- iOS：令牌存 Keychain (`kSecClassGenericPassword`，`AfterFirstUnlockThisDeviceOnly`，service `com.verabot.app.auth`)；首次启动把 UserDefaults 里的旧 `vb_token` 迁过去并删除 (旧令牌没有刷新令牌，到期后重新登录)。

## 6. 配置 (环境变量，写在 `.env`；`.env.example` 有占位)

| 变量 | 默认 | 说明 |
|---|---|---|
| `VERABOT_TOKEN_TTL_HOURS` | 168 | 访问令牌有效期 (7 天) |
| `VERABOT_REFRESH_TTL_DAYS` | 60 | 刷新令牌有效期 |
| `VERABOT_AUTH_CODE_TTL` | 600 | 验证码有效秒数 |
| `VERABOT_AUTH_CODE_COOLDOWN` | 60 | 同一邮箱两次发码间隔 (秒) |
| `VERABOT_AUTH_CODE_DAILY` | 10 | 同一邮箱每天最多发码次数 |
| `VERABOT_AUTH_IP_LIMIT` | 30 | 同一 IP 10 分钟内注册 + 登录失败上限 |
| `VERABOT_MAIL_BACKEND` | `console` | `console` (验证码写后端日志) / `smtp` |
| `VERABOT_SMTP_HOST` | `smtp.gmail.com` | |
| `VERABOT_SMTP_PORT` | 587 | 465 时配合 `VERABOT_SMTP_SSL=1` |
| `VERABOT_SMTP_USER` | — | 例如 luisporschewind@gmail.com |
| `VERABOT_SMTP_PASSWORD` | — | Gmail **应用专用密码** (需开两步验证后生成) |
| `VERABOT_SMTP_FROM` | 同 USER | 发件人 |
| `VERABOT_SMTP_STARTTLS` | 1 | |
| `VERABOT_SMTP_SSL` | 0 | |
| `VERABOT_SMTP_TIMEOUT` | 15 | 秒 |

启用 Gmail：在 `.env` 里加 `VERABOT_MAIL_BACKEND=smtp`、`VERABOT_SMTP_USER=luisporschewind@gmail.com`、`VERABOT_SMTP_PASSWORD=<应用专用密码>`，重启后端。

## 7. 字段映射清单 (契约测试 `auth_test.py` AUTH-15 自动核对)

| iOS (VeraBotCore) | JSON | 后端 |
|---|---|---|
| `User.email` / `emailVerified` / `phone` | `email` / `email_verified` / `phone` | `services/users.py public_user` |
| `AuthResponse.token` / `refreshToken` / `expiresIn` / `user` | `token` / `refresh_token` / `expires_in` / `user` | `services/auth.py issue_session` |
| `LoginRequest(identifier, password)` | `identifier`, `password` | `schemas.LoginIn` |
| `RegisterRequest(email?, phone?, password)` | `email`, `phone`, `password` (nil 不编码) | `schemas.RegisterIn` |
| `EmailCodeRequest(email)` | `email` | `schemas.EmailCodeSendIn` |
| `EmailCodeLoginRequest(email, code)` | `email`, `code` | `schemas.EmailCodeLoginIn` |
| `EmailVerifyRequest(code)` | `code` | `schemas.EmailVerifyIn` |
| `RefreshRequest(refreshToken)` | `refresh_token` | `schemas.RefreshIn` |
| `CodeSentResponse(ok, expiresIn, retryAfter)` | `ok`, `expires_in`, `retry_after` | `services/auth.py send_code` |
| `AuthInputRules.normalizedEmail / normalizedPhone` | — | `normalize_email / normalize_phone` (规则一致，最终以后端为准) |

旧后端 / 旧响应缺字段时：`email`、`phone`、`refreshToken`、`expiresIn` 为 nil，`emailVerified` 为 false (Kit 测试覆盖)。

## 8. iOS 界面

- 登录页：分段控件「邮箱 / 验证码 / 手机号」(系统默认样式)。邮箱页的输入框也接受用户名 (demo)；验证码页「获取验证码」按钮带 60 秒倒计时，提示「新邮箱首次登录会自动创建账号」；手机号页用数字键盘。注册入口只在邮箱 / 手机号页。保留 AppLogo 和白色转圈按钮。
- 设置 › 账号：名字下面一行显示邮箱 / 手机号 (`+86 139 0013 9000`)；老账号仍显示「用户名 demo」。邮箱未验证时多一行「邮箱未验证 · 验证」。
- `AuthSession` (VeraBotNetworking) 持有令牌，`APIClient` 的普通请求、上传、取图片、SSE 聊天都在 401 时透明刷新一次。

## 9. 里程碑

| 编号 | 内容 | 状态 |
|---|---|---|
| AUTH-M1 | v9 schema；邮箱 / 手机号 / 验证码登录；刷新令牌；限流与锁定；发信抽象 (console + SMTP)；iOS 登录页 / 设置页 / Keychain / 透明刷新；契约测试 | ✅ 2026-10-03 |
| AUTH-M2 | 忘记密码 (邮箱验证码重设，`token_version + 1`)；设置页「退出所有设备」；老账号绑定邮箱 | 待做 |
| AUTH-M3 | 手机号 + 短信验证码 (供应商待定) | 延后 |
| AUTH-M4 | (可选) Sign in with Apple | — |

## 10. 已知限制

- 限流和锁定计数在进程内存里 (`core/ratelimit.py`)，重启清零，多进程 / 多实例不共享；上线多实例前换 Redis。
- 账号锁定提示 (429「密码错误次数过多」) 会暴露该账号存在；可接受，后续可改成统一文案。
- 手机号注册不验证号码归属。
- 旧的用户名注册接口仍是 6 位最少 (兼容老客户端 / Web)。
- 还没有忘记密码；验证码登录创建的账号没有可用密码，只能继续用验证码登录。
- Web 冻结，Web 端仍是用户名 + 密码、无刷新令牌 (30 天 → 7 天后需要重新登录)。
