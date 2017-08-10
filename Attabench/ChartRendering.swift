//
//  ChartRendering.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
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

    func setLineDash(_ dashes: [CGFloat]) {
        self.setLineDash(dashes, count: dashes.count, phase: 0)
    }

    func stroke(with params: LineParams) {
        NSGraphicsContext.saveGraphicsState()
        params.apply(on: self)
        params.color.setStroke()
        if params.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = params.shadowRadius
            shadow.shadowOffset = .zero
            shadow.shadowColor = .black
            shadow.set()
        }
        self.stroke()
        NSGraphicsContext.restoreGraphicsState()
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

    func repeated(_ count: Int) -> [Element] {
        precondition(count >= 0)
        var result: [Element] = []
        result.reserveCapacity(self.count * count)
        for _ in 0 ..< count {
            result += self
        }
        return result
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
            : self >= 1e-9 ? String(format: "%.3gns", self * 1e9)
            : self < 1e-12 ? "0s"
            : String(format: "%.3gps", self * 1e12)
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

struct Curve {
    let title: String
    let path: NSBezierPath
}

class Chart {
    let suite: Suite
    let title: String
    let amortized: Bool

    var curves: [Curve] = []
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
            self.title = suite.benchmark.descriptiveAmortizedTitle
                ?? suite.benchmark.descriptiveTitle?.appending(" (amortized)")
                ?? suite.title.appending(" (amortized)")
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

//        maxSize = min(maxSize, 1 << 22)
//        maxTime = min(maxTime, 10e-6)
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

        for task in tasks {
            guard let samples = suite.samplesByTask[task] else { continue }

            let path = NSBezierPath()
            path.appendLines(between: samples.samplesBySize.sorted(by: { $0.0 < $1.0 }).map { (size, sample) in
                return CGPoint(x: sizeScale.position(for: Double(size)),
                               y: timeScale.position(for: amortized ? sample.minimum / Double(size) : sample.minimum))
            })

            self.curves.append(Curve(title: task, path: path))
        }
    }
}

struct LineParams {
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

struct TextParams {
    let font: NSFont
    let color: NSColor

    var attributes: [NSAttributedStringKey: Any] {
        return [.foregroundColor: color,
                .font: font]
    }
}

enum ChartTheme: Int {
    case screen
    case presentation
    case colorPrint
    case monoPrint

    static var allThemes: [ChartTheme] = [.screen, .presentation, .colorPrint, .monoPrint]

    var label: String {
        switch self {
        case .screen: return "Screen"
        case .presentation: return "Presentation"
        case .colorPrint: return "Color Print"
        case .monoPrint: return "Monochrome Print"
        }
    }
    
    var imageSize: CGSize? {
        switch self {
        case .screen:
            return nil
        case .presentation:
            return CGSize(width: 1280, height: 720)
        case .colorPrint, .monoPrint:
            return CGSize(width: 800, height: 260)
        }
    }

    #if OBJCIO
    private static let labelFontName = "Tiempos Text"
    private static let monoFontName = "Akkurat TT"
    #elseif LORENTEY
    private static let labelFontName = "Palatino"
    private static let monoFontName = "InputSansNarrow-Regular"
    #else
    private static let labelFontName = "Helvetica-Light"
    private static let monoFontName = "Menlo"
    #endif

    private static func colorLineParams(index: Int, count: Int, lineWidth: CGFloat, hairLine: Bool, shadowRadius: CGFloat = 0) -> [LineParams] {
        let color: NSColor
        if count > 6 {
            color = NSColor(calibratedHue: CGFloat(index) / CGFloat(count),
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
        if hairLine {
            return [LineParams(lineWidth: lineWidth, color: color, shadowRadius: shadowRadius),
                    LineParams(lineWidth: 0.5, color: .black)]
        }
        else {
            return [LineParams(lineWidth: lineWidth, color: color, shadowRadius: shadowRadius)]
        }
    }

    private static func monoLineParams(index: Int, count: Int, lineWidth: CGFloat) -> [LineParams] {
        let dash: [CGFloat]
        switch index {
        case 0: dash = []
        case 1: dash = [6, 3]
        case 2: dash = [0, 3]
        default:
            dash = [6, 3] + [0, 3].repeated(index - 2)
        }
        return [LineParams(lineWidth: lineWidth, color: .black, dash: dash)]
    }

    static let screenParams = ChartParams(
        marginRatio: (0.05, 0.05),
        backgroundColor: NSColor.white,
        title: TextParams(font: NSFont(name: labelFontName, size: 24)!, color: NSColor.black),
        border: LineParams(lineWidth: 0.5, color: NSColor.black),
        highlightedBorder: LineParams(lineWidth: 4, color: NSColor.black),
        majorGridline: LineParams(lineWidth: 0.75, color: NSColor(white: 0.3, alpha: 1)),
        minorGridline: LineParams(lineWidth: 0.5, color: NSColor(white: 0.3, alpha: 1), dash: [6, 3]),
        axisLabel: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black),
        legend: TextParams(font: NSFont(name: monoFontName, size: 12)!, color: .black),
        legendPadding: 6,
        legendSampleLine: false,
        lineParams: { i, c in colorLineParams(index: i, count: c, lineWidth: 4, hairLine: true) },
        xPadding: 6)

    private static let presentationParams = ChartParams(
        marginRatio: (0, 0),
        backgroundColor: NSColor.black,
        title: TextParams(font: NSFont(name: labelFontName, size: 48)!, color: NSColor.white),
        border: LineParams(lineWidth: 0.5, color: NSColor.white),
        highlightedBorder: LineParams(lineWidth: 4, color: NSColor.white),
        majorGridline: LineParams(lineWidth: 0.75, color: NSColor(white: 0.3, alpha: 1)),
        minorGridline: LineParams(lineWidth: 0.5, color: NSColor(white: 0.7, alpha: 1), dash: [6, 3]),
        axisLabel: TextParams(font: NSFont(name: labelFontName, size: 24)!, color: .white),
        legend: TextParams(font: NSFont(name: monoFontName, size: 20)!, color: .white),
        legendPadding: 8,
        legendSampleLine: false,
        lineParams: { i, c in colorLineParams(index: i, count: c, lineWidth: 8, hairLine: false, shadowRadius: 3) },
        xPadding: 12)

    private static let colorPrintParams = ChartParams(
        marginRatio: (0, 0),
        backgroundColor: NSColor.white,
        title: TextParams(font: NSFont(name: labelFontName, size: 12)!, color: .black),
        border: LineParams(lineWidth: 1, color: .black),
        highlightedBorder: LineParams(lineWidth: 4, color: .black),
        majorGridline: LineParams(lineWidth: 0.7, color: NSColor(white: 0.6, alpha: 1)),
        minorGridline: LineParams(lineWidth: 0.4, color: NSColor(white: 0.6, alpha: 1), dash: [2, 1]),
        axisLabel: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black),
        legend: TextParams(font: NSFont(name: monoFontName, size: 10)!, color: .black),
        legendPadding: 6,
        legendSampleLine: false,
        lineParams: { i, c in colorLineParams(index: i, count: c, lineWidth: 4, hairLine: true) },
        xPadding: 6)

    private static let monoPrintParams = ChartParams(
        marginRatio: (0, 0),
        backgroundColor: NSColor.white,
        title: TextParams(font: NSFont(name: labelFontName, size: 12)!, color: .black),
        border: LineParams(lineWidth: 1, color: .black),
        highlightedBorder: LineParams(lineWidth: 4, color: .black),
        majorGridline: LineParams(lineWidth: 0.7, color: NSColor(white: 0.6, alpha: 1)),
        minorGridline: LineParams(lineWidth: 0.4, color: NSColor(white: 0.6, alpha: 1), dash: [2, 1]),
        axisLabel: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black),
        legend: TextParams(font: NSFont(name: monoFontName, size: 10)!, color: .black),
        legendPadding: 6,
        legendSampleLine: true,
        lineParams: { i, c in monoLineParams(index: i, count: c, lineWidth: 2) },
        xPadding: 6)

    var params: ChartParams {
        switch self {
        case .screen:
            return ChartTheme.screenParams
        case .presentation:
            return ChartTheme.presentationParams
        case .colorPrint:
            return ChartTheme.colorPrintParams
        case .monoPrint:
            return ChartTheme.monoPrintParams
        }
    }
}

struct ChartParams {
    let marginRatio: (CGFloat, CGFloat)
    let backgroundColor: NSColor
    let title: TextParams
    let border: LineParams
    let highlightedBorder: LineParams
    let majorGridline: LineParams
    let minorGridline: LineParams
    let axisLabel: TextParams
    let legend: TextParams
    let legendPadding: CGFloat
    let legendSampleLine: Bool
    let lineParams: (Int, Int) -> [LineParams]
    let xPadding: CGFloat

    func lineParams(for kind: Gridline.Kind) -> LineParams {
        switch kind {
        case .major: return majorGridline
        case .minor: return minorGridline
        }
    }
}

struct ChartRenderer {
    let rect: CGRect
    let bounds: CGRect
    let chart: Chart
    let params: ChartParams
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
        self.params = theme.params
        self.rect = rect
        self.bounds = CGRect(x: rect.midX - (rect.width * (0.5 - params.marginRatio.0)),
                             y: rect.midY - (rect.height * (0.5 - params.marginRatio.1)),
                             width: rect.width * (1 - 2 * params.marginRatio.0),
                             height: rect.height * (1 - 2 * params.marginRatio.1))
        self.chart = chart
        self.showTitle = showTitle
        self.legend = legend

        let bottomRect = bounds.divided(
            atDistance: showTitle
                ? 1.2 * (params.title.font.boundingRectForFont.height + params.title.font.leading)
                : params.axisLabel.font.boundingRectForFont.height,
            from: .maxYEdge).remainder

        let scaleWidth = 3 * params.axisLabel.font.maximumAdvancement.width
        self.chartRect = CGRect(x: bottomRect.minX + scaleWidth,
                                y: bottomRect.minY + params.axisLabel.font.boundingRectForFont.height,
                                width: bottomRect.width - 2 * scaleWidth,
                                height: bottomRect.height - params.axisLabel.font.boundingRectForFont.height - params.axisLabel.font.leading)

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
        params.backgroundColor.setFill()
        rect.fill()
    }

    func drawTitle() {
        let titleRect = CGRect(x: bounds.minX,
                               y: chartRect.maxY,
                               width: bounds.width,
                               height: bounds.maxY - chartRect.maxY)
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: chart.title,
            attributes: [
                .font: params.title.font,
                .foregroundColor: params.title.color,
                .paragraphStyle: paragraphStyle,
                ])
        title.draw(with: titleRect, options: .usesLineFragmentOrigin)
    }

    func drawYAxis() {
        let gridlines = chart.amortized && CGFloat(chart.timeScale.grid.minor) * chartRect.height > 10
            ? chart.timeScale.gridlines : chart.timeScale.gridlines.filter { $0.kind == .major }

        // Draw gridlines
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        for gridline in gridlines {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: gridline.position))
            path.line(to: CGPoint(x: 1, y: gridline.position))
            path.transform(using: chartTransform)
            path.stroke(with: params.lineParams(for: gridline.kind))
        }
        NSGraphicsContext.restoreGraphicsState()

        // Draw labels
        NSGraphicsContext.saveGraphicsState()
        var previousFrame = CGRect.null
        let attributes = params.axisLabel.attributes
        for gridline in gridlines where gridline.kind == .major {
            guard let label = gridline.label else { continue }
            let yMid = chartRect.minY + gridline.position * chartRect.height + params.axisLabel.font.pointSize / 4

            let bounds = (label as NSString).boundingRect(with: CGSize(width: 1000, height: 1000),
                                                          options: [], attributes: attributes)
            let leftPos = CGPoint(x: chartRect.minX - params.xPadding - bounds.width,
                                  y: yMid - bounds.height / 2)
            let rightPos = CGPoint(x: chartRect.maxX + params.xPadding,
                                   y: yMid - bounds.height / 2)
            let frame = bounds.offsetBy(dx: leftPos.x, dy: leftPos.y).insetBy(dx: 0, dy: -3)
            guard !previousFrame.intersects(frame) else { continue }
            (label as NSString).draw(at: leftPos, withAttributes: attributes)
            (label as NSString).draw(at: rightPos, withAttributes: attributes)
            previousFrame = frame
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawXAxis() {
        let gridlines = chart.sizeScale.gridlines
        let attributes = params.axisLabel.attributes

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
            path.stroke(with: params.lineParams(for: labeled ? .major : .minor))
        }
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        for (gridline, _, _) in labels {
            draw(gridline, labeled: true)
        }
        for gridline in secondary {
            draw(gridline, labeled: false)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawBorder() {
        let path = NSBezierPath(rect: chartRect.insetBy(dx: -0.25, dy: -0.25))
        path.stroke(with: params.border)
    }

    func drawHighlight(_ range: Range<CGFloat>) {
        let highlight = NSBezierPath()
        highlight.move(to: .init(x: range.lowerBound, y: 1))
        highlight.line(to: .init(x: range.upperBound, y: 1))
        highlight.move(to: .init(x: range.lowerBound, y: 0))
        highlight.line(to: .init(x: range.upperBound, y: 0))
        highlight.transform(using: chartTransform)
        highlight.stroke(with: params.highlightedBorder)
    }

    func drawCurves() {
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        let lineParams = (0 ..< chart.curves.count).map { params.lineParams($0, chart.curves.count) }
        for pass in 0 ..< lineParams.reduce(0, { max($0, $1.count) }) {
            for index in 0 ..< chart.curves.count {
                guard lineParams[index].count > pass else { continue }
                let curve = chart.curves[index]
                let path = (chartTransform as NSAffineTransform).transform(curve.path)
                path.stroke(with: lineParams[index][pass])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    struct LegendLayout {
        struct Caption {
            let path: NSBezierPath
            let lineParams: LineParams
            let position: CGPoint
            let text: NSAttributedString
        }

        let frame: CGRect
        let contents: [Caption]
    }
    func legendLayout() -> LegendLayout? {
        guard let legend = self.legend else { return nil }
        let attributes = params.legend.attributes
        var contents: [LegendLayout.Caption] = []
        var y = params.legendPadding - params.legend.font.descender
        var width: CGFloat = 0
        let sampleWidth: CGFloat = 24
        for (index, curve) in chart.curves.enumerated().reversed() {
            let lp = params.lineParams(index, chart.curves.count)[0]
            let title: NSMutableAttributedString
            let path = NSBezierPath()
            let pos: CGPoint
            let extraWidth: CGFloat
            if params.legendSampleLine {
                title = NSMutableAttributedString(string: curve.title, attributes: attributes)
                let bounds = title.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin)
                path.move(to: CGPoint(x: params.legendPadding, y: y + bounds.midY))
                path.line(to: CGPoint(x: params.legendPadding + sampleWidth, y: y + bounds.midY))
                extraWidth = sampleWidth + 6
                pos = CGPoint(x: params.legendPadding + extraWidth, y: y)
            }
            else {
                title = NSMutableAttributedString(string: "◼︎ " + curve.title, attributes: attributes)
                title.setAttributes([.foregroundColor: lp.color],
                                    range: NSRange(0 ..< 1))
                pos = CGPoint(x: params.legendPadding, y: y)
                extraWidth = 0
            }
            contents.append(LegendLayout.Caption(path: path, lineParams: lp, position: pos, text: title))
            let bounds = title.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin, context: nil)
            y += bounds.minY + bounds.height + params.legend.font.leading
            width = max(width, extraWidth + bounds.width)
        }
        y += params.legendPadding - params.legend.font.leading
        let legendSize = CGSize(width: width + 2 * params.legendPadding, height: y)

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
        return LegendLayout(frame: frame, contents: contents)
    }

    func drawLegendBackground(with layout: LegendLayout) {
        params.backgroundColor.setFill()
        layout.frame.fill()
    }

    func drawLegendContents(with layout: LegendLayout) {
        // Draw background again, with some transparency and borders.
        params.backgroundColor.withAlphaComponent(0.7).setFill()
        params.border.color.setStroke()
        let legendBorder = NSBezierPath(rect: layout.frame)
        legendBorder.lineWidth = 0.5
        legendBorder.fill()
        legendBorder.stroke()

        // Draw legend titles
        for caption in layout.contents {
            let path = caption.path.copy() as! NSBezierPath
            path.transform(using: .init(translationByX: layout.frame.minX, byY: layout.frame.minY))
            path.stroke(with: caption.lineParams)
            caption.text.draw(at: CGPoint(x: layout.frame.minX + caption.position.x,
                                          y: layout.frame.minY + caption.position.y))
        }
    }
}

extension Chart: CustomPlaygroundQuickLookable {
    var customPlaygroundQuickLook: PlaygroundQuickLook {
        let renderer = ChartRenderer(rect: CGRect(x: 0, y: 0, width: 1024, height: 640),
                                     chart: self, theme: .screen,
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
