//
//  ChartRendering.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Cocoa
import BenchmarkingTools

extension NSBezierPath {
    func appendLines(between points: [CGPoint]) {
        if points.isEmpty { return }
        self.move(to: points[0])
        for point in points.dropFirst() {
            self.line(to: point)
        }
    }
}

extension Int {
    var label: String {
        return self >= 1 << 40 ? String(format: "%.3gT", Double(self) * 0x1p-40)
            : self >= 1 << 30 ? String(format: "%.3gG", Double(self) * 0x1p-30)
            : self >= 1 << 20 ? String(format: "%.3gM", Double(self) * 0x1p-20)
            : self >= 1024 ? String(format: "%.3gk", Double(self) * 0x1p-10)
            : "\(self)"
    }
}

extension TimeInterval {
    var label: String {
        return self >= 1000 ? String(Int(self)) + "s"
            : self >= 1 ? String(format: "%.3gs", self)
            : self >= 1e-3 ? String(format: "%.3gms", self * 1e3)
            : self >= 1e-6 ? String(format: "%.3gµs", self * 1e6)
            : String(format: "%.3gns", self * 1e9)
    }
}

class Chart {
    let size: CGSize
    let suite: Suite
    let title: String
    let presentationMode: Bool

    var curves: [(String, NSColor, NSBezierPath)] = []
    var verticalGridLines: [(String?, CGFloat)] = []
    var horizontalGridLines: [(String?, CGFloat)] = []
    var horizontalHighlight: Range<CGFloat>? = nil

    init(size: CGSize,
         suite: Suite,
         highlightedSizes: ClosedRange<Int>? = nil,
         sizeRange: Range<Int>? = nil,
         timeRange: Range<TimeInterval>? = nil,
         amortized: Bool = false,
         presentation: Bool = false) {
        self.size = size
        self.suite = suite
        if amortized {
            self.title = suite.suite.descriptiveAmortizedTitle ?? suite.title + " (amortized)"
        }
        else {
            self.title = suite.suite.descriptiveTitle ?? suite.title
        }
        self.presentationMode = presentation

        let benchmarks = suite.selectedBenchmarks

        var minSize = sizeRange?.lowerBound ?? Int.max
        var maxSize = sizeRange?.upperBound ?? Int.min
        if let s = highlightedSizes {
            minSize = min(s.lowerBound, minSize)
            maxSize = max(s.upperBound, maxSize)
        }

        var minTime = timeRange?.lowerBound ?? Double.infinity
        var maxTime = timeRange?.upperBound ?? -Double.infinity
        var count = 0
        for (benchmark, samples) in suite.samplesByBenchmark where benchmarks.contains(benchmark) {
            for (size, sample) in samples.samplesBySize {
                if size > maxSize { maxSize = size }
                if size < minSize { minSize = size }
                let time = amortized ? sample.minimum / Double(size) : sample.minimum
                if time > maxTime { maxTime = time }
                if time < minTime { minTime = time }
                count += 1
            }
        }
        if count == 0 {
            return
        }

        var t: TimeInterval = 1e-20
        while 10 * t < minTime {
            t *= 10
        }
        minTime = t
        while t < maxTime {
            t *= 10
        }
        maxTime = t

        let scaleX = 1 / (log2(CGFloat(maxSize)) - log2(CGFloat(minSize)))
        let scaleY = 1 / CGFloat(log2(maxTime) - log2(minTime))

        func x(_ size: Int) -> CGFloat {
            return scaleX * log2(CGFloat(max(1, size)))
        }
        func y(_ size: Int, _ time: TimeInterval) -> CGFloat {
            let time = amortized ? time / Double(size) : time
            return scaleY * CGFloat(log2(time) - log2(minTime))
        }

        if let s = highlightedSizes {
            self.horizontalHighlight = x(s.lowerBound) ..< x(s.upperBound)
        }

        do {
            var size = minSize
            var i = 0
            while size <= maxSize {
                if size >= minSize {
                    let x = scaleX * log2(CGFloat(size))
                    if !presentationMode || i & 1 == 0 {
                        verticalGridLines.append((size.label, x))
                    }
                    else {
                        verticalGridLines.append((nil, x))
                    }
                }
                size <<= 1
                i += 1
            }
        }

        do {
            var time = minTime
            while time <= maxTime {
                horizontalGridLines.append((time.label, y(1, time)))
                time *= 10
            }
            if maxTime / minTime < 1e6 {
                time = 2 * minTime
                while time <= maxTime {
                    let yc = y(1, time)
                    horizontalGridLines.append((nil, yc))
                    time *= 2
                }
            }
        }


        let c = benchmarks.count
        for i in 0 ..< c {
            let benchmark = benchmarks[i]
            guard let samples = suite.samplesByBenchmark[benchmark] else { continue }

            let index = suite.benchmarkTitles.index(of: benchmark)!
            let color: NSColor
            if suite.benchmarkTitles.count > 6 {
                color = NSColor(calibratedHue: CGFloat(index) / CGFloat(suite.benchmarkTitles.count),
                                saturation: 1, brightness: 1, alpha: 1)
            }
            else {
                // Use stable colors when possible.
                // These particular ones are nice because people with most forms of color blindness can still
                // differentiate them.
                switch index {
                case 0: color = NSColor(calibratedRed: 0.89, green: 0.01, blue: 0.01, alpha: 1) // Red
                case 1: color = NSColor(calibratedRed: 1, green: 0.55, blue: 0, alpha: 1) // Orange
                case 2: color = NSColor(calibratedRed: 1, green: 0.93, blue: 0, alpha: 1) // Yellow
                case 3: color = NSColor(calibratedRed: 0, green: 0.5, blue: 0.15, alpha: 1) // Green
                case 4: color = NSColor(calibratedRed: 0, green: 0.3, blue: 1, alpha: 1) // Blue
                case 5: color = NSColor(calibratedRed: 0.46, green: 0.03, blue: 0.53, alpha: 1) // Purple
                default: fatalError()
                }
            }
            let path = NSBezierPath()
            path.appendLines(between: samples.samplesBySize.sorted(by: { $0.0 < $1.0 }).map { (size, sample) in
                return CGPoint(x: x(size), y: y(size, sample.minimum))
            })

            self.curves.append((benchmark, color, path))
        }
    }

    struct ViewParams {
        let backgroundColor: NSColor
        let titleFont: NSFont
        let titleColor: NSColor
        let borderColor: NSColor
        let majorGridLineColor: NSColor
        let minorGridLineColor: NSColor
        let scaleFont: NSFont
        let legendFont: NSFont
        let legendColor: NSColor
        let legendPadding: CGFloat
        let lineWidth: CGFloat
        let shadowRadius: CGFloat
        let xPadding: CGFloat

        static let normal = ViewParams(
            backgroundColor: NSColor.white,
            titleFont: NSFont(name: "Helvetica-Light", size: 24)!,
            titleColor: NSColor.black,
            borderColor: NSColor.black,
            majorGridLineColor: NSColor(white: 0.3, alpha: 1),
            minorGridLineColor: NSColor(white: 0.3, alpha: 1),
            scaleFont: NSFont(name: "Helvetica-Light", size: 12)!,
            legendFont: NSFont(name: "Menlo", size: 12)!,
            legendColor: NSColor.black,
            legendPadding: 6,
            lineWidth: 4,
            shadowRadius: 0,
            xPadding: 6)

        static let presentation = ViewParams(
            backgroundColor: NSColor.black,
            titleFont: NSFont(name: "Helvetica-Light", size: 48)!,
            titleColor: NSColor.white,
            borderColor: NSColor.white,
            majorGridLineColor: NSColor(white: 0.7, alpha: 1),
            minorGridLineColor: NSColor(white: 0.7, alpha: 1),
            scaleFont: NSFont(name: "Helvetica-Light", size: 24)!,
            legendFont: NSFont(name: "Menlo", size: 20)!,
            legendColor: NSColor.white,
            legendPadding: 8,
            lineWidth: 8,
            shadowRadius: 3,
            xPadding: 12)
    }

    func render(into bounds: NSRect) {
        let p = presentationMode ? ViewParams.presentation : ViewParams.normal

        p.backgroundColor.setFill()
        NSRectFill(bounds)

        let scaleAttributes: [String: Any] = [
            NSFontAttributeName: p.scaleFont,
            NSForegroundColorAttributeName: p.majorGridLineColor
        ]
        let (titleRect, bottomRect) = bounds.divided(
            atDistance: 1.2 * (p.titleFont.boundingRectForFont.height + p.titleFont.leading),
            from: .maxYEdge)

        let scaleWidth = 3 * p.scaleFont.maximumAdvancement.width
        let chartBounds = CGRect(x: bottomRect.minX + scaleWidth,
                                 y: p.scaleFont.boundingRectForFont.height,
                                 width: bottomRect.width - 2 * scaleWidth,
                                 height: bottomRect.height - p.scaleFont.boundingRectForFont.height)
        let largeSize = NSSize(width: 100000, height: 100000)

        // Draw title
        let title = NSAttributedString(
            string: self.title,
            attributes: [
                NSFontAttributeName: p.titleFont,
                NSForegroundColorAttributeName: p.titleColor,
            ])
        let titleBounds = title.boundingRect(with: largeSize, options: [], context: nil)
        title.draw(at: CGPoint(x: floor(titleRect.midX - titleBounds.width / 2),
                               y: floor(titleRect.midY - titleBounds.height / 2)))

        var chartTransform = AffineTransform()
        chartTransform.translate(x: chartBounds.minX, y: chartBounds.minY)
        chartTransform.scale(x: chartBounds.width, y: chartBounds.height)

        // Draw horizontal grid lines
        for (title, y) in horizontalGridLines {
            let color = title == nil ? p.minorGridLineColor : p.majorGridLineColor
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: 1, y: y))
            path.transform(using: chartTransform)
            if title == nil {
                path.setLineDash([6, 3], count: 2, phase: 0)
            }
            path.lineWidth = title == nil ? 0.5 : 0.75
            path.stroke()

            if let title = title {
                let yMid = chartBounds.minY + y * chartBounds.height + p.scaleFont.pointSize / 4

                let bounds = (title as NSString).boundingRect(with: largeSize, options: [], attributes: scaleAttributes)
                (title as NSString).draw(
                    at: CGPoint(x: chartBounds.minX - p.xPadding - bounds.width,
                                y: yMid - bounds.height / 2),
                    withAttributes: scaleAttributes)
                (title as NSString).draw(
                    at: CGPoint(x: chartBounds.maxX + p.xPadding,
                                y: yMid - bounds.height / 2),
                    withAttributes: scaleAttributes)
            }
        }

        // Draw vertical grid lines
        for (title, x) in verticalGridLines {
            let color = title == nil ? p.minorGridLineColor : p.majorGridLineColor
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: 1))
            path.transform(using: chartTransform)
            path.lineWidth = 0.5
            path.stroke()

            if let title = title {
                let xMid = chartBounds.minX + x * chartBounds.width
                let yTop = chartBounds.minY - 3

                let bounds = (title as NSString).boundingRect(with: largeSize, options: [], attributes: scaleAttributes)
                (title as NSString).draw(at: CGPoint(x: xMid - bounds.width / 2, y: yTop - bounds.height), withAttributes: scaleAttributes)
            }
        }
        
        // Draw border
        p.borderColor.setStroke()
        let border = NSBezierPath(rect: chartBounds.insetBy(dx: -0.25, dy: -0.25))
        border.lineWidth = 0.5
        border.stroke()

        if !presentationMode, let h = horizontalHighlight {
            let highlight = NSBezierPath()
            highlight.move(to: .init(x: h.lowerBound, y: 1))
            highlight.line(to: .init(x: h.upperBound, y: 1))
            highlight.move(to: .init(x: h.lowerBound, y: 0))
            highlight.line(to: .init(x: h.upperBound, y: 0))
            highlight.transform(using: chartTransform)
            highlight.lineWidth = 4
            highlight.lineCapStyle = .roundLineCapStyle
            highlight.stroke()
        }

        guard !curves.isEmpty else { return }

        // Calculate legend positions and sizes
        let legendMinX = chartBounds.minX + min(0.1 * chartBounds.width, 0.1 * chartBounds.height)
        let legendMaxY = chartBounds.maxY - min(0.1 * chartBounds.width, 0.1 * chartBounds.height)
        var legendMaxX = legendMinX
        var legendMinY = legendMaxY
        var legend: [(position: CGPoint, title: NSAttributedString)] = []
        for (title, color, _) in curves {
            let title = NSMutableAttributedString(string: "◼︎ " + title, attributes: [
                NSFontAttributeName: p.legendFont,
                NSForegroundColorAttributeName: p.legendColor,
                ])
            title.setAttributes([NSForegroundColorAttributeName: color],
                                range: NSRange(0 ..< 1))

            let titleBounds = title.boundingRect(with: largeSize, options: [])
            legendMinY -= titleBounds.height
            legend.append((CGPoint(x: legendMinX, y: legendMinY), title))
            legendMinY -= p.legendFont.leading
            legendMaxX = max(legendMaxX, legendMinX + titleBounds.width)
        }
        let legendRect = CGRect(x: legendMinX, y: legendMinY, width: legendMaxX - legendMinX, height: legendMaxY - legendMinY)
            .insetBy(dx: -2 * p.legendPadding, dy: -2 * p.legendPadding)
        let legendBorder = NSBezierPath(rect: legendRect)
        legendBorder.lineWidth = 0.5

        // Draw legend background
        p.backgroundColor.setFill()
        legendBorder.fill()

        // Draw curves
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartBounds)
        if p.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = p.shadowRadius
            shadow.shadowOffset = .zero
            shadow.shadowColor = .black
            shadow.set()
        }
        for (_, color, path) in curves {
            color.setStroke()
            let path = (chartTransform as NSAffineTransform).transform(path)
            path.lineWidth = p.lineWidth
            path.lineCapStyle = .roundLineCapStyle
            path.lineJoinStyle = .roundLineJoinStyle
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        if !presentationMode {
            NSColor.black.setStroke()
            for (_, _, path) in curves {
                let path = (chartTransform as NSAffineTransform).transform(path)
                path.lineWidth = 0.5
                path.lineCapStyle = .roundLineCapStyle
                path.lineJoinStyle = .roundLineJoinStyle
                path.stroke()
            }
        }

        // Draw legend background again (with some transparency)
        p.backgroundColor.withAlphaComponent(0.7).setFill()
        p.borderColor.setStroke()
        legendBorder.fill()
        legendBorder.stroke()

        // Draw legend titles
        for (position, title) in legend {
            title.draw(at: position)
        }
    }

    var image: NSImage {
        return NSImage(size: size, flipped: false) { rect in
            self.render(into: rect)
            return true
        }
    }
}

extension Chart: CustomPlaygroundQuickLookable {
    var customPlaygroundQuickLook: PlaygroundQuickLook {
        return .image(self.image)
    }
}
