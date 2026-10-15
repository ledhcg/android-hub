import AppKit
import SwiftUI

// Android Hub design tokens. Every view takes spacing, radii, type and surfaces from here, never literals.
// Rationale and usage rules: docs/design/.

/// 4-pt spacing scale.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Corner radii (always `.continuous`).
enum Radius {
    /// Fields, small chips, thumbnails.
    static let control: CGFloat = 8
    /// Cards and grouped content.
    static let card: CGFloat = 12
    /// Large floating surfaces (device bezel plate, popovers).
    static let panel: CGFloat = 16
}

/// Semantic surfaces. They resolve to system colours, so light/dark mode, increased contrast and the user's
/// accent colour all keep working.
enum Surface {
    /// The window and detail background; toolbar and content share it so there is no visible seam.
    static let canvas = Color(nsColor: .windowBackgroundColor)
    /// Grouped content that sits on the canvas.
    static let card = Color(nsColor: .controlBackgroundColor)
    /// Recessed areas: code/log output, text wells.
    static let well = Color(nsColor: .textBackgroundColor)
}

/// Brand colour. DECORATIVE ONLY (empty-state glyphs, "live" indicators). Interactive tint stays the system accent.
enum Brand {
    static let green = Color(red: 68 / 255, green: 209 / 255, blue: 130 / 255)
}

/// Type roles. Built on system text styles so Dynamic Type-style user settings are honoured.
enum TypeRole {
    /// Page / empty-state title.
    static let title = Font.title3.weight(.semibold)
    /// Section titles inside panels.
    static let section = Font.headline
    static let body = Font.body
    /// Supporting text under a title or in a row.
    static let secondary = Font.callout
    /// Captions, hints, counters.
    static let caption = Font.caption
    /// Logs, serials, paths, command output.
    static let mono = Font.callout.monospaced()
}

extension View {
    /// Grouped content on a card surface: padding, radius and surface from the tokens.
    func cardStyle(padding: CGFloat = Space.md) -> some View {
        self.padding(padding)
            .background(Surface.card, in: .rect(cornerRadius: Radius.card, style: .continuous))
    }

    /// Recessed monospaced output (logs, errors, command results).
    func wellStyle(padding: CGFloat = Space.sm) -> some View {
        self.padding(padding)
            .background(Surface.well, in: .rect(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(.separator))
    }

    /// Fills the detail area with the shared canvas surface.
    func canvasBackground() -> some View {
        background(Surface.canvas)
    }
}

/// Empty, error, loading and "not ready" states. One look everywhere: glyph, title, one sentence, optional actions.
struct StatusMessage<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = .secondary
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .padding(.bottom, Space.xs)
            Text(title).font(TypeRole.title).foregroundStyle(.primary)
            Text(message)
                .font(TypeRole.secondary).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            actions()
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension StatusMessage where Actions == EmptyView {
    init(symbol: String, title: String, message: String, tint: Color = .secondary) {
        self.init(symbol: symbol, title: title, message: message, tint: tint, actions: { EmptyView() })
    }
}

/// A small status capsule ("Live", "Recording", "Offline").
struct StatusPill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(TypeRole.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, Space.sm).padding(.vertical, Space.xs / 2 + 1)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
