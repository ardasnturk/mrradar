import SwiftUI

/// MRRadar's look: the same cards, buttons and soft background as Remote Code, Vitrin and
/// Promo Studio, with an emerald gradient of its own.
enum Brand {
    static let emerald = Color(red: 0.11, green: 0.72, blue: 0.50)
    static let teal = Color(red: 0.05, green: 0.60, blue: 0.62)
    static let gold = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let coral = Color(red: 0.95, green: 0.40, blue: 0.38)
    static let indigo = Color(red: 0.30, green: 0.36, blue: 0.93)

    static let gradient = LinearGradient(colors: [emerald, teal, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let buttonGradient = LinearGradient(colors: [emerald, teal], startPoint: .leading, endPoint: .trailing)
}

struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Snapshots can't draw a blur, so they use a plain gradient.
    nonisolated(unsafe) static var isFlat = false

    var body: some View {
        if Self.isFlat {
            LinearGradient(colors: [Color(red: 0.07, green: 0.13, blue: 0.13), Color(red: 0.08, green: 0.09, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        } else {
            blobs
        }
    }

    private var blobs: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Circle().fill(Brand.emerald).frame(width: size.width * 0.8, height: size.width * 0.8)
                        .offset(x: -size.width * 0.35, y: -size.height * 0.35)
                    Circle().fill(Brand.teal).frame(width: size.width * 0.7, height: size.width * 0.7)
                        .offset(x: size.width * 0.4, y: -size.height * 0.1)
                    Circle().fill(Brand.gold).frame(width: size.width * 0.6, height: size.width * 0.6)
                        .offset(x: -size.width * 0.1, y: size.height * 0.5)
                }
                .frame(width: size.width, height: size.height)
            }
            .blur(radius: 70)
            .opacity(colorScheme == .dark ? 0.32 : 0.2)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 14, padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct IconBadge: View {
    let symbol: String
    var colors: [Color] = [Brand.emerald, Brand.teal]
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.52, weight: .semibold)).foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 16)
            .background(Brand.buttonGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct StatusPill: View {
    let text: Text
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            text
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.white.opacity(0.18), in: Capsule())
    }
}

/// A project's icon from RevenueCat, or its initial.
struct ProjectIcon: View {
    let project: RCProjectLike
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = project.iconURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { initial }
            } else {
                initial
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Brand.gradient.overlay {
            Text(verbatim: String(project.name.prefix(1)))
                .font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
        }
    }
}

protocol RCProjectLike {
    var name: String { get }
    var iconURL: String? { get }
}
