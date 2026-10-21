import SwiftUI

/// Ink fill, on-primary text, 4 pt radius, 36 pt tall.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.labelLg)
            .foregroundStyle(Theme.Palette.onPrimary)
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 36)
            .background(
                Theme.Palette.ink.opacity(configuration.isPressed ? 0.9 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Surface fill with hairline; ember on press.
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.labelLg)
            .foregroundStyle(configuration.isPressed ? Color.white : Theme.Palette.ink)
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 36)
            .background(
                configuration.isPressed ? Theme.Palette.ember : Theme.Palette.canvas,
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .hairline(Theme.Radius.control)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Pill chip: surface-soft, full radius, label-md.
struct ChipButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.labelMd)
            .foregroundStyle(active ? Theme.Palette.onPrimary : Theme.Palette.ink.opacity(0.8))
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs + 2)
            .background(
                active ? Theme.Palette.ink : Theme.Palette.surfaceSoft,
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Round icon button with a hairline, used for mute and settings.
struct IconCircleButtonStyle: ButtonStyle {
    var size: CGFloat = 44
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(active ? Theme.Palette.onPrimary : Theme.Palette.ink)
            .frame(width: size, height: size)
            .background(active ? Theme.Palette.ink : Theme.Palette.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
