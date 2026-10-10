# 记忆成长 M5 实施计划

> **执行方式：**由当前执行者按任务顺序实施；步骤采用先写失败测试、再实现、再回归的流程。

**目标：**在 M3/M4 基础上加入本地向量混合召回，以及受权限过滤、可审计且不自动改权限的 Bot 协作优化。

**架构：**使用可选依赖 FastEmbed 与本地 `BAAI/bge-small-zh-v1.5`，将 float32 向量存入 SQLite；向量不可用时继续使用现有关键词召回。委派的显式记忆 ID 与目标 Bot 自己的 style/profile 记忆均在服务器校验后进入单独的结构化上下文；按委派结果的用户反馈只生成受限提示，不改变任何权限。

**技术栈：**FastAPI、SQLite、FastEmbed / ONNX Runtime、现有 Python 测试脚本、VeraBotKit。

**规格：**`docs/design/MEMORY_GROWTH.md` §7、§11.4、§17 Q5、MEM-65~68。

## 全局约束

- Embedding 使用本地 `BAAI/bge-small-zh-v1.5`；不调用云端 Embedding API。
- 记忆用户隔离、Bot `memory_access`、敏感记忆禁止委派、审计不写正文。
- 向量缺失、模型未安装或推理失败时回退现有关键词召回。
- 协作提示只提供建议，不修改 `delegate_to`、`accept_delegation` 或记忆权限。
- 长对话 / 摘要分块 RAG 属于可选项，本阶段不实现。
- Web 冻结；保留现有 M3/M4 代码与用户 `main` 的本地改动。

## 评审关注的输入与失败情形

- 可选模型依赖缺失、模型文件未缓存、推理异常时保持原关键词行为。
- 记忆编辑、删除、过期和 Bot 清理后，旧向量不能参与召回。
- 伪造、重复、超量、他人或目标不可见的 `memory_ids` 均不共享。
- 敏感、候选、已删除和摘要记忆不得经协作接口泄漏。
- 跨用户委派反馈、撤销反馈、缺少可评价委派的消息不污染建议。

---

### Task 1: 本地 Embedding 与 v18 向量存储

**文件：**新增 `backend/verabot/services/memory/embeddings.py`、`backend/verabot/db/migrations/v018_memory_vectors.py`；修改 `backend/pyproject.toml`、`backend/uv.lock`、`backend/verabot/core/config.py`、迁移入口；测试新增 `backend/scripts/test/memory_m5_test.py`。`requirements.txt` 保持基础依赖清单，向量运行时通过 uv 可选 extra 安装。

**接口：**`embeddings.score(user_id: int, memories: list[dict], query: str) -> dict[int, float] | None`；缺依赖或推理失败返回 `None`。向量按 memory id、模型名、维度、content_hash 与 float32 BLOB 保存。

- [x] 测试 v18 幂等迁移、索引维度、记忆删除级联；测试缺模型时返回 `None`。
- [x] 先运行测试确认它因 v18 / Embedding 接口缺失而失败。
- [x] 加入可选 `memory-vector` 依赖、本地模型配置及 v18 迁移；实现惰性、批量的本地编码和向量读写。
- [x] 运行 M5 定向测试及 M4/M3/M2 记忆回归。
- [x] 提交 Task 1 (`b06511f`)。

### Task 2: 关键词与语义混合召回

**文件：**修改 `backend/verabot/services/memory/recall.py`；测试 `memory_m5_test.py`。

**接口：**`rank(mems, query_text, semantic_scores=None)`；保留固定优先 style/profile 与既有注入上限，语义近邻可补入无关键词重叠的条目。

- [x] 测试语义近邻排序、固定置顶、注入数量 / 字数限制及 `None` 回退。
- [x] 确认测试先因当前关键词实现无法命中同义表达而失败。
- [x] 加入归一化余弦分数与关键词 / 时间 / 使用次数 / 置信度合并排序。
- [x] 运行 M5 与 M1~M4 记忆召回回归。
- [x] 提交 Task 2 (`e46847f`)。

### Task 3: 受控记忆共享与目标 Bot 资料

**文件：**修改 `backend/verabot/agents/delegation.py`、`context.py`、`runtime.py`、工具 schema；必要时新增协作 service；测试 `memory_m5_test.py`。

**接口：**`ask_bot(..., memory_ids: list[int] | None = None)`；服务器按所有者、active 状态、目标 `memory_access` 与 sensitivity 过滤。自动附加目标 Bot 可见的 style/profile 记忆；上下文总量有界，结果与 payload 记录实际共享 ID。

- [x] 测试允许的共享、拒绝的 ID、敏感 / 候选 / 跨用户数据排除、目标 `none` / `bot` / `bot_and_global`、正文不进审计日志。
- [x] 运行测试确认新参数和过滤器尚不存在。
- [x] 实现 schema 校验、过滤、限长渲染、审计及目标 Bot 可见的 style/profile 注入。
- [x] 运行委派、工具路由、M3/M4 权限回归。
- [x] 提交 Task 3。

### Task 4: 根据反馈生成受限协作提示

**文件：**新增 `backend/verabot/services/memory/collaboration.py`；修改 `backend/verabot/services/memory/feedback.py`、`runtime.py`、`prompts.py`、必要的迁移 / store；测试 `memory_m5_test.py`。

**接口：**`collaboration.prompt_hints(user_id: int, bot: dict) -> list[str]`；仅汇总当前用户 depth-0 Bot 的成功委派和对应助手回答评分，至少 3 条可归因反馈后提供最多 3 条提示；多目标委派不参与统计，不读其他用户数据、不自动改权限。

- [x] 测试反馈阈值、目标排序、清除反馈后的更新、跨用户隔离与提示条数上限。
- [x] 运行测试确认当前 prompt 尚无反馈建议。
- [x] 实现最少化聚合查询并将建议追加至 depth-0 system prompt；委派子 Bot 不递归继承。
- [x] 运行 M5 与反馈、prompt、委派测试。
- [x] 提交 Task 4。

### Task 5: 文档、全量验证和提交

**文件：**修改 `docs/design/MEMORY_GROWTH.md`、`docs/testing/TEST_CASES_v0.1.md`、`docs/STATUS.md`、`docs/CHANGELOG.md`。

- [x] 记录本地模型选择、安装 / 缓存方式、回退规则、隐私边界、M5 验收及可选 RAG 延后。
- [x] 运行完整记忆后端测试、VeraBotKit 测试、iOS Simulator 构建和必要的后端回归。
- [x] 完成差异检查与整支代码复核，提交到 `codex/memory-m5`；不合并、不推送。
