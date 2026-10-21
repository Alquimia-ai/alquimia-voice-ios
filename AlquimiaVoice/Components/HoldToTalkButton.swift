import SwiftUI

/// 88 pt ember circle. Press fires `onPress` once; lifting the finger fires `onRelease`.
struct HoldToTalkButton: View {
    let isHolding: Bool
    let isEnabled: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var tracking = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isHolding ? Theme.Palette.emberDeep : Theme.Palette.ember)
            Image(systemName: isHolding ? "waveform" : "mic.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 88, height: 88)
        .scaleEffect(isHolding ? 1.06 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.15), value: isHolding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled, !tracking else { return }
                    tracking = true
                    onPress()
                }
                .onEnded { _ in
                    guard tracking else { return }
                    tracking = false
                    onRelease()
                }
        )
        .accessibilityLabel(Text(L10n.Actions.holdToTalk))
        .accessibilityAddTraits(.isButton)
    }
}
