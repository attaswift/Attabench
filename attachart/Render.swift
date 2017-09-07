// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import BenchmarkModel
import BenchmarkCharts
import OptionParser

extension Attaresult {
    func render(_ inputURL: URL, _ options: Options, _ outputURL: URL) throws {
        let tasks: [Task]
        if options.tasks.isEmpty {
            tasks = self.tasks.value
        }
        else {
            tasks = try options.tasks.map { name -> Task in
                guard let task = self.task(named: name) else {
                    throw OptionError("Unknown task '\(name)'")
                }
                return task
            }
        }

        var chartOptions = BenchmarkChart.Options()
        chartOptions.amortizedTime = options.amortized
        chartOptions.logarithmicTime = options.logarithmicTime
        chartOptions.logarithmicSize = options.logarithmicSize
        chartOptions.topBand = (options.topBand ?? BandOption(.sigma(2))).value
        chartOptions.centerBand = (options.centerBand ?? BandOption(.average)).value
        chartOptions.bottomBand = (options.bottomBand ?? BandOption(.minimum)).value
        switch (options.minSize, options.maxSize) {
        case (nil, nil):
            chartOptions.displayAllMeasuredSizes = true
        case let (min?, max?):
            chartOptions.displaySizeRange = Swift.min(min, max) ... Swift.max(min, max)
            chartOptions.displayAllMeasuredSizes = false
        default:
            throw OptionError("Both -min-size and -max-size must be specified")
        }
        switch (options.minTime, options.maxTime) {
        case (nil, nil):
            chartOptions.displayAllMeasuredTimes = true
        case let (min?, max?):
            chartOptions.displayTimeRange = Swift.min(min, max) ... Swift.max(min, max)
            chartOptions.displayAllMeasuredTimes = false
        default:
            throw OptionError("Both -min-time and -max-time must be specified")
        }

        let chart = BenchmarkChart(
            title: inputURL.lastPathComponent,
            tasks: tasks, options: chartOptions)

        let themeName = options.theme ?? BenchmarkTheme.Predefined.screen.name
        guard var theme = BenchmarkTheme.Predefined.theme(named: themeName) else {
            throw OptionError("Unknown theme '\(themeName); use -list-themes to get a list of available themes")
        }

        if let fontName = options.labelFontName {
            theme.setLabelFontName(fontName)
        }
        if let fontName = options.monoFontName {
            theme.setMonoFontName(fontName)
        }
        if let branding = options.branding, !branding {
            theme.branding = nil
        }

        var imageSize: CGSize
        switch (options.width, options.height) {
        case let (w?, h?): imageSize = CGSize(width: w, height: h)
        case (nil, nil):
            guard let size = theme.imageSize else {
                throw OptionError("Please select a theme with a predefined image size or specify an explicit size")
            }
            imageSize = size
        default:
            throw OptionError("Both -width and -height must be specified")
        }

        var renderOptions = BenchmarkRenderer.Options()
        renderOptions.showTitle = false
        renderOptions.legendHorizontalMargin = 0.04 * min(imageSize.width, imageSize.height)
        renderOptions.legendVerticalMargin = renderOptions.legendHorizontalMargin

        let renderer = BenchmarkRenderer(
            chart: chart,
            theme: theme,
            options: renderOptions,
            in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
        )

        let image = renderer.image

        switch outputURL.pathExtension.lowercased() {
        case "png":
            try image.pngData(scale: options.scale ?? 1).write(to: outputURL)
        case "pdf":
            try image.pdfData().write(to: outputURL)
        default:
            throw OptionError("Unknown file extension '\(outputURL.pathExtension)'; expected .png or .pdf")
        }
    }
}
