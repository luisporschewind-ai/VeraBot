# 交付与打包 (Delivery) — v0.1.0

## 1. 交付物

| 项目 | 交付物 | 接收方需要 |
|---|---|---|
| 后端 | `dist/VeraBot-backend-v0.1.0.zip` (+ `.sha256`) | macOS / Linux、网络 (首次安装依赖)、DeepSeek API Key |
| iOS | 仓库中的 `frontend/ios/` (Xcode 工程 + `Packages/VeraBotKit`) | macOS + Xcode 26；真机需要 Apple 开发者 Team 签名 |
| Web | `frontend/web/` 三个静态文件 | 放在后端旁边 (`../frontend/web`) 或设置 `VERABOT_WEB_DIR` |

## 2. 打包后端

```bash
scripts/package_backend.sh      # → dist/VeraBot-backend-v0.1.0.zip 和 .sha256
```

- 版本号取自 `backend/verabot/__init__.py`。
- 包含：`LICENSE` (MIT，取自仓库根目录)、`verabot/`、`scripts/`、`pyproject.toml`、`uv.lock`、`requirements*.txt`、`.python-version`、`.env.example`、`start.command` / `start.sh` / `stop.sh` (保留可执行权限)、`Dockerfile`、`docker-compose.yml`、`README.md`、空的 `data/`。
- 排除：`.venv/`、`.env`、`*.db`、`*.log`、`*.pid`、`.jwt_secret`、`__pycache__`、测试结果、本地模型。
- zip 只包含后端 (不含 Web)，此时 `/` 返回 API 信息 JSON；需要 Web 时把 `frontend/web` 放到解压目录旁边，或设置 `VERABOT_WEB_DIR`。

## 3. 接收方使用

```bash
unzip VeraBot-backend-v0.1.0.zip && cd VeraBot-backend-v0.1.0
./start.sh              # 或 Finder 双击 start.command；按提示输入 DeepSeek Key
```

首次运行：安装 uv (如缺失) → 安装 Python 3.12 → `uv sync --frozen` → 创建 `.env` → 初始化 `data/verabot.db` → 启动 :8000。国内网络自动回退清华 tuna 镜像 (PyPI) 和 npmmirror (Python)。
macOS 从网上下载的 zip 可能带隔离属性，双击 `start.command` 被拦截时：右键 → 打开，或 `xattr -dr com.apple.quarantine VeraBot-backend-v0.1.0`。

## 4. Docker (可选，未实测)

```bash
cp .env.example .env && vi .env      # 填 DEEPSEEK_API_KEY
docker compose up -d --build         # 端口 ${PORT:-8000}；数据持久化到 ./data
```

`docker compose config` 校验通过；测试机的 Docker daemon 未运行，镜像没有实际构建 / 运行过。

## 5. 交付前检查 (Checklist)

- [ ] `docs/CHANGELOG.md`、`docs/STATUS.md` 已更新，版本号三处一致 (见 CONTRIBUTING)
- [ ] `uv run python scripts/test/multi_agent_test.py` 24/24；`avatar_profile_test.py` 21/21；`swift test` 通过 (当前 21 个用例)；Xcode 编译通过
- [ ] `scripts/package_backend.sh` 生成 zip；`unzip -l` 确认不含 `.env` / `*.db` / `.venv`
- [ ] 在全新临时目录解压并用其他端口启动：`PORT=8765 ./start.sh --detach` → `/api/health` 正常 → `./stop.sh`
- [ ] `git tag vX.Y.Z`
