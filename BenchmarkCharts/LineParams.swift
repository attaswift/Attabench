// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

extension BenchmarkTheme {
    public struct LineParams {
        let lineWidth: CGFloat
        let color: NSColor
        let dash: [CGFloat]
        let phase: CGFloat
        let capStyle: NSBezierPath.LineCapStyle
        let joinStyle: NSBezierPath.LineJoinStyle
        let shadowRadius: CGFloat

        init(lineWidth: CGFloat, color: NSColor, dash: [CGFloat] = [], phase: CGFloat = 0,
             capStyle: NSBezierPath.LineCapStyle = .roundLineCapStyle, joinStyle: NSBezierPath.LineJoinStyle = .roundLineJoinStyle,
             shadowRadius: CGFloat = 0) {
            self.lineWidth = lineWidth
            self.color = color
            self.dash = dash
            self.phase = phase
            self.capStyle = capStyle
            self.joinStyle = joinStyle
            self.shadowRadius = shadowRadius
        }

        func apply(on path: NSBezierPath) {
            path.lineWidth = lineWidth
            path.lineJoinStyle = joinStyle
            path.lineCapStyle = capStyle
            path.setLineDash(dash)
        }
    }
}
