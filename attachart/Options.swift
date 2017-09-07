// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import OptionParser
import BenchmarkModel
import BenchmarkCharts

struct Options {
    enum Command {
        case listTasks
        case listThemes
        case render
    }

    enum Preset: String, OptionValue {
        case none = "none"
        case optimizingCollections = "OptimizingCollections"
    }

    var input: String = ""
    var output: String = ""
    var command: Command = .render

    var tasks: [String] = []
    var minSize: Int? = nil
    var maxSize: Int? = nil
    var minTime: Time? = nil
    var maxTime: Time? = nil
    var amortized: Bool = true
    var logarithmicSize = true
    var logarithmicTime = true

    var preset: Preset = .none

    var topBand: BandOption? = nil
    var centerBand: BandOption? = nil
    var bottomBand: BandOption? = nil

    var theme: String? = nil
    var width: Int? = nil
    var height: Int? = nil
    var scale: Int? = nil
    var labelFontName: String? = nil
    var monoFontName: String? = nil
    var branding: Bool? = nil

    mutating func applyPreset() {
        switch preset {
        case .none:
            break
        case .optimizingCollections:
            topBand = topBand ?? BandOption(nil)
            centerBand = centerBand ?? BandOption(.average)
            bottomBand = bottomBand ?? BandOption(nil)
            theme = theme ?? BenchmarkTheme.Predefined.colorPrint.name
            width = width ?? 800
            height = height ?? 260
            scale = scale ?? 4
            labelFontName = labelFontName ?? "Tiempos Text"
            monoFontName = monoFontName ?? "Akkurat TT"
            branding = branding ?? false

            minSize = minSize ?? 1
            maxSize = maxSize ?? (1 << 22)
        }
    }
}

struct BandOption: OptionValue {
    let value: TimeSample.Band?

    init(_ value: TimeSample.Band?) {
        self.value = value
    }

    init(fromOptionValue string: String) throws {
        switch string {
        case "off", "none": self.value = nil
        case "average", "avg": self.value = .average
        case "minimum", "min": self.value = .minimum
        case "maximum", "max": self.value = .maximum
        case "sigma1", "s1": self.value = .sigma(1)
        case "sigma2", "s2": self.value = .sigma(2)
        case "sigma3", "s3": self.value = .sigma(3)
        default:
            throw OptionError("Invalid band value '\(string)' (expected: off|average|minimum|maximum|sigma1|sigma2|sigma3")
        }
    }
}



extension Time: OptionValue {
    public init(fromOptionValue string: String) throws {
        guard let value = Time(string) else {
            throw OptionError("Invalid time value: '\(string)'")
        }
        self = value
    }
}
