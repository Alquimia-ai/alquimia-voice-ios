import SwiftUI

/// Bar meter of the microphone level. Bars past the server's −40 dBFS activation threshold turn ember,
/// and a dashed marker shows where that threshold sits so you can see whether the server will hear you.
struct LevelMeterView: View {
    let level: Float
    let dbfs: Float
    var bars = 32

    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 3
            let barWidth = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
            let filled = Int((CGFloat(level) * CGFloat(bars)).rounded())
            let threshold = CGFloat(LevelMeter.normalized(dbfs: LevelMeter.serverThresholdDBFS))
            let thresholdIndex = Int((threshold * CGFloat(bars)).rounded())

            for index in 0..<bars {
                let x = CGFloat(index) * (barWidth + gap)
                let rect = CGRect(x: x, y: 0, width: barWidth, height: size.height)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                let color: Color
                if index < filled {
                    color = index >= thresholdIndex ? Theme.Palette.ember : Theme.Palette.ink
                } else {
                    color = Theme.Palette.hairline
                }
                context.fill(path, with: .color(color))
            }

            let markerX = CGFloat(thresholdIndex) * (barWidth + gap) - gap / 2
            var marker = Path()
            marker.move(to: CGPoint(x: markerX, y: -4))
            marker.addLine(to: CGPoint(x: markerX, y: size.height + 4))
            context.stroke(marker, with: .color(Theme.Palette.mutedSoft), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
        .frame(height: 24)
        .accessibilityLabel(Text("Nivel de entrada \(Int(dbfs)) dBFS"))
    }
}
