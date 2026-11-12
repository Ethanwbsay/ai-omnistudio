# AI 酒馆 · AI Tavern

一个本地优先的 Flutter AI 应用，将角色聊天、拍照搜题、图片创作和视频生成放在同一个 Android 客户端中。支持配置自己的 OpenAI 兼容 API，并为聊天、图片与视频分别管理模型配置。

当前版本：`1.0.14+15`

## 功能

- **角色聊天**：自定义角色卡、头像、性格、背景、开场白和示例对话；全局用户 Persona；多角色、多会话；SSE 流式回复、停止生成与失败重试。
- **搜题助手**：文字提问、相机拍照、多图上传和裁剪；支持视觉模型分步骤解答与数学公式显示。
- **图片工作台**：文生图、多参考图、整图编辑和局部涂抹遮罩；支持本地图库、预览、导出和提示词复用。
- **视频工作台**：文生视频和单张首帧图生视频；支持火山方舟与 xAI 协议、任务查询恢复、本地播放和导出。
- **API 管理**：保存多个聊天、图片和视频 API 配置，支持图片与视频复用聊天配置。

## 快速开始

### 环境要求

- Flutter stable（本机开发使用 Flutter `3.44.8`）
- Dart `>=3.3.0 <4.0.0`
- Android SDK 37、JDK 17、Android 真机或模拟器

### 运行

```sh
git clone https://github.com/Ethanwbsay/ai-tavern.git
cd ai-tavern
flutter doctor
flutter pub get
flutter run
```

首次打开应用后，进入「API 配置」填写自己的服务地址、API Key 和模型名称。图片与视频功能需在各自工作台中添加对应配置。

`android/local.properties` 是本机 SDK 路径文件，不纳入版本控制；如缺少此文件，请使用 Android Studio 或 Flutter 配置本机 SDK。

### 检查与构建

```sh
flutter analyze
flutter test --concurrency=1
flutter build apk --release --split-per-abi
```

APK 输出到 `build/app/outputs/flutter-apk/`。当前 release 构建使用 debug 签名，仅适合测试；正式发布前请配置自己的应用 ID 和签名。

## API 配置

应用不提供模型账号或额度，需要自行配置有权限和额度的服务商账号。

### 聊天与搜题

使用 OpenAI 兼容的 Chat Completions 接口：

- Base URL 示例：`https://your-api-host/v1`
- 请求路径：`/chat/completions`
- 拍照搜题需要模型支持 `image_url` 图片内容（data URL）
- 角色聊天使用 SSE 流式输出

### 图片工作台

支持 OpenAI 兼容 Images API：文生图使用 `POST /images/generations`，图生图和编辑使用 multipart `POST /images/edits`。结果支持 `data[].b64_json` 和 `data[].url`。最多 16 张参考图，实际数量、尺寸和画质取决于服务商模型。

已取得结果 URL 但下载失败时，请使用「仅重试下载」，避免重复生成。生成 POST 不会自动重试。

### 视频工作台

支持火山方舟和 xAI 视频任务协议，可配置模型、提交路径和查询路径。提交后保存任务 ID，每 5 秒查询一次，最多等待 20 分钟；离开页面后可从「任务与作品」继续查询和下载已有任务。当前未实现多图参考、尾帧、视频编辑或延长。

停止本地请求或删除本地作品不会取消已经提交的云端任务。提交超时且未取得任务 ID 时，应先检查服务商记录，避免重复提交。

## 数据与隐私

- 角色、会话与作品历史保存在应用本机文档目录；图片和视频分别保存在 `image_studio`、`video_studio`。
- API 配置及 Key 使用本机偏好设置保存，尚未接入系统安全密钥存储。
- 调用模型时，输入文字和选择的图片会发送给你配置的 API 服务。
- 构建产物、APK、日志、依赖缓存、本机 SDK 路径和签名文件由 `.gitignore` 排除；本地 `releases/` 中的 APK 不作为源码提交。

## 项目结构

```text
lib/
  main.dart                 应用入口与搜题页面
  tavern_app.dart           角色聊天与首页
  image_studio_page.dart    图片工作台
  video_studio_page.dart    视频工作台
  models/                   数据模型
  services/                 API、流式解析、控制器和本地存储
  widgets/                  公式、遮罩和视频播放器
 test/                      模型、接口、控制器与界面测试
 android/                   Android 原生工程
 windows/                   Windows 桌面工程
docs/usage-and-history.md   原有详细说明与历史修复记录
```

更多协议细节与兼容说明见 [详细使用说明与历史记录](docs/usage-and-history.md)。
