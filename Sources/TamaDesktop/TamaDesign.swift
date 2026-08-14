import SwiftUI
import WisentDesignSystem

enum TamaLayout {
    static let minimumWindowWidth = WisentDesign.Layout.minimumDesktopWidth
    static let minimumWindowHeight = WisentDesign.Layout.minimumDesktopHeight
    static let contentMaximumWidth = WisentDesign.Layout.contentMaximumWidth
    static let setupMaximumWidth: CGFloat = 820
    static let catalogListMinimumWidth: CGFloat = 320
    static let catalogListIdealWidth: CGFloat = 400
    static let justificationListMinimumWidth: CGFloat = 340
    static let justificationListIdealWidth: CGFloat = 440
    static let registryPickerMaximumWidth: CGFloat = 420
    static let brandSymbolSize: CGFloat = 18
    static let noticeSymbolSize: CGFloat = 15
    static let setupStatusSymbolSize: CGFloat = 30
    static let setupStatusControlSize: CGFloat = 64
}

struct TamaPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x6) {
                content
            }
            .padding(WisentDesign.Space.x6)
            .frame(maxWidth: TamaLayout.contentMaximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { WisentCanvasBackground() }
    }
}

struct TamaSidebarBrand: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: TamaLayout.brandSymbolSize, weight: .semibold))
                .foregroundStyle(WisentDesign.brandStrong)
                .frame(width: WisentDesign.Space.x10, height: WisentDesign.Space.x10)
                .background(
                    WisentDesign.brandSoft,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                )
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text("Tama")
                    .font(WisentTypography.heading(18))
                    .foregroundStyle(WisentDesign.ink)
                Text(subtitle.uppercased())
                    .font(WisentTypography.monoMedium(9))
                    .tracking(0.7)
                    .foregroundStyle(WisentDesign.muted)
            }
            Spacer()
        }
        .padding(WisentDesign.Space.x4)
        .accessibilityElement(children: .combine)
    }
}

struct TamaPanelSection<Content: View>: View {
    let title: String
    let detail: String?
    private let content: Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x4) {
                WisentSectionHeader(title, detail: detail)
                content
            }
            .font(WisentTypography.body(13))
            .foregroundStyle(WisentDesign.ink)
        }
    }
}

struct TamaNotice: View {
    let title: String
    let detail: String
    let symbol: String
    let tone: WisentTone

    var body: some View {
        HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
            Image(systemName: symbol)
                .font(.system(size: TamaLayout.noticeSymbolSize, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: WisentDesign.Space.x8, height: WisentDesign.Space.x8)
                .background(
                    tone.softColor,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                )
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text(title)
                    .font(WisentTypography.bodyMedium(13))
                    .foregroundStyle(WisentDesign.ink)
                Text(detail)
                    .font(WisentTypography.body(12))
                    .foregroundStyle(WisentDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: WisentDesign.Space.x2)
        }
        .padding(WisentDesign.Space.x3)
        .background(
            tone.softColor,
            in: RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WisentDesign.Radius.medium)
                .stroke(tone.color.opacity(0.18), lineWidth: WisentDesign.hairline)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TamaRequirement: View {
    let title: String
    let satisfied: Bool

    var body: some View {
        Label(title, systemImage: satisfied ? "checkmark.circle.fill" : "circle.dashed")
            .font(WisentTypography.bodyMedium(12))
            .foregroundStyle(satisfied ? WisentDesign.success : WisentDesign.secondary)
            .accessibilityValue(satisfied ? "Satisfied" : "Not satisfied")
    }
}
