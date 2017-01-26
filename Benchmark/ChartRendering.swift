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
    let suite: BenchmarkSuiteProtocol
    let title: String

    var curves: [(String, NSColor, NSBezierPath)] = []
    var verticalGridLines: [(String?, CGFloat)] = []
    var horizontalGridLines: [(String?, CGFloat)] = []

    init(size: CGSize,
         suite: BenchmarkSuiteProtocol,
         results: BenchmarkSuiteResults,
         sizeRange: Range<Int>? = nil,
         timeRange: Range<TimeInterval>? = nil,
         amortized: Bool = false) {
        self.size = size
        self.suite = suite
        if amortized {
            self.title = suite.descriptiveAmortizedTitle ?? suite.title + " (amortized)"
        }
        else {
            self.title = suite.descriptiveTitle ?? suite.title
        }
        var minSize = sizeRange?.lowerBound ?? Int.max
        var maxSize = sizeRange?.upperBound ?? Int.min
        var minTime = timeRange?.lowerBound ?? Double.infinity
        var maxTime = timeRange?.upperBound ?? -Double.infinity
        var count = 0
        for (_, samples) in results.samplesByBenchmark {
            for (size, sample) in samples.samples {
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

        do {
            var size = minSize
            while size <= maxSize {
                if size >= minSize {
                    let x = scaleX * log2(CGFloat(size))
                    verticalGridLines.append((size.label, x))
                }
                size <<= 1
            }
        }

        do {
            var time = minTime
            while time <= maxTime {
                horizontalGridLines.append((time.label, y(1, time)))

                for m: Double in [2, 4, 6, 8] {
                    let yc = y(1, m * time)
                    if yc <= 1 { horizontalGridLines.append((nil, yc)) }
                }
                time *= 10
            }
        }

        let c = suite.benchmarkTitles.count
        for i in 0 ..< c {
            let benchmark = suite.benchmarkTitles[i]
            guard let samples = results.samplesByBenchmark[benchmark] else { continue }

            let color: NSColor
            if c > 6 {
                color = NSColor(calibratedHue: CGFloat(i) / CGFloat(c), saturation: 1, brightness: 1, alpha: 1)
            }
            else {
                // Use stable colors when possible.
                // These particular ones are nice because people with most forms of color blindness can still
                // differentiate them.
                switch i {
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
            path.appendLines(between: samples.samples.sorted(by: { $0.0 < $1.0 }).map { (size, sample) in
                return CGPoint(x: x(size), y: y(size, sample.minimum))
            })

            self.curves.append((benchmark, color, path))
        }
    }

    func render(into bounds: NSRect) {
        NSColor.black.setFill()
        NSRectFill(bounds)

        let borderColor =  NSColor.white
        let majorGridLineColor = NSColor(white: 0.7, alpha: 1)
        let minorGridLineColor = NSColor(white: 0.3, alpha: 1)

        let titleFont = NSFont(name: "HelveticaNeue-Light", size: 24)!
        let legendFont = NSFont(name: "HelveticaNeue-Light", size: 16)!
        let scaleFont = NSFont(name: "HelveticaNeue-Light", size: 12)!
        let scaleAttributes: [String: Any] = [
            NSFontAttributeName: scaleFont,
            NSForegroundColorAttributeName: majorGridLineColor
        ]

        let (titleRect, bottomRect) = bounds.divided(atDistance: 0.1 * bounds.height, from: .maxYEdge)

        let chartBounds = CGRect(x: bottomRect.minX + 0.1 * bottomRect.width, y: 32, width: 0.8 * bottomRect.width, height: bottomRect.height - 32)
        let largeSize = NSSize(width: 100000, height: 100000)

        // Draw title
        let title = NSAttributedString(
            string: self.title,
            attributes: [
                NSFontAttributeName: titleFont,
                NSForegroundColorAttributeName: NSColor.white
            ])
        let titleBounds = title.boundingRect(with: largeSize, options: [], context: nil)
        title.draw(at: CGPoint(x: floor(titleRect.midX - titleBounds.width / 2), y: floor(titleRect.midY - titleBounds.height / 2)))

        var chartTransform = AffineTransform()
        chartTransform.translate(x: chartBounds.minX, y: chartBounds.minY)
        chartTransform.scale(x: chartBounds.width, y: chartBounds.height)

        // Draw horizontal grid lines
        for (title, y) in horizontalGridLines {
            let color = title == nil ? minorGridLineColor : majorGridLineColor
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: 1, y: y))
            path.transform(using: chartTransform)
            path.lineWidth = 0.5
            path.stroke()

            if let title = title {
                let yMid = chartBounds.minY + y * chartBounds.height + scaleFont.pointSize / 4
                let xMax = chartBounds.minX - 6

                let bounds = (title as NSString).boundingRect(with: largeSize, options: [], attributes: scaleAttributes)
                (title as NSString).draw(at: CGPoint(x: xMax - bounds.width, y: yMid - bounds.height / 2), withAttributes: scaleAttributes)
            }
        }

        // Draw vertical grid lines
        for (title, x) in verticalGridLines {
            let color = title == nil ? minorGridLineColor : majorGridLineColor
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
        borderColor.setStroke()
        let border = NSBezierPath(rect: chartBounds.insetBy(dx: -0.25, dy: -0.25))
        border.lineWidth = 0.5
        border.stroke()

        // Draw curves
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartBounds)
        for (_, color, path) in curves {
            color.setStroke()
            let path = (chartTransform as NSAffineTransform).transform(path)
            path.lineWidth = 4
            path.lineCapStyle = .roundLineCapStyle
            path.lineJoinStyle = .roundLineJoinStyle
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        if !curves.isEmpty {
            // Draw legend
            let legendMinX = chartBounds.minX + min(0.1 * chartBounds.width, 0.1 * chartBounds.height)
            let legendMaxY = chartBounds.maxY - min(0.1 * chartBounds.width, 0.1 * chartBounds.height)
            var legendMaxX = legendMinX
            var legendMinY = legendMaxY
            var legend: [(position: CGPoint, title: NSAttributedString)] = []
            for (title, color, _) in curves {
                let title = NSMutableAttributedString(string: "◼︎ " + title, attributes: [
                    NSFontAttributeName: legendFont,
                    NSForegroundColorAttributeName: majorGridLineColor
                    ])
                title.setAttributes([NSForegroundColorAttributeName: color], range: NSRange(0 ..< 1))
                let titleBounds = title.boundingRect(with: largeSize, options: [])
                legendMinY -= titleBounds.height
                legend.append((CGPoint(x: legendMinX, y: legendMinY), title))
                legendMinY -= legendFont.leading
                legendMaxX = max(legendMaxX, legendMinX + titleBounds.width)
            }
            //legendMinY += legendFont.leading
            let legendRect = CGRect(x: legendMinX, y: legendMinY, width: legendMaxX - legendMinX, height: legendMaxY - legendMinY)
                .insetBy(dx: -12, dy: -12)
            NSColor.black.setFill()
            NSColor.white.setStroke()
            let legendBorder = NSBezierPath(rect: legendRect)
            legendBorder.lineWidth = 0.5
            legendBorder.fill()
            legendBorder.stroke()
            
            for (position, title) in legend {
                title.draw(at: position)
            }
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
