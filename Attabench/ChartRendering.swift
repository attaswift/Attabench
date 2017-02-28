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
    let suite: Suite
    let title: String
    let amortized: Bool

    var curves: [(String, NSColor, NSBezierPath)] = []
    let sizeScale: ChartScale
    let timeScale: ChartScale
    var horizontalHighlight: Range<CGFloat>? = nil

    init(suite: Suite,
         highlightedSizes: ClosedRange<Int>? = nil,
         sizeRange: Range<Int>? = nil,
         timeRange: Range<TimeInterval>? = nil,
         logarithmicSizeScale: Bool = true,
         logarithmicTimeScale: Bool = true,
         amortized: Bool = false,
         presentation: Bool = false) {
        self.suite = suite
        self.amortized = amortized
        if amortized {
            self.title = suite.benchmark.descriptiveAmortizedTitle ?? suite.title + " (amortized)"
        }
        else {
            self.title = suite.benchmark.descriptiveTitle ?? suite.title
        }

        let tasks = suite.selectedTasks

        var minSize = sizeRange?.lowerBound ?? Int.max
        var maxSize = sizeRange?.upperBound ?? Int.min
        if let s = highlightedSizes {
            minSize = min(s.lowerBound, minSize)
            maxSize = max(s.upperBound, maxSize)
        }

        var minTime = timeRange?.lowerBound ?? Double.infinity
        var maxTime = timeRange?.upperBound ?? -Double.infinity
        var count = 0
        for (task, samples) in suite.samplesByTask where tasks.contains(task) {
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

        let c = tasks.count
        for i in 0 ..< c {
            let task = tasks[i]
            guard let samples = suite.samplesByTask[task] else { continue }

            let index = suite.taskTitles.index(of: task)!
            let color: NSColor
            if suite.taskTitles.count > 6 {
                color = NSColor(calibratedHue: CGFloat(index) / CGFloat(suite.taskTitles.count),
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

            self.curves.append((task, color, path))
        }
    }
}

struct ChartTheme {
    struct LineParams {
        let lineWidth: CGFloat
        let dash: [CGFloat]
        let phase: CGFloat

        init(lineWidth: CGFloat, dash: [CGFloat] = [], phase: CGFloat = 0) {
            self.lineWidth = lineWidth
            self.dash = dash
            self.phase = phase
        }

        func apply(on path: NSBezierPath) {
            path.lineWidth = lineWidth
            path.setLineDash(dash, count: dash.count, phase: phase)
        }
    }

    let backgroundColor: NSColor
    let titleFont: NSFont
    let titleColor: NSColor
    let borderColor: NSColor
    let borderWidth: CGFloat
    let highlightedBorderWidth: CGFloat
    let majorGridlineColor: NSColor
    let majorGridlineParams: LineParams
    let minorGridlineColor: NSColor
    let minorGridlineParams: LineParams
    let axisLabelFont: NSFont
    let legendFont: NSFont
    let legendColor: NSColor
    let legendPadding: CGFloat
    let lineParams: LineParams
    let shadowRadius: CGFloat
    let hairline: Bool
    let xPadding: CGFloat

    static let normal = ChartTheme(
        backgroundColor: NSColor.white,
        titleFont: NSFont(name: "Helvetica-Light", size: 24)!,
        titleColor: NSColor.black,
        borderColor: NSColor.black,
        borderWidth: 0.5,
        highlightedBorderWidth: 4,
        majorGridlineColor: NSColor(white: 0.3, alpha: 1),
        majorGridlineParams: LineParams(lineWidth: 0.75),
        minorGridlineColor: NSColor(white: 0.3, alpha: 1),
        minorGridlineParams: LineParams(lineWidth: 0.5, dash: [6, 3]),
        axisLabelFont: NSFont(name: "Helvetica-Light", size: 10)!,
        legendFont: NSFont(name: "Menlo", size: 12)!,
        legendColor: NSColor.black,
        legendPadding: 6,
        lineParams: LineParams(lineWidth: 4),
        shadowRadius: 0,
        hairline: true,
        xPadding: 6)

    static let presentation = ChartTheme(
        backgroundColor: NSColor.black,
        titleFont: NSFont(name: "Helvetica-Light", size: 48)!,
        titleColor: NSColor.white,
        borderColor: NSColor.white,
        borderWidth: 0.5,
        highlightedBorderWidth: 4,
        majorGridlineColor: NSColor(white: 0.7, alpha: 1),
        majorGridlineParams: LineParams(lineWidth: 0.75),
        minorGridlineColor: NSColor(white: 0.7, alpha: 1),
        minorGridlineParams: LineParams(lineWidth: 0.5, dash: [6, 3]),
        axisLabelFont: NSFont(name: "Helvetica-Light", size: 24)!,
        legendFont: NSFont(name: "Menlo", size: 20)!,
        legendColor: NSColor.white,
        legendPadding: 8,
        lineParams: LineParams(lineWidth: 8),
        shadowRadius: 3,
        hairline: false,
        xPadding: 12)

    func lineParams(for kind: Gridline.Kind) -> (color: NSColor, params: LineParams) {
        switch kind {
        case .major:
            return (majorGridlineColor, majorGridlineParams)
        case .minor:
            return (minorGridlineColor, minorGridlineParams)
        }
    }

    func axisLabelAttributes() -> [String: Any] {
        return [
            NSFontAttributeName: axisLabelFont,
            NSForegroundColorAttributeName: majorGridlineColor
        ]
    }
}

struct ChartRenderer {
    let rect: CGRect
    let chart: Chart
    let theme: ChartTheme
    let showTitle: Bool

    let chartRect: CGRect
    let chartTransform: AffineTransform

    let legend: (position: LegendPosition, distance: CGSize)?

    enum LegendPosition {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    init(rect: CGRect, chart: Chart, theme: ChartTheme, showTitle: Bool, legend: (position: LegendPosition, distance: CGSize)?) {
        self.rect = rect
        self.chart = chart
        self.theme = theme
        self.showTitle = showTitle
        self.legend = legend

        let bottomRect = rect.divided(
            atDistance: showTitle
                ? 1.2 * (theme.titleFont.boundingRectForFont.height + theme.titleFont.leading)
                : theme.axisLabelFont.boundingRectForFont.height,
            from: .maxYEdge).remainder

        let scaleWidth = 3 * theme.axisLabelFont.maximumAdvancement.width
        self.chartRect = CGRect(x: bottomRect.minX + scaleWidth,
                                y: theme.axisLabelFont.boundingRectForFont.height,
                                width: bottomRect.width - 2 * scaleWidth,
                                height: bottomRect.height - theme.axisLabelFont.boundingRectForFont.height - theme.axisLabelFont.leading)

        var chartTransform = AffineTransform()
        chartTransform.translate(x: chartRect.minX, y: chartRect.minY)
        chartTransform.scale(x: chartRect.width, y: chartRect.height)
        self.chartTransform = chartTransform
    }

    var image: NSImage {
        return NSImage(size: rect.integral.size, flipped: false) { rect in
            (AffineTransform(translationByX: -self.rect.minX, byY: -self.rect.minY) as NSAffineTransform).concat()
            self.draw()
            return true
        }
    }

    func draw() {
        drawBackground()

        if showTitle {
            drawTitle()
        }

        drawYAxis()
        drawXAxis()
        drawBorder()

        if let range = chart.horizontalHighlight {
            drawHighlight(range)
        }

        guard !chart.curves.isEmpty else { return }

        if let legendLayout = self.legendLayout() {
            drawLegendBackground(with: legendLayout)
            drawCurves()
            drawLegendContents(with: legendLayout)
        }
        else {
            drawCurves()
        }
    }

    func drawBackground() {
        theme.backgroundColor.setFill()
        NSRectFill(rect)
    }

    func drawTitle() {
        let titleRect = CGRect(x: rect.minX,
                               y: chartRect.maxY,
                               width: rect.width,
                               height: rect.maxY - chartRect.maxY)

        let paragraphStyle = NSParagraphStyle.default().mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: chart.title,
            attributes: [
                NSFontAttributeName: theme.titleFont,
                NSForegroundColorAttributeName: theme.titleColor,
                NSParagraphStyleAttributeName: paragraphStyle,
                ])
        title.draw(with: titleRect, options: .usesLineFragmentOrigin)
    }

    func drawYAxis() {
        let gridlines = chart.amortized && CGFloat(chart.timeScale.grid.minor) * chartRect.height > 10
            ? chart.timeScale.gridlines : chart.timeScale.gridlines.filter { $0.kind == .major }

        // Draw gridlines
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartRect)
        for gridline in gridlines {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: gridline.position))
            path.line(to: CGPoint(x: 1, y: gridline.position))
            path.transform(using: chartTransform)
            let (color, lineParams) = theme.lineParams(for: gridline.kind)
            lineParams.apply(on: path)
            color.setStroke()
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // Draw labels
        var previousFrame = CGRect.null
        let attributes = theme.axisLabelAttributes()
        for gridline in gridlines where gridline.kind == .major {
            guard let label = gridline.label else { continue }
            let yMid = chartRect.minY + gridline.position * chartRect.height + theme.axisLabelFont.pointSize / 4

            let bounds = (label as NSString).boundingRect(with: CGSize(width: 1000, height: 1000),
                                                          options: [], attributes: attributes)
            let leftPos = CGPoint(x: chartRect.minX - theme.xPadding - bounds.width,
                                  y: yMid - bounds.height / 2)
            let rightPos = CGPoint(x: chartRect.maxX + theme.xPadding,
                                   y: yMid - bounds.height / 2)
            let frame = bounds.offsetBy(dx: leftPos.x, dy: leftPos.y).insetBy(dx: 0, dy: -3)
            guard !previousFrame.intersects(frame) else { continue }
            (label as NSString).draw(at: leftPos, withAttributes: attributes)
            (label as NSString).draw(at: rightPos, withAttributes: attributes)
            previousFrame = frame
        }
    }

    func drawXAxis() {
        let gridlines = chart.sizeScale.gridlines
        let attributes = theme.axisLabelAttributes()

        // Calculate frames for labels on the size axis
        typealias LabelGeometry = (gridline: Gridline, position: CGPoint, frame: CGRect)
        var labels: [LabelGeometry] = []
        var secondary: [Gridline] = []
        for gridline in gridlines {
            guard let label = gridline.label else { secondary.append(gridline); continue }
            let xMid = chartRect.minX + gridline.position * chartRect.width
            let yTop = chartRect.minY - 3

            let bounds = (label as NSString).boundingRect(with: CGSize(width: 1000, height: 1000), options: [], attributes: attributes)
            let pos = CGPoint(x: xMid - bounds.width / 2, y: yTop - bounds.height)
            let frame = bounds.offsetBy(dx: pos.x, dy: pos.y)
            labels.append((gridline, pos, frame))
        }
        func needsThinning(_ frames: [LabelGeometry]) -> Bool {
            var previousFrame: CGRect = .null
            for (_, _, frame) in frames where !frame.isNull {
                let enlarged = frame.insetBy(dx: -3, dy: 0)
                if previousFrame.intersects(enlarged) { return true }
                previousFrame = enlarged
            }
            return false
        }
        while needsThinning(labels) {
            for i in stride(from: 1, to: labels.count, by: 2).reversed() {
                secondary.append(labels.remove(at: i).gridline)
            }
        }

        // Draw labels
        for (gridline, pos, _) in labels {
            (gridline.label! as NSString).draw(at: pos, withAttributes: attributes)
        }

        // Draw grid lines
        func draw(_ gridline: Gridline, labeled: Bool) {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: gridline.position, y: 0))
            path.line(to: CGPoint(x: gridline.position, y: 1))
            path.transform(using: chartTransform)
            let (color, lineParams) = theme.lineParams(for: labeled ? .major : .minor)
            lineParams.apply(on: path)
            color.setStroke()
            path.stroke()
        }
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartRect)
        for (gridline, _, _) in labels {
            draw(gridline, labeled: true)
        }
        for gridline in secondary {
            draw(gridline, labeled: false)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawBorder() {
        theme.borderColor.setStroke()
        let border = NSBezierPath(rect: chartRect.insetBy(dx: -0.25, dy: -0.25))
        border.lineWidth = theme.borderWidth
        border.stroke()
    }

    func drawHighlight(_ range: Range<CGFloat>) {
        let highlight = NSBezierPath()
        highlight.move(to: .init(x: range.lowerBound, y: 1))
        highlight.line(to: .init(x: range.upperBound, y: 1))
        highlight.move(to: .init(x: range.lowerBound, y: 0))
        highlight.line(to: .init(x: range.upperBound, y: 0))
        highlight.transform(using: chartTransform)
        highlight.lineWidth = theme.highlightedBorderWidth
        highlight.lineCapStyle = .roundLineCapStyle
        highlight.stroke()
    }

    func drawCurves() {
        NSGraphicsContext.saveGraphicsState()
        NSRectClip(chartRect)
        if theme.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = theme.shadowRadius
            shadow.shadowOffset = .zero
            shadow.shadowColor = .black
            shadow.set()
        }
        for (_, color, path) in chart.curves {
            color.setStroke()
            let path = (chartTransform as NSAffineTransform).transform(path)
            path.lineCapStyle = .roundLineCapStyle
            path.lineJoinStyle = .roundLineJoinStyle
            theme.lineParams.apply(on: path)
            path.stroke()
        }
        if theme.hairline {
            NSColor.black.setStroke()
            for (_, _, path) in chart.curves {
                let path = (chartTransform as NSAffineTransform).transform(path)
                path.lineWidth = 0.5
                path.lineCapStyle = .roundLineCapStyle
                path.lineJoinStyle = .roundLineJoinStyle
                path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    typealias LegendLayout = (frame: CGRect, contents: [(position: CGPoint, text: NSAttributedString)])
    func legendLayout() -> LegendLayout? {
        guard let legend = self.legend else { return nil }
        let attributes = [
            NSFontAttributeName: theme.legendFont,
            NSForegroundColorAttributeName: theme.legendColor
        ]
        var contents: [(position: CGPoint, text: NSAttributedString)] = []
        var y = theme.legendPadding - theme.legendFont.descender
        var width: CGFloat = 0
        for (title, color, _) in chart.curves.reversed() {
            let title = NSMutableAttributedString(string: "◼︎ " + title, attributes: attributes)
            title.setAttributes([NSForegroundColorAttributeName: color],
                                range: NSRange(0 ..< 1))

            contents.append((CGPoint(x: theme.legendPadding, y: y), title))
            let bounds = title.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin, context: nil)
            y += bounds.minY + bounds.height + theme.legendFont.leading
            width = max(width, bounds.width)
        }
        y += theme.legendPadding - theme.legendFont.leading
        let legendSize = CGSize(width: width + 2 * theme.legendPadding, height: y)

        var pos = CGPoint.zero
        switch legend.position {
        case .topLeft, .bottomLeft:
            pos.x = chartRect.minX + legend.distance.width
        case .topRight, .bottomRight:
            pos.x = chartRect.maxX - legend.distance.width - legendSize.width
        }
        switch legend.position {
        case .topLeft, .topRight:
            pos.y = chartRect.maxY - legend.distance.height - legendSize.height
        case .bottomLeft, .bottomRight:
            pos.y = chartRect.minY + legend.distance.height
        }

        let frame = CGRect(origin: pos, size: legendSize)
        return (frame, contents)
    }

    func drawLegendBackground(with layout: LegendLayout) {
        theme.backgroundColor.setFill()
        NSRectFill(layout.frame)
    }

    func drawLegendContents(with layout: LegendLayout) {
        // Draw background again, with some transparency and borders.
        theme.backgroundColor.withAlphaComponent(0.7).setFill()
        theme.borderColor.setStroke()
        let legendBorder = NSBezierPath(rect: layout.frame)
        legendBorder.lineWidth = 0.5
        legendBorder.fill()
        legendBorder.stroke()

        // Draw legend titles
        for (position, title) in layout.contents {
            title.draw(at: CGPoint(x: layout.frame.minX + position.x,
                                   y: layout.frame.minY + position.y))
        }
    }
}

extension Chart: CustomPlaygroundQuickLookable {
    var customPlaygroundQuickLook: PlaygroundQuickLook {
        let renderer = ChartRenderer(rect: CGRect(x: 0, y: 0, width: 1024, height: 640),
                                     chart: self, theme: .normal,
                                     showTitle: true,
                                     legend: (position: .topLeft, distance: CGSize(width: 32, height: 32)))
        return .image(renderer.image)
    }
}

extension ChartRenderer: CustomPlaygroundQuickLookable {
    var customPlaygroundQuickLook: PlaygroundQuickLook {
        return .image(self.image)
    }
}
