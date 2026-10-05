import SwiftUI
import ImageIO
import UIKit

private enum WorkspaceSection: String, CaseIterable, Identifiable {
    case voice
    case channels
    case chat
    case screenShares
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: "语音"
        case .channels: "频道与成员"
        case .chat: "聊天"
        case .screenShares: "屏幕共享"
        case .settings: "诊断与设置"
        }
    }

    var symbol: String {
        switch self {
        case .voice: "waveform"
        case .channels: "point.3.connected.trianglepath.dotted"
        case .chat: "bubble.left.and.bubble.right"
        case .screenShares: "rectangle.on.rectangle"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct VoiceWorkspaceView: View {
    @ObservedObject var model: WebSpeakAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: WorkspaceSection = .voice

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadWorkspace
            } else {
                iPhoneWorkspace
            }
        }
        .background(BrandBackground())
        .alert("会话提示", isPresented: Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.clearOperationError() } }
        )) {
            Button("好", role: .cancel) { model.clearOperationError() }
        } message: {
            Text(model.operationError ?? "")
        }
        .onChange(of: model.selectedChatScope) { _, scope in
            if scope == .privateMessage { selectedSection = .chat }
        }
    }

    private var iPadWorkspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                SectionEyebrow(title: "工作区")
                    .padding(.horizontal, 13)
                    .padding(.top, 17)
                    .padding(.bottom, 5)

                ForEach(WorkspaceSection.allCases) { section in
                    sidebarButton(section)
                }

                Spacer(minLength: 12)

                Label("消息只保存在当前会话内存", systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 10)
            .frame(width: 230)
            .frame(maxHeight: .infinity)

            Divider()
            sectionContent(selectedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var iPhoneWorkspace: some View {
        TabView(selection: $selectedSection) {
            ForEach(WorkspaceSection.allCases) { section in
                sectionContent(section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(section)
            }
        }
        .tint(.webSpeakBlue)
    }

    private func sidebarButton(_ section: WorkspaceSection) -> some View {
        Button {
            selectedSection = section
        } label: {
            Label(section.title, systemImage: section.symbol)
                .font(.subheadline.weight(selectedSection == section ? .semibold : .regular))
                .foregroundStyle(selectedSection == section ? Color.webSpeakBlue : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .frame(height: 46)
                .background {
                    if selectedSection == section {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.webSpeakBlue.opacity(0.11))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionContent(_ section: WorkspaceSection) -> some View {
        switch section {
        case .voice:
            VoiceStatusView(model: model)
        case .channels:
            ChannelMemberListView(model: model)
        case .chat:
            ChatSessionView(model: model)
        case .screenShares:
            ScreenShareDiscoveryView(model: model)
        case .settings:
            SessionSettingsView(model: model)
        }
    }
}

private struct VoiceStatusView: View {
    @ObservedObject var model: WebSpeakAppModel
    @State private var showingAwayMessageEditor = false
    @State private var awayMessageDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.currentChannel?.name ?? "语音")
                            .font(.largeTitle.weight(.bold))
                        Text("\(model.currentChannelMembers.count) 位成员")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                    awayStatusMenu
                }

                if !model.whisperTargetIDs.isEmpty {
                    VStack(spacing: 10) {
                        Toggle("对已选目标启用私语", isOn: Binding(
                            get: { model.whisperActive },
                            set: { model.setWhisperActive($0) }
                        ))
                        .font(.subheadline)
                        .tint(.webSpeakBlue)
                        .disabled(model.isWhisperPushToTalkBusy)

                        Text(model.isWhisperPushToTalkActive ? "正在向私语目标发送 · 松开结束" : "按住只向私语目标说话")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(model.isWhisperPushToTalkActive ? Color.white : Color.webSpeakBlue)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                model.isWhisperPushToTalkActive ? Color.green : Color.webSpeakBlue.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in model.beginWhisperPushToTalk() }
                                    .onEnded { _ in model.endWhisperPushToTalk() }
                            )
                            .accessibilityElement()
                            .accessibilityLabel("按住向私语目标说话")
                            .accessibilityValue(model.isWhisperPushToTalkActive ? "正在私语；松开结束" : "已停止")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { model.setWhisperActive(!model.whisperActive) }
                            .disabled(!model.isVoiceMediaConnected || !model.canEnableMicrophone || model.speakerMuted || model.isPushToTalkActive || model.isWhisperPushToTalkBusy)
                    }
                    .padding(14)
                    .webSpeakGlassCard(cornerRadius: 17)
                }

                if !model.isVoiceMediaConnected && !model.isVoiceMediaStarting {
                    Button {
                        model.retryVoiceMedia()
                    } label: {
                        Label("重试语音连接", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.phase != .connected)
                }

                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Label("当前频道成员", systemImage: "person.2")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(model.currentChannelMembers.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if model.currentChannelMembers.isEmpty {
                        ContentUnavailableView("暂无成员信息", systemImage: "person.2.slash")
                            .frame(minHeight: 120)
                    } else {
                        ForEach(model.currentChannelMembers) { member in
                            MemberSummaryRow(
                                member: member,
                                speaking: model.speakingClientIDs.contains(member.id),
                                sharingScreen: model.isMemberSharingScreen(member)
                            )
                        }
                    }
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 21)

                if model.phase == .reconnecting, let error = model.connectionError {
                    StatusCard(title: "连接正在恢复", detail: error, symbol: "arrow.trianglehead.2.clockwise", color: .orange)
                }
            }
            .padding(18)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            voiceControlBar
        }
        .alert("设置离开状态", isPresented: $showingAwayMessageEditor) {
            TextField("离开原因（可选）", text: $awayMessageDraft)
            Button("设为离开") { model.setAway(true, message: awayMessageDraft) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("最多 200 个字符；其他成员将看到“离开（原因）”。")
        }
        .onDisappear {
            model.endWhisperPushToTalk()
            model.endPushToTalk()
        }
    }

    private var awayStatusMenu: some View {
        Menu {
            Button {
                model.setAway(false)
            } label: {
                Label("在线", systemImage: "person.fill")
            }
            Button {
                awayMessageDraft = model.awayMessage
                showingAwayMessageEditor = true
            } label: {
                Label("设置离开状态", systemImage: "moon.zzz")
            }
        } label: {
            Label(model.isAway ? "离开" : "在线", systemImage: model.isAway ? "moon.zzz.fill" : "person.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isAway ? Color.orange : Color.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background((model.isAway ? Color.orange : Color.green).opacity(0.10), in: Capsule())
        }
        .accessibilityLabel(model.isAway ? "当前状态：离开" : "当前状态：在线")
        .accessibilityHint("更改在线状态或设置离开原因")
    }

    private var voiceControlBar: some View {
        HStack(spacing: 12) {
            microphoneControl
            speakerControl
            disconnectControl
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var disconnectControl: some View {
        Button(role: .destructive) {
            model.disconnect()
        } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.body.weight(.medium))
                .frame(width: 44, height: 48)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel("断开 TeamSpeak 连接")
    }

    @ViewBuilder
    private var microphoneControl: some View {
        if model.microphoneControlMode == .pushToTalk {
            Button {} label: {
                Label(
                    model.isPushToTalkActive
                        ? "正在说话 · 松开结束"
                        : (model.speakerMuted ? "扬声器关闭" : "按住说话"),
                    systemImage: model.isPushToTalkActive ? "mic.fill" : "mic"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.speakerMuted ? .red : .webSpeakBlue)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in model.beginPushToTalk() }
                    .onEnded { _ in model.endPushToTalk() }
            )
            .disabled(!model.isVoiceMediaConnected || !model.canEnableMicrophone || model.speakerMuted || model.isWhisperPushToTalkBusy)
            .accessibilityLabel("按住说话")
            .accessibilityValue(model.isPushToTalkActive ? "正在说话，松开结束" : "麦克风已静音")
            .accessibilityHint("按住按钮发言，松开后自动静音")
            .accessibilityAction {
                if model.isPushToTalkActive {
                    model.endPushToTalk()
                } else {
                    model.beginPushToTalk()
                }
            }
        } else {
            Button {
                model.setMicrophoneMuted(!model.microphoneMuted)
            } label: {
                Label(
                    model.microphoneMuted ? "开启麦克风" : "静音麦克风",
                    systemImage: model.microphoneMuted ? "mic.slash.fill" : "mic.fill"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.microphoneMuted ? .red : .webSpeakBlue)
            .disabled(!model.isVoiceMediaConnected || !model.canEnableMicrophone || model.speakerMuted || model.isWhisperPushToTalkBusy)
            .accessibilityHint(model.speakerMuted ? "开启扬声器后才能启用麦克风" : "切换麦克风静音状态")
        }
    }

    private var speakerControl: some View {
        Button {
            model.setSpeakerMuted(!model.speakerMuted)
        } label: {
            Label(
                model.speakerMuted ? "开启扬声器" : "关闭扬声器",
                systemImage: model.speakerMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.speakerMuted ? .red : .webSpeakBlue)
        .accessibilityHint("仅在本机静音或恢复频道语音播放，不改变系统音量或耳机路由")
    }
}

private struct ChannelMemberListView: View {
    @ObservedObject var model: WebSpeakAppModel
    @State private var searchText = ""

    private var passwordPromptBinding: Binding<VoiceChannel?> {
        Binding(
            get: { model.channelPasswordRequest },
            set: { value in
                if value == nil { model.cancelChannelPasswordRequest() }
            }
        )
    }

    private var visibleChannels: [VoiceChannel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.channels }
        return model.channels.filter { channel in
            channel.name.localizedCaseInsensitiveContains(query)
                || (channel.description?.localizedCaseInsensitiveContains(query) ?? false)
                || (channel.members?.contains(where: { $0.nickname.localizedCaseInsensitiveContains(query) }) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("频道与成员")
                    .font(.largeTitle.weight(.bold))

                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索频道或成员", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 46)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if model.channels.isEmpty {
                    ContentUnavailableView("正在等待频道目录", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(minHeight: 220)
                } else if visibleChannels.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(minHeight: 200)
                } else {
                    ForEach(visibleChannels) { channel in
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                model.switchChannel(channel)
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "waveform.path")
                                        .foregroundStyle(channel.id == model.currentChannel?.id ? Color.webSpeakBlue : Color.secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(channel.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if let description = channel.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Text("\(channel.members?.count ?? 0)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if channel.id == model.currentChannel?.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.webSpeakBlue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isSwitchingChannel)
                            .accessibilityHint("直接切换到此频道；如果需要密码会提示输入")

                            let matchingMembers = (channel.members ?? []).filter { member in
                                searchText.isEmpty || member.nickname.localizedCaseInsensitiveContains(searchText)
                            }
                            if !matchingMembers.isEmpty {
                                ForEach(matchingMembers) { member in
                                    MemberActionRow(member: member, model: model)
                                        .padding(.leading, 29)
                                }
                            }
                        }
                        .padding(15)
                        .webSpeakGlassCard(cornerRadius: 19)
                        .padding(.leading, CGFloat(channelDepth(channel)) * 13)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .sheet(item: passwordPromptBinding) { channel in
            ChannelJoinSheet(channel: channel, model: model)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func channelDepth(_ channel: VoiceChannel) -> Int {
        var depth = 0
        var parentID = channel.parentID
        var visited: Set<String> = [channel.id]
        while parentID != "0", let parent = model.channels.first(where: { $0.id == parentID }), visited.insert(parent.id).inserted {
            depth += 1
            parentID = parent.parentID
        }
        return min(depth, 6)
    }
}

private struct ChannelJoinSheet: View {
    let channel: VoiceChannel
    @ObservedObject var model: WebSpeakAppModel
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("加入频道") {
                    LabeledContent("频道", value: channel.name)
                    SecureField("频道密码（如需要）", text: $password)
                        .textInputAutocapitalization(.never)
                }

                if let error = model.channelPasswordError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        model.switchChannel(channel, password: password)
                    } label: {
                        HStack {
                            if model.isSwitchingChannel { ProgressView() }
                            Text("加入频道")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(password.isEmpty || model.isSwitchingChannel)
                }
            }
            .navigationTitle("切换频道")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.isSwitchingChannel)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.cancelChannelPasswordRequest() }
                        .disabled(model.isSwitchingChannel)
                }
            }
        }
    }
}

private struct MemberActionRow: View {
    let member: VoiceMember
    @ObservedObject var model: WebSpeakAppModel
    @State private var showingVolumeControl = false

    var body: some View {
        HStack(spacing: 8) {
            MemberAvatarView(member: member, size: 28)
            Circle()
                .fill(member.isSelf == true ? Color.webSpeakBlue : Color.secondary.opacity(0.55))
                .frame(width: 7, height: 7)
            Text(member.nickname)
                .font(.subheadline)
                .lineLimit(1)
            if member.away == true {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("离开")
            }
            if member.inputMuted == true {
                Image(systemName: "mic.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("麦克风静音")
            }
            Spacer(minLength: 0)
            if member.isSelf != true {
                Menu {
                    Button("发送私聊", systemImage: "bubble.left") {
                        model.privateRecipientID = member.id
                        model.selectedChatScope = .privateMessage
                    }
                    Button("发送 Poke", systemImage: "hand.tap") {
                        model.sendPoke(to: member.id)
                    }
                    Button(
                        model.whisperTargetIDs.contains(member.id) ? "移除私语目标" : "设为私语目标",
                        systemImage: "ear"
                    ) {
                        model.setWhisperTarget(member.id, enabled: !model.whisperTargetIDs.contains(member.id))
                    }
                    Menu("移动成员", systemImage: "arrowshape.turn.up.right") {
                        ForEach(model.channels) { target in
                            Button(target.name) { model.moveMember(member.id, to: target) }
                        }
                    }
                    Button("成员音量", systemImage: "speaker.wave.2") {
                        showingVolumeControl = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel("\(member.nickname) 的操作")
                .sheet(isPresented: $showingVolumeControl) {
                    MemberVolumeSheet(member: member, model: model)
                        .presentationDetents([.height(240)])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
}

private struct MemberVolumeSheet: View {
    let member: VoiceMember
    @ObservedObject var model: WebSpeakAppModel
    @Environment(\.dismiss) private var dismiss

    private var volume: Binding<Double> {
        Binding(
            get: { model.memberVolume(for: member) },
            set: { model.setMemberVolume(member, volume: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.nickname)
                        .font(.title3.weight(.semibold))
                    Text("此偏好在本機保存；0% 靜音，100% 為標準音量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: volume, in: 0 ... 4, step: 0.05)
                        .tint(.webSpeakBlue)
                    Text("\(Int(volume.wrappedValue * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }

                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(20)
            .navigationTitle("成员音量")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
        }
    }
}

private struct MemberSummaryRow: View {
    let member: VoiceMember
    let speaking: Bool
    let sharingScreen: Bool

    private var presenceText: Text {
        if member.away == true {
            let reason = member.awayMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reason.isEmpty ? Text("离开") : Text("离开") + Text(verbatim: "（\(reason)）")
        }
        return Text(speaking ? "正在说话" : "在线")
    }

    var body: some View {
        HStack(spacing: 11) {
            MemberAvatarView(member: member, size: 39)
                .overlay {
                    if speaking {
                        Circle().stroke(Color.green, lineWidth: 2).padding(-3)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.nickname)
                        .font(.subheadline.weight(.medium))
                    if member.isSelf == true {
                        Text("你")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    presenceText
                        .foregroundStyle(speaking && member.away != true ? Color.green : Color.secondary)
                    if sharingScreen {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Label("屏幕共享", systemImage: "rectangle.on.rectangle")
                            .foregroundStyle(Color.webSpeakBlue)
                    }
                }
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            if member.inputMuted == true {
                Image(systemName: "mic.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("麦克风静音")
            }
            if member.outputMuted == true {
                Image(systemName: "speaker.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("扬声器静音")
            }
        }
        .padding(.vertical, 5)
    }
}

private struct MemberAvatarView: View {
    let member: VoiceMember
    let size: CGFloat

    private var decodedImage: UIImage? {
        guard let avatar = member.avatar,
              avatar.utf8.count <= 360 * 1024,
              let separator = avatar.firstIndex(of: ",")
        else {
            return nil
        }

        let metadata = avatar[..<separator].lowercased()
        guard ["data:image/png;base64", "data:image/jpeg;base64", "data:image/gif;base64", "data:image/webp;base64"].contains(metadata) else {
            return nil
        }
        let encoded = avatar[avatar.index(after: separator)...]
        guard let data = Data(base64Encoded: String(encoded)), data.count <= 256 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    var body: some View {
        Group {
            if let decodedImage {
                Image(uiImage: decodedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(member.nickname.prefix(1)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(member.isSelf == true ? .white : .webSpeakBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(member.isSelf == true ? Color.webSpeakBlue : Color.webSpeakBlue.opacity(0.10))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

private struct ChatSessionView: View {
    @ObservedObject var model: WebSpeakAppModel
    @State private var draft = ""

    private var filteredMessages: [ChatMessage] {
        model.chatMessages.filter { message in
            guard message.scope == model.selectedChatScope else { return false }
            if message.scope == .privateMessage {
                guard let recipient = model.privateRecipientID else { return false }
                return message.conversationId == String(recipient)
            }
            if message.scope == .channel, let target = message.targetId, let current = model.currentChannel?.id {
                return target == current
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("聊天")
                .font(.largeTitle.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)

            Picker("聊天范围", selection: $model.selectedChatScope) {
                ForEach(ChatScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if filteredMessages.isEmpty {
                ContentUnavailableView(
                    "当前会话还没有消息",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("只显示本次连接后由网关送达的内容。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 11) {
                            ForEach(filteredMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: filteredMessages.count) { _, _ in
                        if let last = filteredMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if model.selectedChatScope == .privateMessage {
                HStack(spacing: 9) {
                    Label("私聊对象", systemImage: "person.crop.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("私聊对象", selection: $model.privateRecipientID) {
                        Text("选择在线成员").tag(Optional<Int>.none)
                        ForEach(model.members.filter { $0.isSelf != true }) { member in
                            Text(member.nickname).tag(Optional<Int>.some(member.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("私聊对象")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }

            HStack(spacing: 10) {
                TextField("输入消息…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .onSubmit(send)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 31))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.webSpeakBlue)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("发送消息")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.sendChat(text, scope: model.selectedChatScope, recipientID: model.privateRecipientID)
        draft = ""
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if message.isSelf { Spacer(minLength: 28) }
            VStack(alignment: message.isSelf ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(message.senderName)
                        .font(.caption.weight(.semibold))
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(message.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(message.isSelf ? Color.webSpeakBlue.opacity(0.13) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !message.isSelf { Spacer(minLength: 28) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScreenShareDiscoveryView: View {
    @ObservedObject var model: WebSpeakAppModel
    @State private var showingFullscreen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("屏幕共享")
                    .font(.largeTitle.weight(.bold))

                StatusCard(
                    title: "实时发现已接入",
                    detail: "列表与协商信令通过 WebSpeak 网关；画面媒体走 WebRTC/ICE P2P，不经网关中继。",
                    symbol: "dot.radiowaves.left.and.right",
                    color: .green
                )

                if let publisher = model.screenSharePublisherSession {
                    ScreenSharePublisherStatusView(session: publisher, model: model)
                } else if model.isScreenShareStarting {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在準備屏幕共享…")
                            .font(.subheadline)
                        Spacer()
                        Button("取消") { model.cancelScreenShareStart() }
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(14)
                    .webSpeakGlassCard(cornerRadius: 17)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            model.startScreenShare()
                        } label: {
                            Label("共享本机屏幕", systemImage: "record.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.phase != .connected)

                        Text("仅 iOS 27 及以上支持系统屏幕采集。选择整个屏幕后，iOS 的 screen-capture 后台模式允许离开 App 后继续采集；系统仍可因用户停止、权限或资源策略结束共享。本版本不共享系统音频。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .webSpeakGlassCard(cornerRadius: 17)
                }

                if model.screenShares.isEmpty {
                    ContentUnavailableView("当前频道没有共享", systemImage: "rectangle.on.rectangle.slash")
                        .frame(minHeight: 170)
                } else {
                    ForEach(model.screenShares) { stream in
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(spacing: 11) {
                                Image(systemName: "rectangle.on.rectangle")
                                    .font(.title3)
                                    .foregroundStyle(Color.webSpeakBlue)
                                    .frame(width: 43, height: 43)
                                    .background(Color.webSpeakBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stream.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(stream.ownerNickname) · \(stream.source == "teamspeak" ? "TeamSpeak 原生共享" : "WebSpeak 共享")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }

                            HStack(spacing: 14) {
                                Label("\(stream.viewerCount) 位观众", systemImage: "person.2")
                                if stream.audio { Label("含音频", systemImage: "speaker.wave.2") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let viewers = stream.viewers, !viewers.isEmpty {
                                Label(viewers.suffix(5).map(\.nickname).joined(separator: " · "), systemImage: "person.crop.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .accessibilityLabel("正在观看：\(viewers.suffix(5).map(\.nickname).joined(separator: "、"))")
                            }

                            if model.screenSharePublisherSession?.stream.streamId == stream.streamId {
                                Text("此设备正在共享。接收端将通过 WebRTC/ICE 与此设备建立 P2P 连接。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if model.activeScreenShare?.streamId == stream.streamId,
                               let viewer = model.screenShareViewerSession
                            {
                                ZStack(alignment: .bottomLeading) {
                                    ScreenShareVideoView(track: viewer.videoTrack)
                                        .aspectRatio(16 / 9, contentMode: .fit)
                                        .frame(maxWidth: .infinity)
                                        .background(.black, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                                    if viewer.videoTrack == nil {
                                        Text(viewer.status)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.white)
                                            .padding(11)
                                            .background(.black.opacity(0.6), in: Capsule())
                                            .padding(11)
                                    }
                                }

                                if stream.audio {
                                    HStack(spacing: 11) {
                                        Label("共享音频", systemImage: viewer.audioTrack == nil ? "speaker.slash" : "speaker.wave.2")
                                            .font(.caption.weight(.medium))
                                            .frame(minWidth: 88, alignment: .leading)
                                        Slider(value: Binding(
                                            get: { viewer.audioVolume },
                                            set: { viewer.setAudioVolume($0) }
                                        ), in: 0 ... 1)
                                            .accessibilityLabel("共享音频音量")
                                        Text("\(Int((viewer.audioVolume * 100).rounded()))%")
                                            .font(.caption.monospacedDigit())
                                            .frame(width: 44, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 3)
                                }

                                HStack(spacing: 9) {
                                    Button {
                                        showingFullscreen = true
                                    } label: {
                                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                                            .frame(maxWidth: .infinity, minHeight: 42)
                                    }
                                    .buttonStyle(.bordered)

                                    Button(role: .destructive) {
                                        model.leaveScreenShare()
                                    } label: {
                                        Label("退出觀看", systemImage: "xmark")
                                            .frame(maxWidth: .infinity, minHeight: 42)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            } else {
                                Button {
                                    model.joinScreenShare(stream)
                                } label: {
                                    Label("觀看共享", systemImage: "play.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 45)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.phase != .connected || stream.ownerClientId == model.localClientID)
                            }
                        }
                        .padding(15)
                        .webSpeakGlassCard(cornerRadius: 20)
                    }
                }

                Button {
                    model.requestScreenShareList()
                } label: {
                    Label("刷新共享列表", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
            }
            .padding(18)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showingFullscreen) {
            if let viewer = model.screenShareViewerSession {
                NavigationStack {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ScreenShareVideoView(track: viewer.videoTrack)
                            .ignoresSafeArea()
                        if viewer.videoTrack == nil {
                            Text(viewer.status)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.black.opacity(0.65), in: Capsule())
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("完成") { showingFullscreen = false }
                                .foregroundStyle(.white)
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
                .preferredColorScheme(.dark)
            }
        }
    }
}

private struct ScreenSharePublisherStatusView: View {
    @ObservedObject var session: ScreenSharePublisherSession
    @ObservedObject var model: WebSpeakAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: session.isCapturing ? "record.circle.fill" : "rectangle.on.rectangle")
                    .foregroundStyle(session.isCapturing ? Color.red : Color.webSpeakBlue)
                Text(session.isCapturing ? "正在共享本机屏幕" : "等待系统选择屏幕")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if session.isCapturing { ProgressView().controlSize(.small) }
            }
            Text(session.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                model.stopScreenSharePublishing()
            } label: {
                Label("停止共享", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .webSpeakGlassCard(cornerRadius: 17)
    }
}

private struct SessionSettingsView: View {
    @ObservedObject var model: WebSpeakAppModel
    @State private var showingClearLocalDataConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                Text("诊断与设置")
                    .font(.largeTitle.weight(.bold))

                VStack(alignment: .leading, spacing: 11) {
                    Label("麦克风控制", systemImage: "mic.badge.waveform")
                        .font(.subheadline.weight(.semibold))
                    Picker("麦克风模式", selection: Binding(
                        get: { model.microphoneControlMode },
                        set: { model.setMicrophoneControlMode($0) }
                    )) {
                        Text("点按开关").tag(MicrophoneControlMode.toggle)
                        Text("按住说话").tag(MicrophoneControlMode.pushToTalk)
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isWhisperPushToTalkBusy || model.isPushToTalkActive)
                    Text(model.microphoneControlMode == .pushToTalk
                        ? "按住语音首页的麦克风按钮发言，松开后自动静音。"
                        : "点按语音首页的麦克风按钮，在开启与静音之间切换。扬声器关闭时麦克风不可启用。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 19)

                VStack(alignment: .leading, spacing: 13) {
                    Label("麦克风声音", systemImage: "waveform")
                        .font(.subheadline.weight(.semibold))

                    Toggle("说话时自动发送", isOn: $model.voiceActivityDetectionEnabled)
                        .tint(.webSpeakBlue)
                    Text(model.voiceActivityDetectionEnabled
                        ? "安静时不发送；声音达到下方设定后才开始发送。"
                        : "关闭时，只要麦克风开启就会持续发送声音。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.voiceActivityDetectionEnabled {
                        HStack(spacing: 12) {
                            Text("说话触发音量")
                                .font(.caption)
                            Slider(value: Binding(
                                get: { model.voiceActivityThreshold },
                                set: { model.voiceActivityThreshold = $0 }
                            ), in: 0.001 ... 0.08, step: 0.001)
                                .tint(.webSpeakBlue)
                                .accessibilityLabel("说话触发音量")
                            Text(String(format: "%.1f%%", model.voiceActivityThreshold * 100))
                                .font(.caption.monospacedDigit())
                                .frame(width: 46, alignment: .trailing)
                        }
                    }

                    Toggle("降噪与回声处理", isOn: $model.noiseSuppressionEnabled)
                        .tint(.webSpeakBlue)
                    Text("使用 iOS 内置通话语音处理，尝试减轻背景声和回声；不是单独的降噪滤镜。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("这两项只作用于旧版 WebSocket 语音；WebRTC 通话由 iOS 自带通话处理。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !model.gatewayWebRTCAvailable {
                        HStack(spacing: 9) {
                            Text("麦克风输入")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: model.microphoneInputLevel)
                                .tint(.webSpeakBlue)
                            Text("\(Int((model.microphoneInputLevel * 100).rounded()))%")
                                .font(.caption2.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 19)

                VStack(alignment: .leading, spacing: 11) {
                    Label("语言", systemImage: "globe")
                        .font(.subheadline.weight(.semibold))
                    Picker("应用语言", selection: $model.selectedLanguageCode) {
                        Text("跟随系统").tag("system")
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                        Text("Deutsch").tag("de")
                        Text("Русский").tag("ru")
                        Text("日本語").tag("ja")
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 19)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { model.pokeNotificationsEnabled },
                        set: { model.setPokeNotificationsEnabled($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("后台消息通知")
                                .font(.subheadline.weight(.medium))
                            Text("当别人向你发送提醒时，在后台显示本机通知；普通聊天消息不推送。需允许通知，并且语音连接仍在运行。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(.webSpeakBlue)
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 19)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Label("音频输出", systemImage: "airplayaudio")
                            .font(.subheadline)
                        Spacer()
                        AudioRoutePicker()
                            .frame(width: 42, height: 42)
                    }
                    .padding(.horizontal, 16)

                    Divider().padding(.leading, 16)

                    HStack {
                        Label("WebSocket RTT", systemImage: "network")
                        Spacer()
                        Text(model.browserRoundTripMs.map { "\($0) ms" } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(16)

                    Divider().padding(.leading, 16)

                    HStack {
                        Label("TeamSpeak 延迟", systemImage: "server.rack")
                        Spacer()
                        Text(model.teamSpeakLatencyMs.map { "\($0) ms" } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .padding(16)
                }
                .webSpeakGlassCard(cornerRadius: 21)

                Button {
                    model.measureLatency()
                } label: {
                    Label("测量连接延迟", systemImage: "speedometer")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 12) {
                    Label("本次会话事件", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                    if model.serverEvents.isEmpty {
                        Text("暂无事件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.serverEvents.suffix(30)) { event in
                            HStack(alignment: .top, spacing: 9) {
                                Circle().fill(Color.webSpeakBlue.opacity(0.7)).frame(width: 6, height: 6).padding(.top, 5)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.message).font(.caption)
                                    Text(Date(timeIntervalSince1970: event.timestamp / 1_000).formatted(date: .omitted, time: .shortened))
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                .webSpeakGlassCard(cornerRadius: 21)

                Label("聊天与事件不会写入持久化历史；断开连接后会从内存清除。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    showingClearLocalDataConfirmation = true
                } label: {
                    Label("清除本设备保存的数据", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 45)
                }
                .buttonStyle(.bordered)
                .confirmationDialog(
                    "清除 WebSpeak 本地数据？",
                    isPresented: $showingClearLocalDataConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("清除本地连接、身份与音量偏好", role: .destructive) {
                        model.clearLocalData()
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("不会删除网关或 TeamSpeak 服务器上的资料，也不会结束当前服务器会话。")
                }
            }
            .padding(18)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StatusCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .webSpeakGlassCard(cornerRadius: 19)
    }
}
