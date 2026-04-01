# Nova Voice Assistant (Flutter)

现代化 Flutter 语音助手示例项目，包含炫酷动效主界面、音频录制、WebSocket 实时通信、历史记录与设置页面。

## 项目介绍

- 深色科技风 UI：深蓝渐变背景、中央发光语音球、底部麦克风主按钮。
- 音频能力：麦克风权限管理、16kHz/16bit/单声道 PCM 录音流。
- 通信能力：WebSocket 消息收发、30 秒心跳、断线重连（指数退避，最多 3 次）。
- 状态管理：使用 `provider` 管理音频、网络、配置、历史记录。

## 环境要求

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android API 21+

## 安装步骤

1. 安装 Flutter 与 Android Studio，并完成环境变量配置。
2. 在项目根目录执行：

```bash
flutter pub get
```

3. 连接 Android 设备或启动模拟器。

## 配置说明

- 默认 WebSocket 地址在 `lib/utils/constants.dart` 中：
  - `AppConstants.defaultWebSocketUrl`
- 运行后也可在应用 `Settings` 页面直接修改 WebSocket 地址。
- 配置会持久化保存到本地（`SharedPreferences`）。

## 运行指令

```bash
flutter run
```

## Text-Only GUI-Agent E2E

1. 在手机上开启无线调试并完成 `adb pair` / `adb connect`。
2. 启动后端（`F:\voice-project\voa`）：

```bash
mvn -pl server spring-boot:run
```

若 `8080` 端口被占用，可改为：

```bash
mvn -pl server spring-boot:run -Dspring-boot.run.arguments="--server.port=18080"
```

3. 将客户端 WebSocket 地址设置为与你后端启动端口一致：

```text
ws://<backend-ip>:<backend-port>/agent
```

4. 在主页输入文本任务并发送。
5. 若任务进入高风险审批，确认页面出现 `Approve` / `Reject` 按钮。
6. 点击 `Approve` 或 `Reject`，确认状态推进：
   - `Approve`: `waiting_approval -> running -> completed/failed`
   - `Reject`: `waiting_approval -> cancelled`

### 审批消息示例（WebSocket）

客户端创建任务：

```json
{
  "type": "task_create",
  "requestId": "req-2001",
  "data": {
    "text": "delete order"
  }
}
```

服务端要求审批：

```json
{
  "type": "task_need_approval",
  "requestId": "req-2001",
  "taskId": "task-xxx",
  "data": {
    "action": "submit",
    "reason": "needs manual approval"
  }
}
```

客户端同意：

```json
{
  "type": "task_approve",
  "requestId": "req-2001",
  "taskId": "task-xxx"
}
```

客户端拒绝：

```json
{
  "type": "task_reject",
  "requestId": "req-2001",
  "taskId": "task-xxx"
}
```

## 主要目录结构

```text
lib/
├── main.dart
├── app.dart
├── screens/
│   ├── home_screen.dart
│   ├── history_screen.dart
│   └── settings_screen.dart
├── widgets/
│   ├── voice_button.dart
│   ├── audio_visualizer.dart
│   ├── glow_effect.dart
│   └── bottom_nav_button.dart
├── services/
│   ├── audio_service.dart
│   ├── websocket_service.dart
│   └── permission_service.dart
├── models/
│   ├── conversation_message.dart
│   └── app_config.dart
├── providers/
│   ├── app_provider.dart
│   ├── audio_provider.dart
│   └── websocket_provider.dart
└── utils/
    ├── constants.dart
    └── logger.dart
```

## 常见问题

### 1) 录音按钮点击后无反应

- 检查是否授予麦克风权限。
- 若为“永久拒绝”，请前往系统设置手动开启。

### 2) WebSocket 无法连接

- 检查服务器地址、端口、协议（`ws://` 或 `wss://`）是否正确。
- 确认手机与服务端网络互通，且服务端已监听对应路径。

### 3) Android 端报权限相关错误

- 请确认 `android/app/src/main/AndroidManifest.xml` 已包含：
  - `android.permission.INTERNET`
  - `android.permission.RECORD_AUDIO`
  - `android.permission.MODIFY_AUDIO_SETTINGS`

## 备注

- 当前仓库未包含 `flutter create` 生成的完整 Android/Gradle 工程骨架时，可在本目录执行：

```bash
flutter create .
```

- 执行后如有文件冲突，请保留本仓库中的 `lib/`、`pubspec.yaml` 和 Android 权限配置。
