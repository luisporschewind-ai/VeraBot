# 本地运行 (Run locally) — v0.1.0

适用：macOS (测试机为 Intel MacBook Pro 13" 2018，Xcode 26.0.1)。Linux 可运行后端。

## 1. 后端 (Backend)

```bash
cd backend
./start.sh                 # 前台运行；首次会安装 uv / Python 3.12 / 依赖，并提示输入 DeepSeek Key
./start.sh --detach        # 后台运行：日志 data/server.log，PID data/server.pid
./stop.sh                  # 停止后台服务
```

也可以在 Finder 里双击 `backend/start.command`。

- 检查：`curl -s --noproxy '*' http://127.0.0.1:8000/api/health` → `{"ok":true,"model":"deepseek-chat"}`
- API 文档：<http://127.0.0.1:8000/docs>；Web 客户端：<http://127.0.0.1:8000/>
- 换端口：`PORT=8765 ./start.sh`
- 网络受限：`VERABOT_FORCE_MIRROR=1 ./start.sh` 直接用清华 tuna 镜像安装依赖 (`VERABOT_PYPI_MIRROR` 可改镜像地址)。
- 数据：`backend/data/verabot.db` (SQLite)、`backend/data/.jwt_secret`。备份时复制整个 `backend/data/`。
- 注意：Mac 重启后后端不会自动启动，需要重新运行 `./start.sh --detach`。
- 如果终端设置了 HTTP 代理，访问本机时用 `curl --noproxy '*'`。

### 演示数据 (Demo)

```bash
cd backend && uv run python scripts/dev/seed_demo.py          # 创建 demo / verabot2026：Vera 🐼、小研、阿厨
cd backend && uv run python scripts/dev/seed_demo.py --reset  # 清空 demo 的历史后重建示例对话 (会调用 LLM)
```

## 2. iOS App

1. 启动后端 (上一节)。
2. `open frontend/ios/VeraBot.xcodeproj` → 选择 **iPhone 17** 模拟器 → ⌘R。
   命令行等价：`frontend/scripts/run_ios.sh "iPhone 17"` (编译到 `/tmp/verabot_dd`，安装并启动)。
3. 登录 `demo` / `verabot2026`。服务器地址默认 `http://127.0.0.1:8000`，可在登录页修改。
4. 常用路径：Bot 列表 → 点 Vera 进入对话 → 点顶部标题打开「Bot 详情」(sheet) → 协作记录；首页左上角头像 → 设置 (账号 → 语音 → 关于 → 退出登录)。

**模拟器键盘**：模拟器默认连接 Mac 的硬件键盘，软键盘不会弹出。测试键盘相关行为时：Simulator 菜单 **I/O → Keyboard → 取消勾选 Connect Hardware Keyboard**，或按 **⌘K (Toggle Software Keyboard)**。

**SPM 本地包测试**：`cd frontend/ios/Packages/VeraBotKit && swift test`。

## 3. 测试 (Tests)

| 命令 (在 `backend/` 下) | 说明 | 是否调用 LLM |
|---|---|---|
| `uv run python scripts/test/multi_agent_test.py` | 多 Agent 权限 / 护栏 / 迁移 (MA-01~24)，临时 DB | 否 (mock) |
| `uv run python scripts/test/smoke_test.py` | 端到端冒烟测试，结束后删除测试账号；未配置 `OPENAI_API_KEY` 时语音转写 2 项记为 SKIP | 是 |
| `uv run python scripts/test/api_regress.py` 然后 `api_regress2.py` | 迭代 2 回归 REG-* / TC-*：前者创建临时用户 `qa_reg_*`，后者复用并在结束时删除 | 是 |
| `uv run python scripts/test/api_v01_tc*.py` | 迭代 1 API 用例 | 部分 |

iOS UI 自动化辅助：`source frontend/scripts/sim/ui.sh` (需要给终端「辅助功能」权限)，见 [frontend/README.md](../../frontend/README.md)。用例与结果：[TEST_CASES_v0.1.md](../testing/TEST_CASES_v0.1.md)。
