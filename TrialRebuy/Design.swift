import SwiftUI
import UIKit

enum Theme {
    static let base = Color(hex: 0xFAF3EE)
    static let accent = Color(hex: 0xA24A5E)
    static let ink = Color(hex: 0x2E2528)
    static let muted = Color(hex: 0x6E6061)
    static let line = Color(hex: 0xE9DDD6)
    static let rose = Color(hex: 0xF3E2E5)
    static let paleRose = Color(hex: 0xF7E9EB)
    static let sand = Color(hex: 0xF4E7D4)
    static let leaf = Color(hex: 0xE5EFE5)

    static func tint(_ palette: ShareStyle.Palette) -> Color {
        switch palette {
        case .rose: rose
        case .sand: sand
        case .leaf: leaf
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255)
    }
}

extension Verdict {
    var symbol: String {
        switch self {
        case .buy: "checkmark.circle"
        case .retry: "arrow.clockwise"
        case .skip: "minus.circle"
        }
    }

    var hue: Color {
        switch self {
        case .buy: Color(hex: 0x6F9A78)
        case .retry: Color(hex: 0xD3923A)
        case .skip: Color(hex: 0x8C837D)
        }
    }

    var background: Color {
        switch self {
        case .buy: Theme.leaf
        case .retry: Theme.sand
        case .skip: Color(hex: 0xEEE8E4)
        }
    }
}

struct StatusPill: View {
    let verdict: Verdict
    var body: some View {
        Label(verdict.label, systemImage: verdict.symbol)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 5).padding(.horizontal, 8)
            .foregroundStyle(Theme.ink)
            .background(verdict.background, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    let symbol: String
    let id: String
    var secondary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: secondary ? 44 : 52)
                .foregroundStyle(secondary ? Theme.accent : .white)
                .background(secondary ? Theme.paleRose : Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct IconTile: View {
    let title: String
    let symbol: String
    let id: String
    var tint = Theme.rose
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 39, height: 39)
                    .foregroundStyle(Theme.ink)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .padding(.horizontal, 13).padding(.vertical, 7)
            .whiteCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

struct EmptyIllustration: View {
    var body: some View {
        ZStack {
            Capsule().fill(Theme.sand).frame(width: 147, height: 29).offset(y: 25)
            symbol("viewfinder", width: 46, height: 46, tint: Theme.paleRose).rotationEffect(.degrees(-14)).offset(x: -53, y: 2)
            symbol("shippingbox", width: 66, height: 72, tint: Theme.rose).rotationEffect(.degrees(8)).offset(y: -4)
            symbol("checkmark.circle", width: 42, height: 42, tint: Theme.leaf).rotationEffect(.degrees(11)).offset(x: 55, y: 17)
        }
        .frame(height: 88)
        .accessibilityHidden(true)
    }

    private func symbol(_ icon: String, width: CGFloat, height: CGFloat, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: width * 0.41, weight: .medium))
            .frame(width: width, height: height)
            .background(tint, in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(Theme.accent)
    }
}

struct PhotoTile: View {
    @EnvironmentObject private var model: LibraryModel
    let id: UUID?
    var large = false
    var accessibilityID: String? = nil
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(Theme.rose)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Image(systemName: "shippingbox")
                        .font(.system(size: large ? 40 : 19, weight: .light))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.t("photo.package"))
        .accessibilityIdentifier(accessibilityID ?? "")
        .accessibilityHidden(accessibilityID == nil || image == nil)
        .task(id: id) {
            image = nil
            if let id, let data = await model.disk.thumbnail(id), !Task.isCancelled { image = UIImage(data: data) }
        }
    }
}

struct IconRow: View {
    let verdict: Verdict
    let title: String
    let subtitle: String
    var detail: String?
    var photo: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: verdict.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 39, height: 39)
                .background(verdict.background, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(verdict.hue.opacity(0.55)) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                if let detail { Text(detail).font(.footnote).lineLimit(2) }
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 5) {
                StatusPill(verdict: verdict)
                if let photo { PhotoTile(id: photo).frame(width: 36, height: 36) }
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(11)
        .frame(minHeight: 58)
        .whiteCard()
        .contentShape(Rectangle())
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) { content }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.base)
        .foregroundStyle(Theme.ink)
    }
}

extension View {
    func whiteCard() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    func sectionHeading() -> some View {
        font(.headline).foregroundStyle(Theme.muted).accessibilityAddTraits(.isHeader)
    }
}

struct SearchField: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    var id = "search.field"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent).accessibilityHidden(true)
            TextField(L.t("search.prompt"), text: $query)
                .focused(focus).submitLabel(.search)
                .onSubmit { focus.wrappedValue = false }
                .accessibilityIdentifier(id)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L.t("search.clear"))
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line) }
    }
}

struct StorageNotice: View {
    @EnvironmentObject private var model: LibraryModel

    var body: some View {
        if model.failed {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t(model.ready ? "storage.saveError" : "storage.loadError")).font(.footnote)
                PrimaryButton(title: L.t("action.tryAgain"), symbol: "arrow.clockwise", id: "storage.retry", secondary: true) {
                    if model.ready { model.persist() }
                    else { Task { await model.load() } }
                }
            }
            .padding(10)
            .background(Theme.sand)
        }
    }
}
