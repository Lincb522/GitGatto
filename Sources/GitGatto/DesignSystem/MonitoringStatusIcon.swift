import AppKit

@MainActor
enum MonitoringStatusIcon {
    private static let images = Dictionary(uniqueKeysWithValues:
        [MonitoringOverallState.healthy, .monitoring, .paused, .attention].map { state in
            let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
                NSColor.black.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: NSPoint(x: 4, y: 5.5))
                path.line(to: NSPoint(x: 4, y: 12.5))
                path.move(to: NSPoint(x: 4, y: 10))
                path.curve(to: NSPoint(x: 13, y: 5.5), controlPoint1: NSPoint(x: 4, y: 7), controlPoint2: NSPoint(x: 13, y: 10))
                for origin in [NSPoint(x: 2, y: 1.5), NSPoint(x: 2, y: 12.5), NSPoint(x: 11, y: 1.5)] {
                    path.appendOval(in: NSRect(origin: origin, size: NSSize(width: 4, height: 4)))
                }
                path.stroke()
                let badge = NSBezierPath()
                badge.lineWidth = 1.5
                badge.lineCapStyle = .round
                switch state {
                case .healthy, .monitoring:
                    badge.appendOval(in: NSRect(x: 11, y: 12, width: 4, height: 4))
                case .paused:
                    badge.move(to: NSPoint(x: 11, y: 11.5))
                    badge.line(to: NSPoint(x: 11, y: 15.5))
                    badge.move(to: NSPoint(x: 15, y: 11.5))
                    badge.line(to: NSPoint(x: 15, y: 15.5))
                case .attention:
                    badge.move(to: NSPoint(x: 13, y: 10.5))
                    badge.line(to: NSPoint(x: 13, y: 13))
                    badge.move(to: NSPoint(x: 13, y: 15.5))
                    badge.line(to: NSPoint(x: 13, y: 15.6))
                }
                badge.stroke()
                return true
            }
            image.isTemplate = true
            return (state, image)
        })

    static func image(for state: MonitoringOverallState) -> NSImage {
        images[state] ?? NSImage(size: NSSize(width: 18, height: 18))
    }
}
