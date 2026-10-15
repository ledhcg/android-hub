import SwiftUI

// Liquid Glass (macOS 26+) with a material fallback for macOS 15–25.
// The `compiler` guard keeps the package building with SDKs that predate the glass APIs.

extension View {
    /// A floating glass surface in the given shape; a regular material before macOS 26.
    @ViewBuilder func glassSurface<S: Shape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
        #else
        background(.regularMaterial, in: shape)
        #endif
    }

    /// The primary call-to-action button: glass-prominent on macOS 26+, bordered-prominent before.
    @ViewBuilder func prominentActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
}
