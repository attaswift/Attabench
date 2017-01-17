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

class Chart {
    let size: CGSize

    var curves: [(String, NSColor, NSBezierPath)] = []
    var verticalGridLines: [(String?, CGFloat)] = []
    var horizontalGridLines: [(String?, CGFloat)] = []

    init(size: CGSize, suite: BenchmarkSuiteProtocol, results: BenchmarkSuiteResults, sizeRange: Range<Int> = 1 ..< 1024, timeRange: Range<TimeInterval> = 1e-3 ..< 0.1) {
        self.size = size
        var minSize = sizeRange.lowerBound
        var maxSize = sizeRange.upperBound
        var minTime = timeRange.lowerBound
        var maxTime = timeRange.upperBound
        for (_, samples) in results.samplesByBenchmark {
            for (size, sample) in samples.samples {
                if size > maxSize { maxSize = size }
                if size < minSize { minSize = size }
                let time = sample.minimum
                if time > maxTime { maxTime = time }
                if time < minTime { minTime = time }
            }
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

        let scaleX = size.width / (log2(CGFloat(maxSize)) - log2(CGFloat(minSize)))
        let scaleY = size.height / CGFloat(log2(maxTime) - log2(minTime))

        func x(_ size: Int) -> CGFloat {
            return scaleX * log2(CGFloat(max(1, size)))
        }
        func y(_ time: TimeInterval) -> CGFloat {
            return scaleY * CGFloat(log2(time) - log2(minTime))
        }

        do {
            var size = minSize
            while size <= maxSize {
                if size >= minSize {
                    let x = scaleX * log2(CGFloat(size))
                    verticalGridLines.append(("\(size)", x))
                }
                size <<= 1
            }
        }

        do {
            var time = minTime
            while time <= maxTime {
                let title = time >= 1 ? String(format: "%.3gs", time)
                    : time >= 0.001 ? String(format: "%.3gms", time * 1000)
                    : String(format: "%.3gµs", time * 1000000)

                horizontalGridLines.append((title, y(time)))

                for m: Double in [2, 4, 6, 8] {
                    horizontalGridLines.append((nil, y(m * time)))
                }
                time *= 10
            }
        }

        let c = suite.benchmarkTitles.count
        for i in 0 ..< c {
            let benchmark = suite.benchmarkTitles[i]
            guard let samples = results.samplesByBenchmark[benchmark] else { continue }

            let color = NSColor(calibratedHue: CGFloat(i) / CGFloat(c), saturation: 1, brightness: 1, alpha: 1)
            let path = NSBezierPath()
            path.appendLines(between: samples.samples.sorted(by: { $0.0 < $1.0 }).map { (size, sample) in
                return CGPoint(x: x(size), y: y(sample.minimum))
            })

            self.curves.append((benchmark, color, path))
        }
    }

    func render(into bounds: NSRect) {
        NSColor.black.setFill()
        NSRectFill(bounds)

        let majorGridLineColor = NSColor(white: 0.7, alpha: 1)
        let minorGridLineColor = NSColor(white: 0.3, alpha: 1)
        // Draw horizontal grid lines
        for (title, y) in horizontalGridLines {
            let color = title == nil ? minorGridLineColor : majorGridLineColor
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: self.size.width, y: y))
            path.lineWidth = 0.5
            path.stroke()
        }

        // Draw vertical grid lines
        for (title, x) in verticalGridLines {
            let color = title == nil ? minorGridLineColor : majorGridLineColor
            color.setStroke()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: self.size.height))
            path.lineWidth = 0.5
            path.stroke()
        }

        var titleY = bounds.maxY

        for (title, color, path) in curves {
            let title = title as NSString
            let attributes: [String: Any] = [
                NSFontAttributeName: NSFont(name: "HelveticaNeue", size: 16)!,
                NSForegroundColorAttributeName: color
            ]
            let titleBounds = title.boundingRect(with: NSSize(width: 100000, height: 100000), options: [], attributes: attributes)
            titleY -= titleBounds.height
            title.draw(at: CGPoint(x: 0, y: titleY), withAttributes: attributes)
            titleY -= 3

            color.setStroke()
            path.lineWidth = 4
            path.stroke()
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
