# 贡献指南 (CONTRIBUTING)

## 1. 基本规则

- **代码和文档在同一个 commit 里修改**。改了行为、接口、配置或 UI，就要在同一个 commit 里更新相应的文档 (见下方清单)。PR / commit 中不允许「文档以后再补」。
- 一个 commit 只做一件事。commit message 用中文或英文均可，格式：`<范围>: <说明>`，例如 `backend: 委派记录增加 tokens 字段`、`ios: 修复 sheet 保存后布局`、`docs: 更新 RUN_LOCAL`。
- 不提交密钥和本地数据：`backend/.env`、`backend/data/*.db`、`.jwt_secret`、`.venv/`、DerivedData、临时截图 (见 `.gitignore`)。提交前执行 `git status` 确认。
- 后端与前端是两个可独立交付的项目：`frontend/` 不 import `backend/` 的代码，只通过 HTTP API 交互。

## 2. 文档检查清单 (Docs checklist)

每个 commit 提交前逐项确认：

- [ ] `docs/CHANGELOG.md`：在 `[Unreleased]` 下记录改动 (新增 / 变更 / 修复)。
- [ ] `docs/STATUS.md`：功能状态、已知限制、下一步是否需要更新。
- [ ] 接口 / 环境变量变化 → `backend/README.md`、`backend/.env.example`、`docs/product/FEATURES.md` (API 摘要)。
- [ ] 模块 / 目录 / 依赖变化 → `docs/design/ARCHITECTURE.md`；依赖版本变化需同时更新 `uv.lock` 与 `requirements.txt` (`uv export`)。
- [ ] 多 Agent 权限 / 护栏变化 → `docs/design/MULTI_AGENT_DESIGN.md`。
- [ ] 行为变化 → `docs/testing/TEST_CASES_v0.1.md` 增加或更新用例，并记录结果。
- [ ] UI 变化 → 更新 `assets/screenshots/` 中对应截图 (或在 STATUS 中注明截图过时)。
- [ ] 运行方式变化 → `docs/ops/RUN_LOCAL.md` / `docs/ops/DELIVERY.md`、`frontend/README.md`。

## 3. 版本号 (SemVer)

遵循 [语义化版本 (Semantic Versioning)](https://semver.org/lang/zh-CN/)：`MAJOR.MINOR.PATCH`。

- `PATCH`：向后兼容的缺陷修复。
- `MINOR`：向后兼容的新功能 (包括新增 API 字段、新增可选环境变量)。
- `MAJOR`：不兼容的改动 (删除 / 重命名 API、数据库需要手动迁移)。1.0.0 之前，不兼容改动可以只升 MINOR，但必须在 CHANGELOG 中标注 **Breaking**。

发布步骤：

1. 同步修改版本号：`backend/verabot/__init__.py` (`__version__`)、`backend/pyproject.toml` (`version`)、iOS `MARKETING_VERSION` (Xcode Target → General，或 `project.pbxproj`)。
2. `docs/CHANGELOG.md` 把 `[Unreleased]` 改为 `[x.y.z] — YYYY-MM-DD`；更新 `docs/STATUS.md`。
3. `git commit` 后打 tag：`git tag -a vX.Y.Z -m "vX.Y.Z"`。
4. 生成后端交付件：`scripts/package_backend.sh` → `dist/VeraBot-backend-vX.Y.Z.zip`。

## 4. 提交前自测

```bash
cd backend && uv run python scripts/test/multi_agent_test.py     # mock LLM，确定性，24/24
cd frontend/ios/Packages/VeraBotKit && swift test                 # VeraBotKit 单元测试
cd frontend && scripts/run_ios.sh                                 # 编译并在模拟器运行
```

有真实 DeepSeek Key 时再跑 `backend/scripts/test/smoke_test.py`、`api_regress*.py` (会调用 LLM、产生费用)。
