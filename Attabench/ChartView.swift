// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import BenchmarkCharts
import GlueKit

@IBDesignable
class ChartView: NSView {
    var documentBasename: String = "Benchmark"

    var chart: BenchmarkChart? = nil {
        didSet {
            self.image = self.render()
        }
    }

    private var themeConnection: Connection? = nil
    var theme: AnyObservableValue<BenchmarkTheme> = .constant(BenchmarkTheme.Predefined.screen) {
        didSet {
            self.image = render()
            themeConnection?.disconnect()
            themeConnection = theme.values.subscribe { [unowned self] theme in
                self.image = self.render()
            }
        }
    }

    var imageSize: CGSize? = nil {
        didSet {
            self.needsDisplay = true
        }
    }

    var image: NSImage? = nil {
        didSet {
            self.needsDisplay = true
        }
    }

    @IBInspectable
    var backgroundColor: NSColor = .clear {
        didSet {
            self.needsDisplay = true
        }
    }

    var downEvent: NSEvent? = nil

    func render() -> NSImage? {
        return render(at: imageSize ?? self.bounds.size)
    }

    func render(at size: CGSize) -> NSImage? {
        guard let chart = self.chart else { return nil }
        var options = BenchmarkRenderer.Options()
        let legendMargin = min(0.05 * size.width, 0.05 * size.height)
        options.showTitle = false
        options.legendPosition = chart.tasks.count > 10 ? .hidden : .topLeft
        options.legendHorizontalMargin = legendMargin
        options.legendVerticalMargin = legendMargin

        let renderer = BenchmarkRenderer(chart: chart,
                                         theme: self.theme.value,
                                         options: options,
                                         in: CGRect(origin: .zero, size: size))
        return renderer.image
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw background.
        self.backgroundColor.setFill()
        dirtyRect.fill()

        let bounds = self.bounds

        if let image = image, image.size.width * image.size.height > 0 {
            let aspect = image.size.width / image.size.height
            let fitSize = CGSize(width: min(bounds.width, aspect * bounds.height),
                                 height: min(bounds.height, bounds.width / aspect))
            image.draw(in: CGRect(origin: CGPoint(x: bounds.minX + (bounds.width - fitSize.width) / 2,
                                                  y: bounds.minY + (bounds.height - fitSize.height) / 2),
                                  size: fitSize))
        }
    }

    override var frame: NSRect {
        get { return super.frame }
        set {
            super.frame = newValue
            if imageSize == nil {
                self.image = render()
            }
        }
    }
}
