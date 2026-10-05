import SwiftUI
import UIKit

extension Color {
    static let webSpeakBlue = Color(red: 35.0 / 255.0, green: 76.0 / 255.0, blue: 205.0 / 255.0)
    static let webSpeakBlueSoft = Color(red: 102.0 / 255.0, green: 137.0 / 255.0, blue: 238.0 / 255.0)
}

struct BrandBackground: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
                }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }
        }
    }
}

extension View {
    func webSpeakGlassCard(cornerRadius: CGFloat = 26) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

struct PrototypeNotice: View {
    var body: some View {
        Label {
            Text("离线示例 · 不连接服务器或采集音频")
                .font(.footnote.weight(.medium))
        } icon: {
            Image(systemName: "eye")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .webSpeakGlassCard(cornerRadius: 16)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}
