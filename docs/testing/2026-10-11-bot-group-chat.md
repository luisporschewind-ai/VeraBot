# Bot 群聊 G3 验证与验收交付

日期：2026-10-11。用户授权继续 G3，并询问完成后能否验证一部分。范围为计划 Task 7：回归、真实 HTTP 联调、隔离模拟器环境与人工验收说明。

## 当前结论

G3 自动验证已完成；用户授权代验收后，Task 4/5 的主要页面交互及后台中断、重启偏好已在模拟器实际操作通过。真实模型体验与其余完整 G3 项仍待验收。所有模型回复使用确定性模拟提供者，未调用真实模型、未升级正式数据库，工作树未提交/合并/推送。构建、HTTP 通过不等同于完整端到端交互通过。

代码位于 `/Users/admin/.codex/worktrees/bot-group-chat-preview/VeraBot-v0.1`，基础提交 `84e0dc3`。保留主工作区与原模拟器数据。

## 自动证据

| 检查 | 结果 | 证据 |
|---|---|---|
| group_store / runtime / lifecycle | 13 / 7 / 8 通过 | `/tmp/vb_g3_group_{store,runtime,lifecycle}.log` |
| multi_agent / status_event / auth_stability / llm_body | 25 / 8 / 6 / 7 通过 | `/tmp/vb_g3_{multi_agent,status_event,auth_stability,llm_body}.log` |
| VeraBotKit | 211 Swift Testing + 1 XCTest 通过 | `/tmp/vb_g3_swift.log` |
| iOS Simulator build | BUILD SUCCEEDED | `/tmp/vb_g3_build.log` |
| 真实 TCP HTTP + SSE | 四组流程通过 | `/tmp/vb_g3_http.log`；`backend/scripts/test/group_http_test.py` |
| diff 格式 | git diff --check 通过 | 当前工作树 |

HTTP 流程使用真实 Uvicorn 单 worker、httpx 网络连接和 SQLite，替换模型传输。覆盖默认 A、点名 B、A→B→C、历史读取、重复 UUID 409；运行中再次发送/清空 409；停止两次均成功、剩余成员不发言；B 首次失败 C 继续、重试仅新增 B；收到 delta 后实际关闭 socket，轮次转 interrupted，重进无活动轮次，清空/删除成功。

G2 的 SQL 层扫描有 100 项原有违规，HEAD 基线与工作树比较无新增；本阶段未处理该遗留项，不能宣称全仓检查全绿。G2 [记录](2026-10-11-bot-group-chat-g2.md)保留详细边界与作者自审说明；本阶段没有独立审查，也未合并。

## GC-01～12 状态

| 用例 | 已有证据 | 仍待验证 |
|---|---|---|
| GC-01 创建边界 | store：2/4 人、1/5 人/重复/他人/空名/第11群、失败原子性 | 创建页面与错误展示 |
| GC-02 点名与顺序 | runtime + HTTP：只 B、严格 A→B→C，后者上下文收到前者实际回答 | 真实模型讨论质量 |
| GC-03 默认与偏好 | HTTP 默认 A/点名 B，客户端 reducer/VM；UI 偏好实现已编译 | 本地偏好持久化、成员操作交互 |
| GC-04 隔离 | store 所有权；runtime 私聊秘密/其他指令不混入；lifecycle 越权 | 真实账号切换页面 |
| GC-05 幂等与并发 | store + HTTP UUID 重复/冲突/busy；用量去重 | 快速重复点击视觉表现 |
| GC-06 停止 | lifecycle 部分回复/迟到事件，HTTP 重复停止/不启动后续成员 | 页面停止状态与反馈 |
| GC-07 失败/重试 | runtime 空回复；lifecycle 超时/上下文边界；HTTP B失败、C继续、只重试B | 页面重试入口与提示 |
| GC-08 恢复 | lifecycle 启动恢复；HTTP 实际socket断流；Swift旧会话拒绝 | 页面退出/后台/注销/换账号/重启App人工检查 |
| GC-09 删除与管理 | store 历史快照/只读；lifecycle Bot删除；HTTP运行清空409、停止后清空/删除 | 群信息确认框、只读界面 |
| GC-10 预算边界 | runtime上下文/输出限制/每日额度；lifecycle时间预算/usage去重与未知 | 真实提供者usage、真实耗时 |
| GC-11 身份/能力 | context结构化source与固定无工具规则、tools=None断言 | 提示注入语义抵抗、真实模型不虚报动作 |
| GC-12 私聊兼容 | multi_agent/status/auth/llm请求体 + Swift全包回归 | 私聊附件、确认卡片、记忆与设备交互完整验收 |

## 可复现隔离环境

启动（使用已有 Python 3.12 虚拟环境仅提供依赖，导入当前工作树代码）：

```sh
cd /Users/admin/.codex/worktrees/bot-group-chat-preview/VeraBot-v0.1
/Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python backend/scripts/dev/group_chat_demo.py --data-dir /tmp/verabot-group-g3-demo --port 8093 --delay 0.7
```

服务地址 `http://127.0.0.1:8093`，只监听本机；独立库 `/tmp/verabot-group-g3-demo/demo.db`，附件/数据目录同根。未指定 data-dir 则新建临时目录。仅用于开发验收，勿作为正式服务。所有 llm.stream_chat 均被替换，回复带「模拟回复」；无上游 HTTP 模型请求。日志 `provider-calls.jsonl` 只含本地测试上下文，可核对上下文；勿在这个测试账号输入个人敏感内容。

账号 `group-demo`，密码 `group-demo-123`，已有 A/B/C 三个 Bot 和「伙伴讨论 · G3 验收」群。默认每条模拟回答分片约 4 秒；本轮以 `--delay 0.7` 放慢至约 11 秒，便于镜像操作停止。参数允许 0.05–2 秒；发送 `[fail-once]` 全体讨论时 B 首次失败、C 继续，随后可单独重试 B。失败记忆仅在当前服务进程内，重启后再次触发。

真实 HTTP 检查（会创建并删除自己的测试群，最后保留一个新的人工作业群）：

```sh
/Users/admin/Desktop/VeraBot-v0.1/backend/.venv/bin/python backend/scripts/test/group_http_test.py http://127.0.0.1:8093
```

## 人工操作顺序

1. 使用独立「VeraBot G3 验收」模拟器，登录页「其他登录方式」选择用户名，再登录测试账号，助理页切换「群聊」。
2. 新建群，选 A/B/C，默认 A；发一条普通文字，确认只有 A 回复。
3. 点 B 发文字，确认只有 B 回复；点「一起讨论」，确认 A→B→C 独立气泡。
4. 讨论中点击停止，确认部分文字保留、其他成员不再开始；返回列表重进，确认历史和终态一致。
5. 发 `[fail-once]` 全体讨论，确认 B 失败 C 继续；点 B 的重试，只新增 B 回复，原问题和 A/C 不重复。
6. 群信息修改名称/默认成员；运行中先停止，再清空/删除并确认；失败时草稿和已有历史保留。
7. 补查后台、退出登录、换账号、删除 Bot 后不可点名/历史仍在，最后验证现有私聊。

测试账号上的这些数据都是模拟验收数据。连接真实服务、真实模型体验和正式环境迁移需另外安排；当前不得标记真实群聊验收通过。

## 模拟器交付证据

独立设备 `F02AB43D-CB5B-4F7E-AAF4-679D2EEB0E3B`（iPhone 17 / iOS 26），G3 构建已安装，`simctl launch` 返回进程 50012；已看到真实登录页，[截图](assets/2026-10-11-group-chat/g3-login.png)。仅此新设备的服务器偏好设为 `http://127.0.0.1:8093`。服务健康检查 HTTP 200，保留运行供用户测试。用户登录和群页面操作尚未代验。

首次迁移导致宿主机高负载，镜像连接/截图超时，已关闭本次镜像及浏览器任务；不把镜像连接记为通过。为降低负载，旧 G0 预览 App 和旧模拟器已关闭，账号与设备数据保留。原设备可用 `xcrun simctl boot 6FD1E62D-DA65-42B1-81F5-554042006671` 重新打开。验收使用原生 Simulator，无需镜像。自动证据摘录见 [g3-evidence.txt](assets/2026-10-11-group-chat/g3-evidence.txt)。

## 首轮人工反馈与修复（2026-10-11）

用户确认创建群、默认回应、全体讨论通过。点名入口不可点击、修改默认 C 后仍由 A 回应未通过。

根因：RobotAvatarView 自带 minimumDistance=0 的高优先级拖动手势，顶部外层按钮的点击被头像消费；GroupChatViewModel.update 只更新群资料，preferredBotID 仍是 A，发送时显式传 A 覆盖默认 C。

修复：仅顶部点名按钮中的头像不参与命中/独立辅助功能，交给外层按钮处理；扩大按钮命中区域并标记选中背景、点名提示。明确保存默认成员即同步 preferredBotID（包括默认成员已经是C而本地还选A），现有服务器/账号/群偏好持久化随之更新；仅传名称的更新保留用户点名选择；群设置保存会明确应用所选默认成员。

新增测试先复现 preferredBotID=1 而期望3的失败，再修复；首次修复完整 Swift 包 213 Swift Testing + 1 XCTest 通过；再补充同默认值保存覆盖旧本地选择测试。顶部手势修复仍需用户实际点击复验，自动测试不能代替此项。原反馈不直接改为验收通过。

最终修复：明确保存默认成员会覆盖旧本地点名，即使服务器默认值未变化；仅传name的API更新保留当前选择。新增三项回归（默认切换、仅改名、同默认值重新保存）均通过；完整包 214 Swift Testing + 1 XCTest、Simulator build、diff检查通过。日志 `/tmp/vb_g3_selection_final.log`、`/tmp/vb_g3_selection_build_final.log`。使用现有G3模拟器原地安装，不新增设备、不清除账号或群历史；本轮用户手动复验仍待确认。


## 用户授权代验收（2026-10-11）

用户报告「改为 C 并保存，结果还是 B 回应」，随后授权「你来替我进行验收」。使用已有 G3 设备，实际点击 SwiftUI 页面、发送消息并结合隔离库核对结果。本轮未新增模拟器，未修改正式群聊逻辑；只为开发模拟提供者加入可配置分片延迟。原始反馈在当前安装版本未复现，原因仍未确认，不能据本轮通过宣称异常已彻底修复。

| 用例 | 实际页面操作与证据 | 结果 |
|---|---|---|
| 保存默认 C | 用户原群 group 3 的设置已为 C、本地点名为 B；再次保存后顶部与输入框切为 C；发送 `a`，turn 17 仅 member 9 / C 完成。另实际切 B 保存再切 C 保存、退出重进，仍选 C。 | 通过；原反馈未复现 |
| 顶部点名 | 点击顶部 B，选中背景及输入框切为 B；发送 `b`，turn 18 仅 member 8 / B 完成。 | 通过 |
| 顺序讨论 | 在独立验收群 group 4 点击「大家讨论」发送 `s`；turn 19 的 A/B/C 依次生成独立气泡并完成。 | 通过 |
| 停止 | 页面发起讨论 `t`，流式期间点击停止；turn 20 stopped、cancel_requested=1，仅保留 A 的 33 字部分回复，B/C 未开始；返回列表重进仍显示停止终态与可用输入框。首次尝试点击过晚，未计通过。 | 通过 |
| 单成员失败 | 通过真实 HTTP 在 group 4 注入 `[fail-once] G3 UI acceptance`（受镜像键盘输入限制，触发消息不是 UI 发送）；turn 21 A 完成、B 失败、C 完成，实际页面显示一致。 | 故障结果 UI 通过；故障触发为 HTTP |
| 只重试失败 B | 在实际页面点击 B 的「再试一次」；turn 22 仅 target member 11 / B 完成，retry_of_message_id=50、复用 user_message_id=48，只新增消息 52，原问题仍只有一条、A/C 未重复。 | 通过 |
| 后台中断与恢复 | 页面全体讨论 `x` 开始后点镜像 Home；turn 25 interrupted，只保留 A 的 30 字部分回复，B/C 未开始。主屏幕点 Vera Bot 返回，显示「连接中断 · 回应未完成」和重试入口，输入框可用。turn 23 切后台过晚已完成、turn 24 镜像 Home 超时未生效，均未计中断通过。 | 通过 |
| 偏好跨 App 重启 | 原群重新保存 C，终止并重启现有 App，打开群仍选 C；发送 `r`，turn 26 仅 member 9 / C 完成。 | 通过 |

验收群 group 4 由 HTTP 创建，仅用于此次代验收；创建群 UI 已由用户此前验收通过，不把这个准备动作重复算作 UI 创建验证。用户原群 group 3、其他群和历史均保留；当前停留原群、默认及本地点名为 C，模拟服务保持运行。

证据：[轮次与消息快照](assets/2026-10-11-group-chat/acceptance/turns.json)、[保存 C 后回复](assets/2026-10-11-group-chat/acceptance/default-c.png)、[停止](assets/2026-10-11-group-chat/acceptance/stopped.png)、[失败 B / C 继续](assets/2026-10-11-group-chat/acceptance/failure-b.png)、[仅 B 重试](assets/2026-10-11-group-chat/acceptance/retry-b.png)、[后台返回](assets/2026-10-11-group-chat/acceptance/background-return.png)、[重启后 C 回复](assets/2026-10-11-group-chat/acceptance/restart-c.png)。截图为实际 Simulator 页面；全部回复仍为确定性模拟内容，不代表真实讨论质量。

镜像使用 LTS Node 24 启动并完成触摸/键盘操作，期间出现元数据短暂丢失和一次 Home 超时；刷新后恢复，未将失败操作算作通过。验收结束关闭临时镜像与浏览器页，保留同一原生 Simulator 和模拟服务。

仍待完整 G3 验收：真实模型讨论质量/用量/耗时，清空与删除等管理页面确认流程，注销/换账号/删除 Bot 的实际界面流程，以及现有私聊完整设备交互回归。此前自动/HTTP 证据保留，不混同本轮 UI 覆盖。本轮未提交、合并或推送。

## 合并前复查

独立代码审查发现快速返回群聊可读到尚未终结的轮次快照、页面此后保持 busy。新增 running→interrupted 的自动恢复测试先复现失败；修复为 load、已有请求和群忙冲突恢复时有界复查轮次快照，检查 epoch、账号与取消状态；超时/网络失败显示重新加载入口，不自动重发或停止其他设备的讨论。补充离开页面拒绝迟到快照测试，完整 Swift 包 216 Swift Testing + 1 XCTest 通过。后端群存储/执行/生命周期及私聊委派、状态、鉴权、LLM 请求体回归共 74 项通过。复审无其余合并阻塞项。日志 `/tmp/vb_group_restore_red.log`、`/tmp/vb_group_restore_green.log`、`/tmp/vb_group_premerge_*.log`。此前安装的设备包是这次小修之前的版本；以 main 后续构建为准。
