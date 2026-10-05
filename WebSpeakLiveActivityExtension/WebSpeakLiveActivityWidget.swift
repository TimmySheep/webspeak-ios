import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WebSpeakLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WebSpeakVoiceLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("语音会话", systemImage: "waveform")
                        .font(.headline)
                    Spacer()
                    connectionStatus(context.state.connectionStatus)
                        .font(.caption.weight(.semibold))
                }

                Text(context.state.channelName)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)

                HStack(spacing: 14) {
                    microphoneStatus(context.state)
                    speakerStatus(context.state.speakerMuted)
                    if context.state.screenShareStatus != .none {
                        screenShareStatus(context.state.screenShareStatus)
                    }
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .padding(16)
            .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            .activityBackgroundTint(Color(red: 0.08, green: 0.10, blue: 0.15))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WebSpeak")
                            .font(.caption.weight(.semibold))
                        Text(context.state.channelName)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            microphoneAction(context)
                            if context.state.connectionStatus != .connected {
                                connectionStatus(context.state.connectionStatus)
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 12) {
                            speakerStatus(context.state.speakerMuted)
                            if context.state.screenShareStatus != .none {
                                screenShareStatus(context.state.screenShareStatus)
                            }
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            } compactTrailing: {
                Image(systemName: context.state.microphoneMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(context.state.microphoneMuted ? Color.red : Color.blue)
                    .accessibilityLabel(context.state.microphoneMuted ? "麦克风静音" : "麦克风开启")
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
                    .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
            }
            .keylineTint(.blue)
        }
    }

    @ViewBuilder
    private func microphoneAction(_ context: ActivityViewContext<WebSpeakVoiceLiveActivityAttributes>) -> some View {
        if context.state.microphoneMode == .toggle {
            Button(intent: ToggleLiveActivityMicrophoneIntent(sessionID: context.attributes.sessionID)) {
                Label(
                    context.state.microphoneMuted ? "开启麦克风" : "静音麦克风",
                    systemImage: context.state.microphoneMuted ? "mic.fill" : "mic.slash.fill"
                )
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(minHeight: 40)
                .background(
                    context.state.microphoneToggleEnabled
                        ? (context.state.microphoneMuted ? Color.blue : Color.red)
                        : Color.gray.opacity(0.45),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!context.state.microphoneToggleEnabled)
            .accessibilityLabel(context.state.microphoneMuted ? "开启麦克风" : "静音麦克风")
            .accessibilityHint(context.state.speakerMuted ? "开启扬声器后才能启用麦克风" : "切换麦克风")
            .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
        } else {
            microphoneStatus(context.state)
                .accessibilityHint("PTT 模式请在 App 内按住说话")
                .environment(\.locale, Locale(identifier: context.state.localeIdentifier))
        }
    }

    @ViewBuilder
    private func connectionStatus(_ status: WebSpeakVoiceLiveActivityAttributes.ContentState.ConnectionStatus) -> some View {
        switch status {
        case .connected:
            Label("语音已连接", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .reconnecting:
            Label("正在重连", systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
        case .connecting:
            Label("语音连接中", systemImage: "ellipsis.circle")
                .foregroundStyle(.orange)
        case .unavailable:
            Label("语音媒体暂不可用", systemImage: "mic.slash.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func microphoneStatus(_ state: WebSpeakVoiceLiveActivityAttributes.ContentState) -> some View {
        if state.microphoneMode == .pushToTalk {
            Label(
                state.pushToTalkActive ? "正在发言" : "PTT 等待",
                systemImage: state.pushToTalkActive ? "mic.fill" : "mic.slash.fill"
            )
            .foregroundStyle(state.pushToTalkActive ? Color.blue : Color.secondary)
        } else {
            Label(
                state.microphoneMuted ? "麦克风静音" : "麦克风开启",
                systemImage: state.microphoneMuted ? "mic.slash.fill" : "mic.fill"
            )
            .foregroundStyle(state.microphoneMuted ? Color.red : Color.blue)
        }
    }

    private func speakerStatus(_ muted: Bool) -> some View {
        Label(
            muted ? "扬声器关闭" : "扬声器开启",
            systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        )
        .foregroundStyle(muted ? Color.secondary : Color.blue)
    }

    @ViewBuilder
    private func screenShareStatus(_ status: WebSpeakVoiceLiveActivityAttributes.ContentState.ScreenShareStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .preparing:
            Label("共享准备中", systemImage: "rectangle.dashed")
                .foregroundStyle(.secondary)
        case .sharing:
            Label("正在共享屏幕", systemImage: "rectangle.on.rectangle")
                .foregroundStyle(.blue)
        case .watching:
            Label("正在观看共享", systemImage: "rectangle.inset.filled")
                .foregroundStyle(.blue)
        }
    }
}
