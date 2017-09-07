// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import CoreGraphics
import AppKit

public struct BenchmarkRenderer {
    public struct Options {
        public var showTitle: Bool = true
        public var legendPosition: LegendPosition = .topLeft
        public var legendHorizontalMargin: CGFloat = 0
        public var legendVerticalMargin: CGFloat = 0
        public var highlightedSizes: ClosedRange<Int>? = nil

        public init() {}
    }

    public enum LegendPosition {
        case hidden
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    public let chart: BenchmarkChart
    public let theme: BenchmarkTheme
    public let options: Options

    public let rect: CGRect
    let bounds: CGRect

    let titleRect: CGRect?
    let brandingRect: CGRect?
    let chartRect: CGRect
    let chartTransform: AffineTransform

    public init(chart: BenchmarkChart, theme: BenchmarkTheme, options: Options, in rect: CGRect) {
        self.chart = chart
        self.theme = theme
        self.options = options

        self.rect = rect
        self.bounds = rect.insetBy(dx: theme.margins.x, dy: theme.margins.y)

        var chartRect = bounds
        if options.showTitle {
            let font = theme.title.font
            let height = font.leading + font.boundingRectForFont.height
            let split = chartRect.divided(atDistance: height, from: .maxYEdge)
            titleRect = split.slice
            chartRect = split.remainder
        }
        else {
            titleRect = nil
        }

        let scaleWidth = 3 * theme.axisLabel.font.maximumAdvancement.width
        chartRect = chartRect.insetBy(dx: scaleWidth, dy: 0)

        if let branding = theme.branding {
            let split = chartRect.divided(atDistance: branding.font.leading + branding.font.boundingRectForFont.height,
                                          from: .minYEdge)
            brandingRect = split.slice
            chartRect = split.remainder
        }
        else {
            brandingRect = nil
        }

        let scaleHeight = theme.axisLabel.font.leading + theme.axisLabel.font.boundingRectForFont.height
        chartRect = chartRect.insetBy(dx: 0, dy: scaleHeight)

        self.chartRect = chartRect

        var chartTransform = AffineTransform()
        chartTransform.translate(x: chartRect.minX, y: chartRect.minY)
        chartTransform.scale(x: chartRect.width, y: chartRect.height)
        self.chartTransform = chartTransform
    }

    public var image: NSImage {
        return NSImage(size: rect.integral.size, flipped: false) { rect in
            (AffineTransform(translationByX: -self.rect.minX, byY: -self.rect.minY) as NSAffineTransform).concat()
            self.draw()
            return true
        }
    }

    public func draw() {
        drawBackground()

        if options.showTitle {
            drawTitle()
        }

        drawYAxis()
        drawXAxis()
        drawBorder()

        if let range = options.highlightedSizes {
            drawHighlight(range)
        }

        guard !chart.curves.isEmpty else { return }

        if let legendLayout = self.legendLayout() {
            drawLegendBackground(with: legendLayout)
            drawErrorBands()
            drawCurves()
            drawLegendContents(with: legendLayout)
        }
        else {
            drawErrorBands()
            drawCurves()
        }

        drawBranding()
    }

    func drawBackground() {
        theme.backgroundColor.setFill()
        rect.fill()
    }

    func drawTitle() {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: chart.title,
            attributes: [
                .font: theme.title.font,
                .foregroundColor: theme.title.color,
                .paragraphStyle: paragraphStyle,
                ])
        title.draw(with: titleRect!, options: .usesLineFragmentOrigin)
    }

    func drawYAxis() {
        var gridlines = chart.timeScale.gridlines
        if !chart.options.amortizedTime || CGFloat(chart.timeScale.grid.minor) * chartRect.height <= 10 {
            gridlines = gridlines.filter { $0.kind == .major }
        }

        // Draw gridlines
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        for gridline in gridlines {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: gridline.position))
            path.line(to: CGPoint(x: 1, y: gridline.position))
            path.transform(using: chartTransform)
            path.stroke(with: theme.lineParams(for: gridline.kind))
        }
        NSGraphicsContext.restoreGraphicsState()

        // Draw labels
        NSGraphicsContext.saveGraphicsState()
        var previousFrame = CGRect.null
        let attributes = theme.axisLabel.attributes
        for gridline in gridlines where gridline.kind == .major {
            guard let label = gridline.label else { continue }
            let yMid = chartRect.minY + gridline.position * chartRect.height + theme.axisLabel.font.pointSize / 4

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
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawXAxis() {
        let gridlines = chart.sizeScale.gridlines
        let attributes = theme.axisLabel.attributes

        // Calculate frames for labels on the size axis
        typealias LabelGeometry = (gridline: Gridline, position: CGPoint, frame: CGRect)
        var labels: [LabelGeometry] = []
        var secondary: [Gridline] = []
        for gridline in gridlines {
            guard let label = gridline.label else { secondary.append(gridline); continue }
            let xMid = chartRect.minX + gridline.position * chartRect.width
            let yTop = chartRect.minY - 3

            let bounds = (label as NSString).boundingRect(with: CGSize(width: 1000, height: 1000),
                                                          options: [],
                                                          attributes: attributes)
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
            path.stroke(with: theme.lineParams(for: labeled ? .major : .minor))
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
        path.stroke(with: theme.border)
    }

    func drawHighlight(_ range: ClosedRange<Int>) {
        let range = Double(range.lowerBound) ... Double(range.upperBound)
        let highlight = NSBezierPath()
        highlight.move(to: .init(x: range.lowerBound, y: 1))
        highlight.line(to: .init(x: range.upperBound, y: 1))
        highlight.move(to: .init(x: range.lowerBound, y: 0))
        highlight.line(to: .init(x: range.upperBound, y: 0))
        highlight.transform(using: chartTransform)
        highlight.stroke(with: theme.highlightedBorder)
    }

    func drawErrorBands() {
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        for index in 0 ..< chart.curves.count {
            guard let lineParams = theme.lineParams(index, chart.curves.count).first else { continue }
            let color = lineParams.color.withAlphaComponent(lineParams.color.alphaComponent * 0.3)
            let curve = chart.curves[index]
            let path = NSBezierPath(linesBetween: curve.topBand + curve.bottomBand.reversed())
            path.transform(using: chartTransform)
            color.setFill()
            path.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawCurves() {
        NSGraphicsContext.saveGraphicsState()
        chartRect.clip()
        let lineParams = (0 ..< chart.curves.count).map { theme.lineParams($0, chart.curves.count) }
        for pass in 0 ..< lineParams.reduce(0, { max($0, $1.count) }) {
            for index in 0 ..< chart.curves.count {
                guard lineParams[index].count > pass else { continue }
                let curve = chart.curves[index]
                let path = NSBezierPath(linesBetween: curve.centerBand)
                path.transform(using: chartTransform)
                path.stroke(with: lineParams[index][pass])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    struct LegendLayout {
        struct Caption {
            let path: NSBezierPath
            let lineParams: BenchmarkTheme.LineParams
            let position: CGPoint
            let text: NSAttributedString
        }

        let frame: CGRect
        let contents: [Caption]
    }
    func legendLayout() -> LegendLayout? {
        guard options.legendPosition != .hidden else { return nil }

        let attributes = theme.legend.attributes
        var contents: [LegendLayout.Caption] = []
        var y = theme.legendPadding - theme.legend.font.descender
        var width: CGFloat = 0
        let sampleWidth: CGFloat = 24
        for (index, curve) in chart.curves.enumerated().reversed() {
            let lp = theme.lineParams(index, chart.curves.count)[0]
            let title: NSMutableAttributedString
            let path = NSBezierPath()
            let pos: CGPoint
            let extraWidth: CGFloat
            if theme.legendSampleLine {
                title = NSMutableAttributedString(string: curve.title, attributes: attributes)
                let bounds = title.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin)
                path.move(to: CGPoint(x: theme.legendPadding, y: y + bounds.midY))
                path.line(to: CGPoint(x: theme.legendPadding + sampleWidth, y: y + bounds.midY))
                extraWidth = sampleWidth + 6
                pos = CGPoint(x: theme.legendPadding + extraWidth, y: y)
            }
            else {
                title = NSMutableAttributedString(string: "◼︎ " + curve.title, attributes: attributes)
                title.setAttributes([.foregroundColor: lp.color],
                                    range: NSRange(0 ..< 1))
                pos = CGPoint(x: theme.legendPadding, y: y)
                extraWidth = 0
            }
            contents.append(LegendLayout.Caption(path: path, lineParams: lp, position: pos, text: title))
            let bounds = title.boundingRect(with: CGSize(width: 1000, height: 1000), options: .usesLineFragmentOrigin)
            y += bounds.minY + bounds.height + theme.legend.font.leading
            width = max(width, extraWidth + bounds.width)
        }
        y += theme.legendPadding - theme.legend.font.leading
        let legendSize = CGSize(width: width + 2 * theme.legendPadding, height: y)

        var pos = CGPoint.zero
        switch options.legendPosition {
        case .topLeft, .bottomLeft:
            pos.x = chartRect.minX + options.legendHorizontalMargin
        case _:
            pos.x = chartRect.maxX - options.legendHorizontalMargin - legendSize.width
        }
        switch options.legendPosition {
        case .topLeft, .topRight:
            pos.y = chartRect.maxY - options.legendVerticalMargin - legendSize.height
        case _:
            pos.y = chartRect.minY + options.legendVerticalMargin
        }

        let frame = CGRect(origin: pos, size: legendSize)
        return LegendLayout(frame: frame, contents: contents)
    }

    func drawLegendBackground(with layout: LegendLayout) {
        theme.backgroundColor.setFill()
        layout.frame.fill()
    }

    func drawLegendContents(with layout: LegendLayout) {
        // Draw background again, with some transparency and borders.
        theme.backgroundColor.withAlphaComponent(0.7).setFill()
        theme.border.color.setStroke()
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

    func drawBranding() {
        guard let params = theme.branding else { return }
        guard let brandingRect = self.brandingRect else { return }
        let text = "Generated by Attabench"
        let atext = NSAttributedString(string: text, attributes: params.attributes)
        let size = atext.size()
        atext.draw(at: CGPoint(x: brandingRect.maxX - size.width,
                               y: brandingRect.maxY - size.height))
    }
}

extension BenchmarkRenderer: CustomPlaygroundQuickLookable {
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        return .image(self.image)
    }
}
