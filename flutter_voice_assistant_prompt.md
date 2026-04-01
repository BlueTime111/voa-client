# Flutter 语音助手 Android 应用构建提示词

## 项目概述

创建一个现代化的 Flutter 语音助手 Android 应用，具有炫酷的 UI 设计、实时 WebSocket 通信和音频录制功能。

---

## 🎨 界面设计要求

### 整体风格
- **配色方案**：深色主题
  - 背景：深蓝到黑色的径向渐变 (`#0A1929` → `#000000`)
  - 主色调：蓝色系 (`#1E88E5`, `#42A5F5`)
  - 文字：白色主标题，浅灰色副标题 (`#BDBDBD`)
- **设计风格**：Material Design 3，现代简洁
- **适配要求**：支持状态栏安全区域，适配不同屏幕尺寸

### 核心 UI 元素

#### 1. 中央语音按钮
- **尺寸**：直径 200dp 的圆形按钮
- **背景**：蓝色渐变 (`LinearGradient` 从 `#1E88E5` 到 `#42A5F5`)
- **图标**：白色音频波形（4-5 条竖线，中间高两边低，类似 `|||‖|||` 形状）
- **发光效果**：
  - 外围蓝色光晕，使用 `BoxShadow` 实现
  - 0-30dp 的模糊扩散效果
  - 半透明蓝色 (`#1E88E5` with 40% opacity)
- **动画效果**：
  - 待机状态：呼吸动画（缩放 0.95 → 1.0，循环 2 秒）
  - 监听状态：光晕脉冲扩散（从 1.0 → 1.2，循环 1.5 秒）
  - 点击反馈：涟漪效果 (`InkWell`)

#### 2. 文字提示区域
- **主标题**："How can I help you?"
  - 字体：粗体，32sp
  - 颜色：纯白色 (`#FFFFFF`)
  - 位置：屏幕垂直居中偏下（距离中央按钮下方 80dp）
- **副标题**："I'm listening, go ahead."
  - 字体：常规，16sp
  - 颜色：浅灰色 (`#BDBDBD`)
  - 位置：主标题下方 12dp
- **对齐方式**：水平居中

#### 3. 底部导航栏
- **布局**：三个图标按钮等距分布
- **左侧按钮**：History（历史记录）
  - 图标：`Icons.history` 或时钟图标
  - 标签："History"
- **中央按钮**：麦克风（主交互按钮）
  - 背景：蓝色圆形 (直径 64dp)
  - 图标：白色麦克风 `Icons.mic`
  - 外围光晕效果
- **右侧按钮**：Settings（设置）
  - 图标：`Icons.settings` 齿轮图标
  - 标签："Settings"
- **样式**：
  - 图标颜色：灰色 (`#9E9E9E`)
  - 标签：12sp，灰色
  - 位置：距离屏幕底部 40dp

### 动画细节实现

#### 音频波形动画
- 录音时波形条随音量跳动
- 使用 `AnimatedContainer` 或 `CustomPaint`
- 跳动频率：120-180 次/分钟
- 高度随机变化范围：10-30dp

#### 光晕脉冲动画
```dart
// 参考实现逻辑
AnimatedBuilder(
  animation: _pulseAnimation,
  builder: (context, child) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.4),
            blurRadius: 30 * _pulseAnimation.value,
            spreadRadius: 10 * _pulseAnimation.value,
          ),
        ],
      ),
    );
  },
)
```

---

## 💻 技术实现要求

### 项目配置

#### 基本信息
- **Flutter SDK**：3.0 或更高版本
- **Dart SDK**：3.0+
- **Android 最低版本**：API 21 (Android 5.0)
- **目标版本**：API 34 (Android 14)
- **包名**：`com.example.nova_voice_assistant`

#### 必需的权限配置
在 `android/app/src/main/AndroidManifest.xml` 添加：
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

### 核心功能实现

#### 1. 音频录制模块
- **插件选择**：
  - 推荐：`record: ^5.0.0` 或 `flutter_sound: ^9.0.0`
  - 备选：`audio_session` + `flutter_sound_lite`
- **功能要求**：
  - 实时音量监控（用于驱动波形动画）
  - PCM 格式音频流输出
  - 采样率：16kHz
  - 位深度：16-bit
  - 声道：单声道
- **状态管理**：
  - 空闲、录音中、暂停、处理中

#### 2. WebSocket 通信模块
- **插件**：`web_socket_channel: ^3.0.0`
- **功能要求**：
  - 支持音频流实时传输（分块发送，每块 1-2 秒）
  - 接收服务器返回的文本响应
  - 心跳机制（30 秒间隔）
  - 断线自动重连（最多重试 3 次，指数退避）
  - 连接状态监听
- **配置项**：
  - WebSocket URL 可在设置页面修改
  - 默认：`ws://your-server-address:port/ws`

#### 3. 权限管理
- **插件**：`permission_handler: ^11.0.0`
- **实现逻辑**：
  - 应用启动时检查麦克风权限
  - 未授权时弹出引导对话框
  - 被永久拒绝时跳转到系统设置页

#### 4. 状态管理
- **方案**：`provider: ^6.0.0` 或 `riverpod: ^2.0.0`
- **状态对象**：
  - `AudioState`：录音状态、音量等级
  - `WebSocketState`：连接状态、消息队列
  - `AppState`：全局配置、历史记录

### 项目文件结构

```
lib/
├── main.dart                          # 应用入口
├── app.dart                           # 应用配置（主题、路由）
│
├── screens/
│   ├── home_screen.dart               # 主界面（语音交互）
│   ├── history_screen.dart            # 历史记录页面
│   └── settings_screen.dart           # 设置页面
│
├── widgets/
│   ├── voice_button.dart              # 中央语音按钮组件
│   ├── audio_visualizer.dart          # 音频波形可视化
│   ├── glow_effect.dart               # 光晕效果组件
│   └── bottom_nav_button.dart         # 底部导航按钮
│
├── services/
│   ├── audio_service.dart             # 音频录制服务
│   ├── websocket_service.dart         # WebSocket 通信服务
│   └── permission_service.dart        # 权限管理服务
│
├── models/
│   ├── conversation_message.dart      # 对话消息模型
│   └── app_config.dart                # 应用配置模型
│
├── providers/
│   ├── audio_provider.dart            # 音频状态管理
│   └── websocket_provider.dart        # WebSocket 状态管理
│
└── utils/
    ├── constants.dart                 # 常量定义
    └── logger.dart                    # 日志工具
```

### 依赖库配置

在 `pubspec.yaml` 添加：

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 网络通信
  web_socket_channel: ^3.0.0
  
  # 音频录制
  record: ^5.0.0
  # 或者使用：flutter_sound: ^9.0.0
  
  # 权限管理
  permission_handler: ^11.0.0
  
  # 状态管理
  provider: ^6.0.0
  
  # 路径处理
  path_provider: ^2.0.0
  
  # 本地存储（保存历史记录）
  shared_preferences: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## 🚀 核心页面功能说明

### 1. 主界面 (Home Screen)
- **布局**：
  - 顶部：状态栏占位
  - 中央：大型语音按钮 + 发光效果
  - 中下部：提示文字区域
  - 底部：三按钮导航栏
- **交互逻辑**：
  - 点击中央按钮 → 开始录音 → 显示波形动画
  - 再次点击 → 停止录音 → 发送音频到服务器
  - 接收响应 → 在提示文字区域显示结果
  - 长按按钮 → 持续录音模式

### 2. 历史记录页面 (History Screen)
- **布局**：列表形式展示对话历史
- **内容**：
  - 时间戳
  - 用户语音识别文本
  - AI 回复内容
- **功能**：
  - 点击单条记录可重播音频
  - 滑动删除单条记录
  - 清空全部历史

### 3. 设置页面 (Settings Screen)
- **配置项**：
  - WebSocket 服务器地址
  - 音频质量选择（低/中/高）
  - 自动发送延迟时长
  - 深色/浅色主题切换
  - 关于应用信息

---

## 🎯 交付标准

### 代码质量
- ✅ 所有代码遵循 Flutter/Dart 官方规范
- ✅ 每个文件顶部添加功能说明注释
- ✅ 关键方法添加文档注释
- ✅ 使用有意义的变量和函数命名

### 功能完整性
- ✅ 所有 UI 元素完整实现
- ✅ 所有动画效果流畅运行
- ✅ WebSocket 连接稳定可用
- ✅ 音频录制功能正常
- ✅ 权限请求流程完善

### 文档要求
- ✅ 提供完整的 `README.md`，包含：
  - 项目介绍
  - 环境要求
  - 安装步骤
  - 配置说明（如何修改 WebSocket 地址）
  - 运行指令
  - 常见问题解答
- ✅ 代码中关键部分添加中文注释

### 测试要求
- ✅ 在真机或模拟器上测试所有功能
- ✅ 确认不同屏幕尺寸下 UI 正常显示
- ✅ 验证网络异常情况下的错误处理

---

## 📝 实现步骤建议

### 第一阶段：项目搭建
1. 创建 Flutter 项目
2. 配置 `pubspec.yaml` 依赖
3. 设置 Android 权限
4. 创建文件结构

### 第二阶段：UI 实现
1. 实现主界面布局
2. 创建中央语音按钮组件
3. 添加底部导航栏
4. 实现动画效果

### 第三阶段：功能集成
1. 实现音频录制服务
2. 集成 WebSocket 通信
3. 添加权限管理
4. 实现状态管理

### 第四阶段：完善功能
1. 实现历史记录功能
2. 实现设置页面
3. 优化错误处理
4. 性能优化

### 第五阶段：测试与文档
1. 功能测试
2. 性能测试
3. 编写 README
4. 代码注释完善

---

## 🔗 参考资源

- Flutter 官方文档：https://flutter.dev/docs
- Material Design 3：https://m3.material.io/
- record 插件文档：https://pub.dev/packages/record
- web_socket_channel 文档：https://pub.dev/packages/web_socket_channel

---

## ⚠️ 注意事项

1. **性能优化**：
   - 音频流传输使用 isolate 避免阻塞 UI 线程
   - 大文件历史记录使用分页加载
   
2. **错误处理**：
   - 网络异常时显示友好提示
   - 麦克风权限被拒绝时引导用户开启
   
3. **用户体验**：
   - 所有异步操作添加 loading 提示
   - 录音时禁用其他交互按钮
   - 添加音频反馈（震动或声音）

---

**复制此提示词，粘贴给任何 AI 编程助手，即可开始构建完整的 Flutter 语音助手项目！**
