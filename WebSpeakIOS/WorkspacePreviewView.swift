import SwiftUI

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case voice
    case channels
    case chat
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: "语音"
        case .channels: "频道"
        case .chat: "聊天"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .channels: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left.and.bubble.right"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct WorkspacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: WorkspaceTab = .voice
    @State private var microphoneMuted = false
    @State private var pushToTalkActive = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader

            if horizontalSizeClass == .regular {
                iPadWorkspace
            } else {
                iPhoneWorkspace
            }
        }
        .background {
            BrandBackground()
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 11) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 42, height: 42)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回连接页")

            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("WebSpeak")
                    .font(.headline)
                Text("界面预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "circle.dashed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("未连接")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var iPadWorkspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(title: "工作区")
                    .padding(.horizontal, 13)
                    .padding(.top, 17)
                    .padding(.bottom, 5)

                ForEach(WorkspaceTab.allCases) { tab in
                    sidebarButton(tab)
                }

                Spacer(minLength: 12)

                Label("示例数据，不是实时会话", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 228)
            .frame(maxHeight: .infinity)

            Divider()

            tabContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iPhoneWorkspace: some View {
        TabView(selection: $selectedTab) {
            ForEach(WorkspaceTab.allCases) { tab in
                tabContent(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .tag(tab)
            }
        }
        .tint(.webSpeakBlue)
    }

    private func sidebarButton(_ tab: WorkspaceTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(tab.title, systemImage: tab.symbol)
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .foregroundStyle(selectedTab == tab ? Color.webSpeakBlue : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background {
                    if selectedTab == tab {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.webSpeakBlue.opacity(0.11))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tabContent(_ tab: WorkspaceTab) -> some View {
        switch tab {
        case .voice:
            VoiceActivityPreview(microphoneMuted: $microphoneMuted, pushToTalkActive: $pushToTalkActive)
        case .channels:
            ChannelsPreview()
        case .chat:
            ChatPreview()
        case .settings:
            SettingsPreview()
        }
    }
}

private struct VoiceActivityPreview: View {
    @Binding var microphoneMuted: Bool
    @Binding var pushToTalkActive: Bool

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 13)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PrototypeNotice()

                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "语音活动")
                    HStack(alignment: .firstTextBaseline) {
                        Text("正在频道中")
                            .font(.title2.weight(.bold))
                        Spacer()
                        Text("3 位成员")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(Color.webSpeakBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("夜航语音")
                            .font(.subheadline.weight(.semibold))
                        Text("示例 TeamSpeak 频道")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(15)
                .webSpeakGlassCard(cornerRadius: 19)

                LazyVGrid(columns: columns, spacing: 13) {
                    MemberPreviewCard(name: "阿澈", detail: "正在说话", symbol: "waveform", speaking: true)
                    MemberPreviewCard(name: "北极星", detail: "已连接", symbol: "person.fill", speaking: false)
                    MemberPreviewCard(name: "你", detail: microphoneMuted ? "麦克风已静音" : "你的设备", symbol: microphoneMuted ? "mic.slash.fill" : "mic.fill", speaking: false)
                }

                ScreenSharePreviewCard()

                VStack(spacing: 13) {
                    HStack {
                        Label("语音控制", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("预览")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        PreviewControlButton(
                            title: microphoneMuted ? "开启麦克风" : "静音麦克风",
                            symbol: microphoneMuted ? "mic.fill" : "mic.slash.fill",
                            emphasized: microphoneMuted,
                            action: { microphoneMuted.toggle() }
                        )

                        PreviewControlButton(
                            title: pushToTalkActive ? "按住说话中" : "按住说话",
                            symbol: "hand.tap.fill",
                            emphasized: pushToTalkActive,
                            action: { pushToTalkActive.toggle() }
                        )
                    }
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 21)
            }
            .padding(.horizontal, 18)
            .padding(.top, 15)
            .padding(.bottom, 28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MemberPreviewCard: View {
    let name: String
    let detail: String
    let symbol: String
    let speaking: Bool

    var body: some View {
        VStack(spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(name.prefix(1)))
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.webSpeakBlue)
                    .frame(width: 68, height: 68)
                    .background(Color.webSpeakBlue.opacity(0.11), in: Circle())
                    .overlay {
                        if speaking {
                            Circle().stroke(Color.webSpeakBlue.opacity(0.55), lineWidth: 2)
                                .padding(-4)
                        }
                    }

                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(speaking ? Color.green : Color.secondary, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
            }

            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .webSpeakGlassCard(cornerRadius: 21)
    }
}

private struct ScreenSharePreviewCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("屏幕共享", systemImage: "rectangle.on.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("待接入")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                VStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 27, weight: .light))
                        .foregroundStyle(Color.webSpeakBlue.opacity(0.8))
                    Text("共享开始后会显示在这里")
                        .font(.subheadline.weight(.medium))
                    Text("支持观看与发起共享的原生入口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .frame(minHeight: 145)
        }
        .padding(15)
        .webSpeakGlassCard(cornerRadius: 21)
    }
}

private struct PreviewControlButton: View {
    let title: String
    let symbol: String
    let emphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(emphasized ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(emphasized ? Color.webSpeakBlue : Color.primary.opacity(0.055))
                }
        }
        .buttonStyle(.plain)
        .accessibilityHint("仅切换原型预览状态，不控制麦克风")
    }
}

private struct ChannelsPreview: View {
    private let channels: [(name: String, members: [String], symbol: String)] = [
        ("大厅", ["阿澈", "你"], "waveform"),
        ("夜航语音", ["北极星"], "waveform"),
        ("休息区", [], "moon.zzz"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PrototypeNotice()
                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "频道")
                    Text("语音频道")
                        .font(.title2.weight(.bold))
                }

                VStack(spacing: 0) {
                    ForEach(Array(channels.enumerated()), id: \.offset) { index, channel in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 11) {
                                Image(systemName: channel.symbol)
                                    .foregroundStyle(index == 1 ? Color.webSpeakBlue : Color.secondary)
                                    .frame(width: 22)
                                Text(channel.name)
                                    .font(.subheadline.weight(index == 1 ? .semibold : .medium))
                                Spacer()
                                Text("\(channel.members.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                if index == 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.webSpeakBlue)
                                }
                            }

                            if !channel.members.isEmpty {
                                ForEach(channel.members, id: \.self) { member in
                                    HStack(spacing: 9) {
                                        Circle()
                                            .fill(member == "阿澈" ? Color.green : Color.secondary.opacity(0.55))
                                            .frame(width: 7, height: 7)
                                        Text(member)
                                            .font(.subheadline)
                                        if member == "阿澈" {
                                            Text("正在说话")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.leading, 32)
                                }
                            } else {
                                Text("此频道暂无成员")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 32)
                            }
                        }
                        .padding(16)

                        if index < channels.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .webSpeakGlassCard(cornerRadius: 21)
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct ChatPreview: View {
    private let messages: [(sender: String, time: String, text: String, mine: Bool)] = [
        ("阿澈", "20:41", "今晚的语音测试听起来很清楚。", false),
        ("你", "20:42", "不错，延迟也挺低。", true),
        ("北极星", "20:43", "我去频道列表看一下。", false),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    PrototypeNotice()

                    VStack(alignment: .leading, spacing: 5) {
                        SectionEyebrow(title: "频道聊天 · 示例内容")
                        Text("夜航语音")
                            .font(.title2.weight(.bold))
                    }

                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(message.sender.prefix(1)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(message.mine ? Color.white : Color.webSpeakBlue)
                                .frame(width: 33, height: 33)
                                .background(message.mine ? Color.webSpeakBlue : Color.webSpeakBlue.opacity(0.10), in: Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 7) {
                                    Text(message.sender)
                                        .font(.caption.weight(.semibold))
                                    Text(message.time)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                Text(message.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .webSpeakGlassCard(cornerRadius: 18)
                    }

                    Label("这些是界面样例，不是服务器消息，也不会发送或保存。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 10) {
                TextField("连接后输入消息", text: .constant(""))
                    .disabled(true)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color.primary.opacity(0.05), in: Capsule())

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

private struct SettingsPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                PrototypeNotice()
                VStack(alignment: .leading, spacing: 5) {
                    SectionEyebrow(title: "偏好设置")
                    Text("音频与外观")
                        .font(.title2.weight(.bold))
                }

                VStack(spacing: 0) {
                    SettingsPreviewRow(title: "麦克风", detail: "系统默认输入", symbol: "mic")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "音频输出", detail: "系统路由与耳机", symbol: "speaker.wave.2")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "降噪与 VOX", detail: "根据 iOS 音频能力实现", symbol: "waveform.badge.mic")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "语言", detail: "跟随系统；支持五种语言", symbol: "globe")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "外观", detail: "系统浅色 / 深色", symbol: "circle.lefthalf.filled")
                    Divider().padding(.leading, 54)
                    SettingsPreviewRow(title: "网络诊断", detail: "延迟、丢包与 WebRTC 统计", symbol: "chart.xyaxis.line")
                }
                .webSpeakGlassCard(cornerRadius: 21)

                Label("具体选项会在连接和媒体能力接入后开放。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SettingsPreviewRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(Color.webSpeakBlue)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview("iPhone Workspace") {
    NavigationStack {
        WorkspacePreviewView()
    }
}
