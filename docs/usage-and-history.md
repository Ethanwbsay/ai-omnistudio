# AI 万象工坊（Flutter Android）

一个本地优先的 AI 角色聊天应用：你可以配置多个 OpenAI 兼容 API，创建角色卡和全局用户 Persona，并以流式方式进行沉浸式对话。

首页提供角色聊天、搜题助手、图片工作台和视频工作台。图片与视频功能分别使用独立的模型配置。

## 视频工作台

进入首页右上角的“视频工作台”，打开“视频 API 配置”，选择协议并填写自己的 API Key。已内置官方地址、模型 ID 和任务路径：

| 协议 | Base URL | 预置模型 | 提交 / 查询 |
| --- | --- | --- | --- |
| 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-seedance-2-5-260628` | `POST /contents/generations/tasks` / `GET /contents/generations/tasks/{id}` |
| xAI | `https://api.x.ai/v1` | `grok-imagine-video` | `POST /videos/generations` / `GET /videos/{id}` |

- 支持文生视频和单张首帧图生视频，设置时长、比例、分辨率与声音；生成后自动下载 MP4，可播放、拖动进度、暂停、导出和复用提示词。
- Seedance 2.5 时长为 4–30 秒，分辨率为 480p / 720p / 1080p；图生视频自动发送 `ratio: adaptive`，保持首帧图片比例。也可填写方舟的其他 Seedance 模型 ID 或 `ep-…` 接入点；其他模型及无法判定版本的接入点保守提供 4–15 秒选项，实际能力以账号和模型为准。
- Grok Imagine Video 时长为 1–15 秒，支持 480p / 720p；配置页可选 `grok-imagine-video-1.5`，增加 1080p。选择“声音：模型默认”时不发送 `generate_audio`。
- 可保存多个视频 API 配置、复用聊天 API 的地址与 Key、自定义相对任务路径。网关必须实现所选方舟或 xAI 协议，修改模型名称或路径不等于兼容任意视频 API。
- 本地图片转换为 PNG 后以 data URI 上传，单图小于 20 MB；Seedance 首帧宽高至少 300 像素、比例在 0.4–2.5 之间。当前未实现多图参考、尾帧、视频编辑和视频延长。
- 提交后立即保存任务 ID，每 5 秒查询一次，最多等待 20 分钟。暂停查询或离开页面后，服务端任务仍可能继续；返回“任务与作品”点“继续查询 / 下载”即可恢复，恢复只查询已有任务，不再次提交生成。网络或下载失败也可继续查询刷新下载地址。
- API Key 保存在本机偏好设置；任务与视频保存在应用文档目录 `video_studio`，任务记录不包含 Key。普通媒体下载不发送 API Key；已核验的偏爱 AI 同源代理媒体接口需要鉴权，跳转到外部 CDN 时不发送 Key。采用流式写入，大小上限 300 MB，失败或暂停时清理临时文件。
- 对 `https://chat.yueyued.top/api/openai/v1` 自动适配偏爱 AI 网页代理：查询附带 `grok_model`，新任务使用固定的 `x-paiai-client-id`，支持嵌套结果、`completed` 等状态和相对媒体路径。恢复任务使用创建时的模型与客户端标识；旧版记录未携带客户端标识时保持原来的请求身份，补充模型路由后继续查询，不重新提交。实现依据为[网站公开请求代码](https://chat.yueyued.top/_next/static/chunks/app/page-55fc95f7643a094f.js)。
- 服务商返回的视频链接有有效期，请及时完成下载。删除本地任务和视频不会取消云端任务。提交超时未返回任务 ID 时，请先查看服务商控制台，确认是否已提交，避免重复生成。

接口依据：[Seedance 2.5 官方教程](https://docs.volcengine.com/docs/ark/seedance-2-5)、[方舟创建任务](https://docs.volcengine.com/docs/ark/create-video-generation-task-api)、[方舟查询任务](https://docs.volcengine.com/docs/ark/get-video-generation-task-api)、[Grok 视频生成](https://docs.x.ai/developers/model-capabilities/video/generation)、[Grok 图生视频](https://docs.x.ai/developers/model-capabilities/video/image-to-video)。模型需由服务商账号开通且有可用额度；应用不会预置账号或 Key。

## 图片工作台

- 文生图：输入提示词，选择图片 API、输出比例和分辨率、画质和数量；支持 1:1、3:2、2:3、16:9、9:16、4:3、3:4、5:4、4:5、16:10、10:16、21:9、9:21、2:1、1:2、7:4、4:7；
- 图生图：从相册一次选择多张参考图，也可继续添加图片或拍照，输入转换要求；
- 图片编辑：上传图片进行整图编辑，或涂抹局部区域生成透明 PNG 遮罩，支持撤销和清除；
- 生成结果自动保存到本地图库，支持缩放预览、导出图片、复制提示词、用作参考图和继续编辑；
- 图片 API 可保存多个配置，也可复用聊天 API 的地址和 Key，再单独填写图片模型 ID。

进入首页的“图片工作台”，打开右上角“图片 API 配置”，填写服务商的 Base URL、API Key 和图片模型名称。Base URL 填到版本前缀（例如 `https://your-host/v1`），接口选项可设置相对请求路径。

当前支持 **OpenAI 兼容 Images API**：文生图使用 JSON `POST /images/generations`，图生图和编辑使用 multipart `POST /images/edits`。单图上传字段为 `image`，多图使用重复的 `image[]` 字段，按页面显示顺序发送；局部编辑额外上传 `mask`，作用于第一张底图。参考图统一转为 PNG，遮罩与底图同尺寸，透明区域对应涂抹位置。结果支持 `data[].b64_json` 和 `data[].url`，URL 图片会立即下载到本地，下载时不发送 API Key。[OpenAI Docs 图片接口参考](https://developers.openai.com/api/reference/resources/images/methods/edit)。

参考图最多 16 张，单张 PNG 不超过 50 MB、合计不超过 100 MB。缩略图支持移除、放大和“设为底图”；新增辅助参考图保留当前遮罩，切换或移除底图会清除遮罩。具体支持的参考图数量和分辨率以服务商模型为准，模型仅支持单图时请选择一张。尺寸选项按实际像素标注比例（例如 `1792 × 1024` 为 `7:4`，`1536 × 864` 为 `16:9`）。

当前版本：**1.0.14+15**（Android versionName `1.0.14`；工程构建号 `15`，Flutter arm64 分包的实际 versionCode 为 `2015`）。本仓库只包含源码，不附 APK；构建命令和安装包输出目录见项目根目录的 README。

1.0.14 兼容长 SSE 最终图片的非标准换行和结束方式：只对明确的 `b64_json` / `data:image/...;base64,...` 字段合并物理换行，保留其他 JSON 字符串与空白；接受命名最终事件的连续数据行和裸续行；最终 JSON 暂不完整时保留片段继续读取，新事件到来时不拼接旧的损坏事件。EOF 缺少最后空行时，仅接收完整合法的最终 JSON，截断图片仍不入库。失败诊断增加事件字符数、JSON 错误位置和数据行数，不输出原始响应、图片、Key 或签名链接。验证包含超过 2,587,972 字符的真实 PNG，分段流式接收后解码、保存并重开图库校验字节和尺寸；没有发送真实付费生成。用户截图确认 HTTP 200 且收到 2,587,972 字节，但没有原始事件，尚不能确认是换行、截断或服务端错误事件导致其故障。提供修复与更准确诊断，不将模拟通过当成用户请求已恢复。

1.0.13 修复流式解析过早终止：SSE 的 `data` 可以是任意文本，旧版把空 `data:` 和文本保活当成 JSON，立即报“事件内容不是完整 JSON”并关闭请求。现在忽略空数据、命名进度事件和非图片消息，继续等待最终图片；未命名事件中的完整 Images `data` 结果也可接收。最终图片事件必须包含完整 JSON 和明确的图片字段；预览、截断事件和错误不会被保存为作品。结束仍无结果时显示 HTTP 状态、接收字节和跳过事件数量，不复制原始响应或图片内容。已用旧版失败、新版通过的保活用例，以及实际 HTTP 分块接收和 PNG 解码、落盘、重新读取历史验证；这些模拟验证无法证明用户账号的实际响应就是上述保活格式。用户已确认原配置包含 `/v1`，地址缺失不是其已扣费请求的原因。[SSE 格式依据](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation)。

1.0.12 针对梭子蟹增加流式 Images 接收：旧配置默认“自动”，`suoxie.codes` 的 GPT 图片模型发送 `stream=true` 和 `partial_images=1`；支持保活、分段 UTF-8、预览与最终事件、多张最终结果，只保存完成事件中的图片，收到所需最终结果后不再等连接关闭。服务商忽略流式参数返回普通 JSON 时也可接收。“接口选项 → 接收方式”可手动选普通 JSON 或流式，不支持流式时不会自动重发付费请求。对于梭子蟹的裸域名 Base URL 和默认 `images/...` 路径自动补 `/v1`，保留已填写的版本前缀和自定义路径；无 Key 的路由验证中，`POST /images/edits` 返回 404，`POST /v1/images/edits` 返回鉴权要求（401），没有调用模型。协议依据：[Images 编辑流式示例](https://developers.openai.com/api/reference/resources/images/methods/edit)、[服务端流式实现](https://github.com/Wei-Shaw/sub2api/blob/main/backend/internal/service/openai_images_responses.go)。本地模拟验证不代表用户账号下的真实请求已成功；197 秒、0 字节的截图表明未收到响应头，无法仅凭扣费记录确定服务端或移动网络在哪一段丢失返回。

1.0.11 对网关响应接收做了兼容处理：跳过 JSON 前的空白保活数据，收到完整合法 JSON 后结束接收，不再依赖连接关闭；不接受截断的 JSON 或 Base64。请求使用 `Accept-Encoding: identity`，兼容服务商返回的 `data:image/...` 内嵌图片 URL。连接异常显示发生阶段、HTTP 状态、已接收字节数、异常类型和脱敏原因；不会显示 Key 或签名 URL，也不会自动重发生成 POST。梭子蟹页面使用的 Sub2API 公共源码包含非流式图片的空白保活和内嵌 URL 返回路径（[保活实现](https://github.com/Wei-Shaw/sub2api/blob/main/backend/internal/service/openai_images_json_keepalive.go)、[内嵌结果实现](https://github.com/Wei-Shaw/sub2api/blob/main/backend/internal/service/openai_images_direct.go)）；这证明需要兼容这些返回行为，不能据此断定用户某次请求的故障原因。

图片请求的生成与下载使用独立超时：生成默认等待 15 分钟，旧配置自动使用这个默认值；“图片 API 配置 → 接口选项”可设置 1–30 分钟，每张结果图片另有 3 分钟下载时间。页面显示等待生成、接收结果、下载结果和本地保存的阶段及已等待时间。HTTP 408/504/524 网关超时与应用等待超时分开提示，响应中存在请求 ID 时显示供排查使用。生成 POST 不会自动重试。

服务端已返回 URL、但下载失败或超时时，会保留当前页面中的待下载链接并保存已成功取得的图片。“仅重试下载”只请求已有图片 URL，不重新调用模型；未处理完待下载图片前禁止再次生成，也可确认“放弃下载”。待下载链接只保存在当前页面内存中，请完成下载后再离开页面或关闭应用；链接过期后无法保证恢复。未收到响应的旧超时请求无法从应用恢复，请先查看服务商记录中的生成结果，避免重复调用。

尺寸、画质和返回格式选择“模型默认”时不会发送对应参数；不同模型支持的尺寸、画质、生成数量和遮罩能力各有不同，请按服务商文档选择。`n` 默认发送 1。只支持 Chat Completions、Gemini 原生协议、异步任务轮询或其他自定义 JSON 协议的图片服务暂不兼容，修改请求路径不能改变协议。停止生成会关闭本地请求，服务端可能已经开始处理。

配置保存在本机偏好设置，图片和历史保存在应用文档目录的 `image_studio` 中；“保存图片”可通过系统文件选择器导出到指定位置。未填写有效的图片模型账号前不会发起真实生成请求。

## AI 角色聊天

- 创建角色并设置头像、简介、性格、背景、开场白、示例对话和补充提示词；
- 保存多个 OpenAI 兼容 API 配置，并为每个角色单独选择；
- 配置全局用户 Persona；
- SSE 流式回复，支持停止生成、失败重试、多个会话和清空会话；
- 角色和会话数据保存在本地应用文档目录中。

## 保留的搜题模块

原有搜题功能支持：

- 文字输入题目；
- 相机拍照或从相册上传题目；
- 调用支持视觉的 OpenAI 兼容聊天接口输出详细、分步骤解答；
- 保留当前会话上下文，可继续追问；
- 本地设置 API Base URL、API Key 和模型名称。

## 启动

1. 安装 Flutter SDK（Dart `>=3.3`）并配置 Android SDK。
2. 在项目根目录执行：

   ```powershell
   flutter pub get
   flutter test
   flutter run
   ```

3. 首次打开应用，先进入“API 配置”添加自己的 OpenAI 兼容服务，再创建角色并开始聊天。

Base URL 通常填写 `https://your-host/v1`，应用会请求 `.../chat/completions`。拍照搜题需要服务端模型接受 Chat Completions 的 `image_url`（data URL）内容。

> API Key 会存到本机应用偏好设置；正式发布前建议改用 `flutter_secure_storage` 等 Android Keystore 安全存储方案。

## VS Code 测试

工程已包含 `.vscode/launch.json`。在 VS Code 打开本目录后，选择 **AI 万象工坊（Flutter）**，连接 Android 手机或启动模拟器，再按 `F5`。也可在终端运行：

```powershell
flutter doctor
flutter pub get
flutter test
flutter run
```
