# 原生客户端架构

## 边界与目标

- App 原生支持 iPhone 与 iPad；没有 macOS target，不把 WebView/PWA 作为主界面。
- App 负责 Apple 原生 UI、连接表单、设备偏好、授权说明、会话呈现与平台生命周期。
- WebSpeak 服务继续负责 TeamSpeak 3/6 ServerQuery 会话、频道/成员同步、既有控制协议和屏幕共享信令；未经授权不修改服务端。
- WebSpeak 现有屏幕共享只转发 SDP/ICE 协商，媒体走 WebRTC/ICE 对等链路。客户端不得误将共享媒体转发到网关。

## 连接协议边界

目前静态核对的 WebSpeak 接入流程：

1. `GET /api/public-config` 读取网关公开接入模式与默认目标。
2. `POST /api/join-ticket` 请求一次性连接票据；请求携带与网关同源的 `Origin`。该校验用于沿用现有来源防护，不等于用户身份认证。
3. 连接 `WS(S) /ws/voice?ticket=…`，使用服务端现有 JSON 控制协议。
4. 语音优先使用网关声明可用的 WebRTC/ICE；若网关明确未启用 WebRTC，则使用既有 WebSocket 二进制语音协议（上行 48 kHz 单声道 Int16 PCM、20 ms 一帧；下行按每个成员使用 Apple AudioConverter 解码 Opus）。屏幕共享媒体始终走 WebRTC/ICE P2P，不经过 WebSocket 中继。

服务端协议需由独立的 `GatewayAPI`、`VoiceWebSocketClient` 与容错 `Codable` 模型封装。一次性票据只保存在内存，不能写入日志、偏好或 URL 历史。TLS 正常校验，不得添加忽略证书错误的回退。

## 推荐分层

- `App/`：应用入口、路由、依赖组装。
- `Features/Connection/`：网关发现、连接表单、最近/收藏、错误与重连状态。
- `Features/Voice/`：频道、成员、说话状态、成员操作与 PTT。
- `Features/Chat/`：频道/服务器/私聊与事件列表。网关未提供原生桌面旧聊天记录回放；是否保存本 App 已收到的新消息由独立隐私决策控制。
- `Features/ScreenShare/`：列表、观看与广播状态；当前发送端在 iOS 27+ 使用 ScreenCaptureKit 系统选择器，用户主动选择后才采集；较旧系统发送端尚未实现。媒体走 WebRTC/ICE P2P，网关只转发信令。
- `Features/Settings/`：音频、语言、外观与诊断。
- `Networking/`：HTTP API、WebSocket、JSON 模型和协议测试。
- `Media/`：WebRTC 与旧 WebSocket/Opus 语音适配、`AVAudioSession` 路由和生命周期协调。当前固定依赖 `stasel/WebRTC` `150.0.0`（BSD 3-Clause）；旧音频编解码使用系统 AudioConverter，不新增依赖；构建通过不代表真机媒体验收。
- `Persistence/`：Keychain 凭据/身份、非敏感偏好与用户选择的本地缓存。

UI 只观察会话状态，不拥有长生命周期媒体对象。断线、重连、应用进入后台、音频打断、蓝牙设备变化与系统终止都必须作为显式状态处理；不得承诺 iOS 不允许的绝对后台保活。

## 平台限制与未决项

- iOS 麦克风与屏幕广播需按系统要求授权；当前 iOS 27+ ScreenCaptureKit 发送路径已接入，但待真机验收，iOS 17–26 的系统级广播尚未实现。
- Web UI 的“桌面窗口/标签页伴奏”不是 iPhone/iPad 的直接等价能力；当前屏幕广播不采集系统音频，不宣称与网页端伴奏等价。
- WebSpeak 网关不会读取或回填 TeamSpeak 桌面客户端已有的本地聊天历史。
- TeamSpeak TS3/TS6 语音兼容、系统 Opus 转换器在 iOS 真机上的逐帧表现、原生 WebRTC 与后台音频策略尚未端到端验证。
