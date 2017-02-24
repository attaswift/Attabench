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
    var sizeLabel: String {
        return self >= 1 << 40 ? String(format: "%.3gT", Double(self) * 0x1p-40)
            : self >= 1 << 30 ? String(format: "%.3gG", Double(self) * 0x1p-30)
            : self >= 1 << 20 ? String(format: "%.3gM", Double(self) * 0x1p-20)
            : self >= 1024 ? String(format: "%.3gk", Double(self) * 0x1p-10)
            : "\(self)"
    }
}

extension TimeInterval {
    var timeLabel: String {
        return self >= 1000 ? String(Int(self)) + "s"
            : self >= 1 ? String(format: "%.3gs", self)
            : self >= 1e-3 ? String(format: "%.3gms", self * 1e3)
            : self >= 1e-6 ? String(format: "%.3gµs", self * 1e6)
            : self < 1e-9 ? "0s"
            : String(format: "%.3gns", self * 1e9)
    }
}

struct Gridline {
    enum Kind {
        case major
        case minor
    }
    let kind: Kind
    let position: CGFloat
    let label: String?

    init(_ kind: Kind, position: CGFloat, label: String? = nil) {
        self.kind = kind
        self.position = position
        self.label = label
    }
}

protocol ChartScale {
    var min: Double { get }
    var max: Double { get }
    var grid: (major: Double, minor: Double) { get }

    var gridlines: [Gridline] { get }
    func position(for value: Double) -> CGFloat
}

struct EmptyScale: ChartScale {
    let min: Double = 0
    let max: Double = 1
    let grid: (major: Double, minor: Double) = (1, 1)
    let gridlines: [Gridline] = []

    func position(for value: Double) -> CGFloat {
        return CGFloat(value)
    }
}

struct LogarithmicScale: ChartScale {
    let decimal: Bool
    let labeler: (Double) -> String
    let min: Double
    let max: Double
    let grid: (major: Double, minor: Double)

    init(_ range: Range<Double>, decimal: Bool, labeler: @escaping (Double) -> String) {
        precondition(range.lowerBound > 0)
        self.decimal = decimal
        self.labeler = labeler

        let step = decimal ? 10.0 : 2.0

        // Find last major gridline below range.
        if range.lowerBound < 1 {
            var s: Double = 1
            while range.lowerBound * s < 1 {
                s *= step
            }
            self.min = 1 / s
        }
        else {
            var s: Double = 1
            while s * step < range.lowerBound {
                s *= step
            }
            self.min = s
        }

        // Find first major gridline above range.
        var s = self.min
        while s < range.upperBound {
            s *= step
        }
        self.max = s

        self.grid = (major: log(step) / (log(max) - log(min)),
                     minor: decimal ? log(2) / (log(max) - log(min)) : 0)
    }

    var gridlines: [Gridline] {
        var gridlines: [Gridline] = []
        let step = decimal ? 10.0 : 2.0
        var value = self.min
        while value <= self.max {
            let position = self.position(for: value)
            let label = self.labeler(value)
            gridlines.append(Gridline(.major, position: position, label: label))
            value *= step
        }
        if decimal {
            value = 2 * min
            while true {
                let position = self.position(for: value)
                if position > 1.0001 { break }
                gridlines.append(Gridline(.minor, position: position))
                value *= 2
            }
        }
        return gridlines
    }

    func position(for value: Double) -> CGFloat {
        precondition(value > 0)
        return CGFloat((log2(value) - log2(min)) / (log2(max) - log2(min)))
    }
}

extension Array {
    func looped() -> AnyIterator<Element> {
        var i = 0
        return AnyIterator {
            defer { i = (i + 1 == self.count ? 0 : i + 1) }
            return self[i]
        }
    }
}

struct LinearScale: ChartScale {
    let decimal: Bool
    let labeler: (Double) -> String
    let min: Double
    let max: Double
    private let majorScale: Double
    private let minorScale: Double
    let grid: (major: Double, minor: Double)

    init(_ range: Range<Double>, decimal: Bool, labeler: @escaping (Double) -> String) {
        self.decimal = decimal
        self.labeler = labeler

        let steps = (decimal ? [5.0, 2.0] : [2.0]).looped()
        let desiredDelta: Range<Double> = decimal ? 5.0 ..< 20.0 : 4.0 ..< 16.0

        let delta = range.upperBound - range.lowerBound
        var scale = 1.0
        if delta < desiredDelta.lowerBound {
            while scale * delta < desiredDelta.lowerBound {
                scale *= steps.next()!
            }
            scale = 1 / scale
        }
        else if delta > desiredDelta.upperBound {
            while delta > scale * desiredDelta.upperBound {
                scale *= steps.next()!
            }
        }
        self.min = scale * floor(range.lowerBound / scale)
        self.max = scale * ceil(range.upperBound / scale)
        self.majorScale = scale
        self.minorScale = scale / 4

        self.grid = (major: scale / (max - min),
                     minor: decimal ? minorScale / (max - min) : 0)
    }

    var gridlines: [Gridline] {
        var gridlines: [Gridline] = []
        var value = self.min
        while true {
            let position = self.position(for: value)
            if position > 1.0001 { break }
            let label = self.labeler(value)
            gridlines.append(Gridline(.major, position: position, label: label))
            if decimal {
                var v = value + minorScale
                while v < value + majorScale {
                    let p = self.position(for: v)
                    if p > 1.0001 { break }
                    gridlines.append(Gridline(.minor, position: p, label: self.labeler(v)))
                    v += minorScale
                }
            }
            value += majorScale
        }
        return gridlines
    }

    func position(for value: Double) -> CGFloat {
        return CGFloat((value - min) / (max - min))
    }
}

class Chart {
    let size: CGSize
    let suite: Suite
    let title: String
    let amortized: Bool
    let presentationMode: Bool
    let showTitle: Bool

    var curves: [(String, NSColor, NSBezierPath)] = []
    let sizeScale: ChartScale
    let timeScale: ChartScale
    var horizontalHighlight: Range<CGFloat>? = nil

    init(size: CGSize,
         suite: Suite,
         highlightedSizes: ClosedRange<Int>? = nil,
         sizeRange: Range<Int>? = nil,
         timeRange: Range<TimeInterval>? = nil,
         logarithmicSizeScale: Bool = true,
         logarithmicTimeScale: Bool = true,
         amortized: Bool = false,
         presentation: Bool = false,
         showTitle: Bool = true) {
        self.size = size
        self.suite = suite
        self.amortized = amortized
        self.presentationMode = presentation
        self.showTitle = showTitle
        if amortized {
            self.title = suite.suite.descriptiveAmortizedTitle ?? suite.title + " (amortized)"
        }
        else {
            self.title = suite.suite.descriptiveTitle ?? suite.title
        }

        let jobs = suite.selectedJobs

        var minSize = sizeRange?.lowerBound ?? Int.max
        var maxSize = sizeRange?.upperBound ?? Int.min
        if let s = highlightedSizes {
            minSize = min(s.lowerBound, minSize)
            maxSize = max(s.upperBound, maxSize)
        }

        var minTime = timeRange?.lowerBound ?? Double.infinity
        var maxTime = timeRange?.upperBound ?? -Double.infinity
        var count = 0
        for (job, samples) in suite.samplesByJob where jobs.contains(job) {
            for (size, sample) in samples.samplesBySize {
                if size > maxSize { maxSize = size }
                if size < minSize { minSize = size }
                let time = amortized ? sample.minimum / Double(size) : sample.minimum
                if time > maxTime { maxTime = time }
                if time < minTime { minTime = time }
                count += 1
            }
        }

        if count < 2 {
            self.sizeScale = EmptyScale()
            self.timeScale = EmptyScale()
            return
        }

        let sizeLabeler: (Double) -> String = { value in Int(value).sizeLabel }
        if logarithmicSizeScale {
            self.sizeScale = LogarithmicScale(Double(minSize) ..< Double(maxSize), decimal: false, labeler: sizeLabeler)
        }
        else {
            self.sizeScale = LinearScale(Double(minSize) ..< Double(maxSize), decimal: false, labeler: sizeLabeler)
        }

        let timeLabeler: (Double) -> String = { value in TimeInterval(value).timeLabel }
        if logarithmicTimeScale {
            self.timeScale = LogarithmicScale(minTime ..< maxTime, decimal: true, labeler: timeLabeler)
        }
        else {
            self.timeScale = LinearScale(minTime ..< maxTime, decimal: true, labeler: timeLabeler)
        }

        if let s = highlightedSizes {
            self.horizontalHighlight = sizeScale.position(for: Double(s.lowerBound)) ..< sizeScale.position(for: Double(s.upperBound))
        }

        let c = jobs.count
        for i in 0 ..< c {
            let job = jobs[i]
            guard let samples = suite.samplesByJob[job] else { continue }

            let index = suite.jobTitles.index(of: job)!
            let color: NSColor
            if suite.jobTitles.count > 6 {
                color = NSColor(calibratedHue: CGFloat(index) / CGFloat(suite.jobTitles.count),
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
                return CGPoint(x: sizeScale.position(for: Double(size)),
                               y: timeScale.position(for: amortized ? sample.minimum / Double(size) : sample.minimum))
            })

            self.curves.append((job, color, path))
        }
    }

    struct ViewParams {
        let backgroundColor: NSColor
        let titleFont: NSFont
        let titleColor: NSColor
        let borderColor: NSColor
        let borderWidth: CGFloat
        let highlightedBorderWidth: CGFloat
        let majorGridlineColor: NSColor
        let majorGridlineWidth: CGFloat
        let minorGridlineColor: NSColor
        let minorGridlineWidth: CGFloat
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
            borderWidth: 0.5,
            highlightedBorderWidth: 4,
            majorGridlineColor: NSColor(white: 0.3, alpha: 1),
            majorGridlineWidth: 0.75,
            minorGridlineColor: NSColor(white: 0.3, alpha: 1),
            minorGridlineWidth: 0.5,
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
            borderWidth: 0.5,
            highlightedBorderWidth: 4,
            majorGridlineColor: NSColor(white: 0.7, alpha: 1),
            majorGridlineWidth: 0.75,
            minorGridlineColor: NSColor(white: 0.7, alpha: 1),
            minorGridlineWidth: 0.5,
            scaleFont: NSFont(name: "Helvetica-Light", size: 24)!,
            legendFont: NSFont(name: "Menlo", size: 20)!,
            legendColor: NSColor.white,
            legendPadding: 8,
            lineWidth: 8,
            shadowRadius: 3,
            xPadding: 12)

        func gridlineParams(for gridline: Gridline) -> (lineWidth: CGFloat, color: NSColor) {
            switch gridline.kind {
            case .major:
                return (majorGridlineWidth, majorGridlineColor)
            case .minor:
                return (minorGridlineWidth, minorGridlineColor)
            }
        }
    }

    func render(into bounds: NSRect) {
        let p = presentationMode ? ViewParams.presentation : ViewParams.normal

        p.backgroundColor.setFill()
        NSRectFill(bounds)

        let scaleAttributes: [String: Any] = [
            NSFontAttributeName: p.scaleFont,
            NSForegroundColorAttributeName: p.majorGridlineColor
        ]
        let (titleRect, bottomRect) = bounds.divided(
            atDistance: showTitle
                ? 1.2 * (p.titleFont.boundingRectForFont.height + p.titleFont.leading)
                : p.scaleFont.boundingRectForFont.height,
            from: .maxYEdge)

        let scaleWidth = 3 * p.scaleFont.maximumAdvancement.width
        let chartBounds = CGRect(x: bottomRect.minX + scaleWidth,
                                 y: p.scaleFont.boundingRectForFont.height,
                                 width: bottomRect.width - 2 * scaleWidth,
                                 height: bottomRect.height - p.scaleFont.boundingRectForFont.height)
        let largeSize = NSSize(width: 100000, height: 100000)

        // Draw title
        if showTitle {
            let title = NSAttributedString(
                string: self.title,
                attributes: [
                    NSFontAttributeName: p.titleFont,
                    NSForegroundColorAttributeName: p.titleColor,
                    ])
            let titleBounds = title.boundingRect(with: largeSize, options: [], context: nil)
            title.draw(at: CGPoint(x: floor(titleRect.midX - titleBounds.width / 2),
                                   y: floor(titleRect.midY - titleBounds.height / 2)))
        }

        var chartTransform = AffineTransform()
        chartTransform.translate(x: chartBounds.minX, y: chartBounds.minY)
        chartTransform.scale(x: chartBounds.width, y: chartBounds.height)

        let horizontalGridlines = amortized && CGFloat(timeScale.grid.minor) * chartBounds.height > 10
            ? timeScale.gridlines : timeScale.gridlines.filter { $0.kind == .major }
        let verticalGridlines = sizeScale.gridlines

        // Draw horizontal grid lines
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartBounds)
        for gridline in horizontalGridlines {
            let lineParams = p.gridlineParams(for: gridline)
            lineParams.color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: gridline.position))
            path.line(to: CGPoint(x: 1, y: gridline.position))
            path.transform(using: chartTransform)
            if gridline.kind == .minor {
                path.setLineDash([6, 3], count: 2, phase: 0)
            }
            path.lineWidth = lineParams.lineWidth
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Draw vertical grid lines
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartBounds)
        for gridline in verticalGridlines {
            let lineParams = p.gridlineParams(for: gridline)
            lineParams.color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: gridline.position, y: 0))
            path.line(to: CGPoint(x: gridline.position, y: 1))
            path.transform(using: chartTransform)
            path.lineWidth = lineParams.lineWidth
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Draw horizontal grid labels
        var previousFrame = CGRect.null
        for gridline in horizontalGridlines where gridline.kind == .major {
            guard let label = gridline.label else { continue }
            let yMid = chartBounds.minY + gridline.position * chartBounds.height + p.scaleFont.pointSize / 4

            let bounds = (label as NSString).boundingRect(with: largeSize, options: [], attributes: scaleAttributes)
            let leftPos = CGPoint(x: chartBounds.minX - p.xPadding - bounds.width,
                             y: yMid - bounds.height / 2)
            let rightPos = CGPoint(x: chartBounds.maxX + p.xPadding,
                                   y: yMid - bounds.height / 2)
            let frame = bounds.offsetBy(dx: leftPos.x, dy: leftPos.y).insetBy(dx: 0, dy: -3)
            guard !previousFrame.intersects(frame) else { continue }
            (label as NSString).draw(at: leftPos, withAttributes: scaleAttributes)
            (label as NSString).draw(at: rightPos, withAttributes: scaleAttributes)
            previousFrame = frame
        }

        // Draw vertical grid labels
        previousFrame = .null
        for gridline in verticalGridlines {
            guard let label = gridline.label else { continue }
            let xMid = chartBounds.minX + gridline.position * chartBounds.width
            let yTop = chartBounds.minY - 3

            let bounds = (label as NSString).boundingRect(with: largeSize, options: [], attributes: scaleAttributes)
            let pos = CGPoint(x: xMid - bounds.width / 2, y: yTop - bounds.height)
            let frame = bounds.offsetBy(dx: pos.x, dy: pos.y).insetBy(dx: -3, dy: 0)
            guard !previousFrame.intersects(frame) else { continue }
            (label as NSString).draw(at: pos, withAttributes: scaleAttributes)
            previousFrame = frame
        }

        // Draw border
        p.borderColor.setStroke()
        let border = NSBezierPath(rect: chartBounds.insetBy(dx: -0.25, dy: -0.25))
        border.lineWidth = p.borderWidth
        border.stroke()

        if let h = horizontalHighlight {
            let highlight = NSBezierPath()
            highlight.move(to: .init(x: h.lowerBound, y: 1))
            highlight.line(to: .init(x: h.upperBound, y: 1))
            highlight.move(to: .init(x: h.lowerBound, y: 0))
            highlight.line(to: .init(x: h.upperBound, y: 0))
            highlight.transform(using: chartTransform)
            highlight.lineWidth = p.highlightedBorderWidth
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
        NSGraphicsContext.restoreGraphicsState()

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
