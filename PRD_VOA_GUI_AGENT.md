# VOA GUI-Agent PRD（AI 可执行规范版）

- 文档版本：`v1.0`
- 更新日期：`2026-03-27`
- 项目代号：`VOA GUI-Agent`
- 适用仓库：`E:\project\voice\flutter-voice`（Flutter 客户端） + `F:\voice-project\voa`（Java 服务端）
- 目标：用本 PRD 直接驱动 AI 分阶段生成代码

---

## 1. 文档目的

本 PRD 用于定义一个分阶段落地的 GUI-Agent 产品，重点解决：

1. 先用文本方式接入 GELab-Zero 跑通自动化闭环；
2. 再接入语音输入，形成完整的语音 GUI-Agent；
3. 避免强依赖 USB 数据线，优先无线连接方案；
4. 提供 AI 可执行的接口契约、状态机和验收标准。

---

## 2. 产品目标与非目标

## 2.1 产品目标

1. 用户可通过文本/语音发起移动端任务；
2. 服务端通过 GELab-Zero 生成 GUI 操作步骤并执行；
3. 客户端实时展示任务进度、步骤结果、失败原因；
4. 高风险动作需人工确认（安全阈值）。

## 2.2 非目标（当前阶段不做）

1. iOS 自动化；
2. 多租户权限系统；
3. 大规模多设备集群调度；
4. 全自治高风险执行（必须保留确认门）。

---

## 3. MVP 分级规划（按你要求）

## 3.1 MVP V1：文本接入 GELab-Zero（无语音）

### 目标
仅通过文本输入跑通端到端 GUI 自动化闭环。

### 用户价值
- 快速验证 Agent 核心能力；
- 降低语音链路复杂度，先把执行稳定性做对。

### 范围（In Scope）
1. Flutter 新增文本输入框与任务发起按钮；
2. Java 网关支持 `task.create` 文本任务；
3. Java 编排层接入 GELab-Zero 规划与执行；
4. Device Bridge 支持 ADB over Wi-Fi（优先无线）；
5. 客户端展示任务状态与步骤时间线；
6. 支持 `task.cancel` 和失败重试（整任务重试）。

### 非范围（Out of Scope）
1. 语音录音、ASR、端点检测；
2. 语音实时字幕；
3. 多设备并行任务。

### 上线门槛（Go/No-Go）
1. 3 个固定任务成功率 >= 85%；
2. 任务状态机无卡死；
3. 高风险动作可拦截为 `waiting_approval`；
4. 无 USB 常驻依赖（允许首次配置）。

---

## 3.2 MVP V2：接入语音（在 V1 基础上增量）

### 目标
把现有语音链路纳入任务执行主流程，实现语音到 GUI 操作闭环。

### 用户价值
- hands-free 场景可直接下达任务；
- 保留文本兜底，增强可用性。

### 范围（In Scope）
1. 复用现有 Flutter 录音与 WebSocket 音频分块；
2. Java 侧 ASR 最终文本自动触发 `task.create`；
3. 语音流程支持：开始、停止、取消、异常回退；
4. 实时展示：用户转写、执行中状态、模型结果；
5. 语音与文本共用统一任务协议和状态机。

### 非范围（Out of Scope）
1. 说话人分离；
2. 多语种识别自动切换；
3. 离线端侧全栈 ASR+TTS 优化。

### 上线门槛（Go/No-Go）
1. 语音任务成功率 >= 80%；
2. 停录到任务进入 `running` <= 2.5s（内网目标）；
3. 断线后不重复执行副作用动作。

---

## 3.3 MVP V2+（可选增强）

1. 步骤级重试（从失败步骤继续）；
2. 会话恢复（客户端重连后回补任务事件）；
3. 执行器抽象（ADB Executor / Companion Executor 可插拔）。

---

## 4. 用户角色与场景

## 4.1 用户角色

1. 操作员：发任务并观察结果；
2. 管理员：配置服务端地址、策略和执行权限；
3. 开发测试：排查失败链路、回放日志。

## 4.2 典型场景

1. 文本：`在美团搜索附近评分最高的咖啡店并收藏第一个`；
2. 语音：`帮我在地图里导航到最近的地铁站`；
3. 高风险：`帮我下单` -> 必须人工确认后执行。

---

## 5. 系统架构（目标态）

```text
Flutter App
  -> WebSocket Gateway (Java)
     -> ASR Service (V2 才启用)
     -> Task Orchestrator
        -> GELab Adapter
        -> Device Bridge (ADB over Wi-Fi)
  <- Task Events / Step Results / Errors
```

---

## 6. 协议规范（AI 生成代码必须遵守）

## 6.1 统一消息 Envelope

```json
{
  "version": "1.0",
  "traceId": "uuid",
  "sessionId": "uuid",
  "taskId": "uuid-or-null",
  "type": "event.type",
  "ts": "2026-03-27T12:34:56.000Z",
  "payload": {}
}
```

### 字段约束
1. `version`：固定 `1.0`；
2. `traceId`：一次请求链路唯一，必填；
3. `sessionId`：连接会话唯一，必填；
4. `taskId`：任务阶段必填，非任务事件可为 `null`；
5. `type`：事件名，必填；
6. `ts`：ISO8601 时间，必填；
7. `payload`：对象，必填（可空对象）。

## 6.2 客户端 -> 服务端事件

### V1 必选
1. `client.hello`
2. `task.create`
3. `task.cancel`
4. `task.approve`
5. `task.reject`
6. `client.ping`

### V2 增量
1. `asr.start`
2. `asr.chunk`
3. `asr.end`

## 6.3 服务端 -> 客户端事件

### V1 必选
1. `server.hello`
2. `server.pong`
3. `task.created`
4. `task.running`
5. `task.step.started`
6. `task.step.result`
7. `task.waiting_approval`
8. `task.completed`
9. `task.failed`
10. `task.cancelled`
11. `error`

### V2 增量
1. `asr.partial`
2. `asr.final`

## 6.4 关键 payload 结构

### `task.create`
```json
{
  "inputType": "text|voice",
  "text": "用户任务文本",
  "deviceId": "android-device-id",
  "riskPolicy": "strict|balanced|open"
}
```

### `task.step.started`
```json
{
  "stepId": "s-001",
  "action": "tap|swipe|input|back|wait|assert",
  "target": "控件描述或坐标",
  "reason": "为何执行该步骤"
}
```

### `task.step.result`
```json
{
  "stepId": "s-001",
  "ok": true,
  "summary": "步骤结果摘要",
  "artifact": {
    "screenshot": "optional-path-or-base64",
    "uiTree": "optional-json"
  }
}
```

### `task.waiting_approval`
```json
{
  "approvalId": "a-001",
  "riskLevel": "high",
  "action": "submit_order",
  "reason": "可能产生支付行为"
}
```

### `error`
```json
{
  "code": "E_TIMEOUT|E_PROTOCOL|E_DEVICE|E_MODEL|E_INTERNAL",
  "message": "可读错误信息",
  "retriable": true
}
```

---

## 7. 任务状态机

`idle -> created -> running -> waiting_approval -> running -> completed`

异常分支：
1. 任意状态可到 `failed`；
2. `created/running/waiting_approval` 可到 `cancelled`；
3. `failed` 可重试生成新 `taskId`。

状态约束：
1. 同一 `taskId` 不允许并行进入两个终态；
2. 终态（`completed/failed/cancelled`）后禁止继续推 `step` 事件。

---

## 8. 功能需求清单（带版本标签）

| ID | 需求 | 版本 | 优先级 | 验收摘要 |
|---|---|---|---|---|
| FR-001 | 文本创建任务 | V1 | P0 | `task.create` 可触发执行 |
| FR-002 | 任务时间线展示 | V1 | P0 | 显示状态与步骤结果 |
| FR-003 | 任务取消 | V1 | P0 | `task.cancel` 后 2s 内终止 |
| FR-004 | 高风险确认门 | V1 | P0 | `waiting_approval` 必须人工确认 |
| FR-005 | 失败重试（整任务） | V1 | P1 | 一键重试并生成新 task |
| FR-006 | 语音采集与分块上行 | V2 | P0 | `asr.start/chunk/end` 正常 |
| FR-007 | ASR 最终结果触发任务 | V2 | P0 | `asr.final` -> `task.create` |
| FR-008 | 语音实时字幕 | V2 | P1 | partial/final 可见 |
| FR-009 | 断线恢复与防重放 | V2 | P0 | 重连无重复副作用 |
| FR-010 | 统一历史记录归档 | V2 | P1 | 文本/语音统一可回放 |

---

## 9. 非功能需求（NFR）

| ID | 指标 | 目标值 |
|---|---|---|
| NFR-001 | 文本任务首响应时延 | <= 1.5s |
| NFR-002 | 语音停录到 running | <= 2.5s |
| NFR-003 | WebSocket 可用性 | >= 99%（内测） |
| NFR-004 | 幂等性 | 同一 step 不重复副作用执行 |
| NFR-005 | 可观测性 | 全链路 traceId 可检索 |
| NFR-006 | 安全性 | 客户端不存生产密钥 |

---

## 10. 风控与安全策略

1. 动作分级：
   - L1（只读）：自动执行；
   - L2（轻副作用）：默认可配置确认；
   - L3（高副作用）：强制确认。
2. 执行白名单：限定可操作 App 包名和动作类型；
3. 超时保护：步骤超时、任务超时、最大步数限制；
4. 审计日志：记录输入、计划、动作、结果、错误。

---

## 11. 版本实现清单（AI 开发任务拆解）

## 11.1 V1 开发任务（文本）

### Flutter
1. `home_screen.dart` 新增文本输入与发送按钮；
2. `websocket_service.dart` 增加 `task.*` 事件收发封装；
3. `websocket_provider.dart` 增加任务状态与步骤列表状态；
4. 新增 `models/task_event.dart`、`models/task_state.dart`；
5. UI 增加任务时间线组件（可放 `widgets/task_timeline.dart`）。

### Java
1. 新增 `TaskOrchestrator`（状态机）；
2. 新增 `GelabAdapter`（模型请求适配）；
3. 新增 `DeviceBridge`（ADB Wi-Fi 执行）；
4. `VoiceWebSocketHandler` 增加 `task.*` 事件路由；
5. 错误码与幂等键实现。

## 11.2 V2 开发任务（语音）

### Flutter
1. 保留现有录音分块与 `asr_*` 事件；
2. 在 `asr.final` 回来后自动发 `task.create(inputType=voice)`；
3. 语音/文本统一写入任务历史。

### Java
1. 复用 Vosk 流式 ASR；
2. `asr.final` 与任务编排耦合；
3. 加入断线恢复与防重复执行。

---

## 12. 验收测试（UAT）

## 12.1 V1 UAT
1. 文本任务可创建、执行、完成；
2. 任务中可取消；
3. 高风险动作会停在确认态；
4. 拒绝确认后任务终止且可重试；
5. 错误事件可读且可重试。

## 12.2 V2 UAT
1. 语音录制、停录、ASR、任务触发完整链路可用；
2. partial/final 字幕展示正常；
3. 网络抖动后不重复执行副作用动作；
4. 文本与语音任务历史都可查看。

---

## 13. 里程碑计划

1. 里程碑 M1（V1）：2 周
   - 文本任务闭环 + 任务时间线 + 基础风控。
2. 里程碑 M2（V2）：2 周
   - 语音触发任务 + 断线恢复 + 稳定性优化。
3. 里程碑 M3（V2+ 可选）：1~2 周
   - 步骤级重试 + 会话回补 + 可观测增强。

---

## 14. 已知风险与缓解

1. 设备连接不稳定（无线 ADB）
   - 缓解：重连、心跳、步骤幂等。
2. 协议漂移导致前后端不兼容
   - 缓解：以本 PRD 协议为唯一契约源，增加 contract test。
3. 模型动作偏差
   - 缓解：高风险确认门、白名单、最大步数限制。
4. 客户端泄露密钥风险
   - 缓解：密钥仅服务端管理，客户端只连网关。

---

## 15. AI 生成代码执行规则（关键）

为保证可控，本项目后续使用 AI 生成代码时，必须按以下顺序：

1. **先生成协议模型**：先生成 `Envelope`、事件 DTO、错误码枚举；
2. **再生成状态机**：任务状态迁移与约束单测先行；
3. **再生成接口层**：WebSocket handler / provider；
4. **最后生成 UI 和执行器**：减少返工。

每次 AI 产出必须附带：
1. 变更文件清单；
2. 新增事件名与字段列表；
3. 单元测试与集成测试说明；
4. 回滚方案。

---

## 16. 附录：最小示例消息

### 创建文本任务
```json
{
  "version": "1.0",
  "traceId": "tr-001",
  "sessionId": "ss-001",
  "taskId": null,
  "type": "task.create",
  "ts": "2026-03-27T12:00:00.000Z",
  "payload": {
    "inputType": "text",
    "text": "打开地图并导航到最近地铁站",
    "deviceId": "emulator-5554",
    "riskPolicy": "strict"
  }
}
```

### 步骤结果返回
```json
{
  "version": "1.0",
  "traceId": "tr-001",
  "sessionId": "ss-001",
  "taskId": "tk-001",
  "type": "task.step.result",
  "ts": "2026-03-27T12:00:04.000Z",
  "payload": {
    "stepId": "s-003",
    "ok": true,
    "summary": "已点击搜索框并输入关键词"
  }
}
```

### 高风险确认
```json
{
  "version": "1.0",
  "traceId": "tr-001",
  "sessionId": "ss-001",
  "taskId": "tk-001",
  "type": "task.waiting_approval",
  "ts": "2026-03-27T12:00:08.000Z",
  "payload": {
    "approvalId": "ap-001",
    "riskLevel": "high",
    "action": "submit_order",
    "reason": "该动作将提交订单"
  }
}
```
