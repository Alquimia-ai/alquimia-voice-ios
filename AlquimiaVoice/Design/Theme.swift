import SwiftUI
import UIKit

/// Design tokens mapped from https://www.alquimia.ai/DESIGN.md.
/// Colors live in the asset catalog (light/dark variants); typography is Geist with a system fallback.
enum Theme {
    enum Palette {
        static let canvas = Color("Canvas")
        static let ink = Color("Ink")
        static let onPrimary = Color("OnPrimary")
        static let surfaceSoft = Color("SurfaceSoft")
        static let card = Color("Card")
        static let body = Color("Body")
        static let muted = Color("Muted")
        static let mutedSoft = Color("MutedSoft")
        static let ember = Color("Ember")
        static let emberDeep = Color("EmberDeep")
        static let hairline = Color("Hairline")
        static let hairlineSoft = Color("HairlineSoft")
        static let error = Color("ErrorRed")
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 40
    }

    enum Radius {
        static let control: CGFloat = 4
        static let block: CGFloat = 8
        static let card: CGFloat = 12
    }

    enum Typography {
        enum Weight {
            case regular, medium, semibold, bold

            var geist: String {
                switch self {
                case .regular: return "Geist-Regular"
                case .medium: return "Geist-Medium"
                case .semibold: return "Geist-SemiBold"
                case .bold: return "Geist-Bold"
                }
            }

            var mono: String {
                switch self {
                case .regular: return "GeistMono-Regular"
                case .medium, .semibold, .bold: return "GeistMono-Medium"
                }
            }

            var system: Font.Weight {
                switch self {
                case .regular: return .regular
                case .medium: return .medium
                case .semibold: return .semibold
                case .bold: return .bold
                }
            }
        }

        static let geistAvailable: Bool = UIFont(name: "Geist-Regular", size: 12) != nil
        static let monoAvailable: Bool = UIFont(name: "GeistMono-Regular", size: 12) != nil

        static func sans(_ size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
            geistAvailable
                ? .custom(weight.geist, size: size, relativeTo: style)
                : .system(size: size, weight: weight.system)
        }

        static func mono(_ size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
            monoAvailable
                ? .custom(weight.mono, size: size, relativeTo: style)
                : .system(size: size, weight: weight.system, design: .monospaced)
        }

        static var headlineLg: Font { sans(44, weight: .medium, relativeTo: .largeTitle) }
        static var headlineMd: Font { sans(32, weight: .medium, relativeTo: .title) }
        static var headlineSm: Font { sans(24, weight: .medium, relativeTo: .title2) }
        static var bodyLg: Font { sans(16, relativeTo: .body) }
        static var bodyMd: Font { sans(15, relativeTo: .body) }
        static var bodySm: Font { sans(14, relativeTo: .subheadline) }
        static var labelLg: Font { sans(14, weight: .medium, relativeTo: .subheadline) }
        static var labelMd: Font { sans(12, weight: .medium, relativeTo: .caption) }
        static var eyebrow: Font { sans(11, relativeTo: .caption2) }
        static var monoLabel: Font { mono(12.5, relativeTo: .caption) }
        static var monoLarge: Font { mono(28, weight: .medium, relativeTo: .title) }

        static let eyebrowTracking: CGFloat = 11 * 0.16

        static func headlineTracking(_ size: CGFloat) -> CGFloat { -0.02 * size }
    }
}

extension View {
    /// Hairline border instead of a shadow, per the design system.
    func hairline(_ radius: CGFloat = Theme.Radius.card, color: Color = Theme.Palette.hairline) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: 1))
    }
}
