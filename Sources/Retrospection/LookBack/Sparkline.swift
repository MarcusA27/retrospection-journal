import SwiftUI

/// A quiet sentiment curve for the sidebar — your daily tone over time, drawn as a thin line with a
/// faint fill. No axes, no labels: a strip you read at a glance, not a chart you study. The selected
/// day is marked so it ties back to the entry you're reading.
struct Sparkline: View {
    let points: [SentimentPoint]
    let selected: String?

    var body: some View {
        GeometryReader { geo in
            let pts = positions(in: geo.size)
            ZStack {
                fillPath(pts, h: geo.size.height)
                    .fill(LinearGradient(
                        colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom))
                linePath(pts)
                    .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                if let i = selectedIndex, i < pts.count {
                    Rectangle().fill(Color.secondary.opacity(0.18))
                        .frame(width: 1).position(x: pts[i].x, y: geo.size.height / 2)
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5).position(pts[i])
                }
            }
        }
        .frame(height: 42)
    }

    private var selectedIndex: Int? {
        guard let s = selected else { return points.isEmpty ? nil : points.count - 1 }
        return points.firstIndex { $0.date == s }
    }

    private func positions(in size: CGSize) -> [CGPoint] {
        let vals = points.map(\.score)
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let span = max(hi - lo, 0.0001)
        let step = points.count > 1 ? size.width / CGFloat(points.count - 1) : 0
        return points.indices.map { i in
            let y = size.height - CGFloat((points[i].score - lo) / span) * (size.height - 6) - 3
            return CGPoint(x: CGFloat(i) * step, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
    }

    private func fillPath(_ pts: [CGPoint], h: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: h))
            p.addLine(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: last.x, y: h))
            p.closeSubpath()
        }
    }
}
