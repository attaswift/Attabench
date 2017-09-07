// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import OptionParser
import Benchmarking // for complain
import BenchmarkModel
import BenchmarkCharts

let parser = OptionParser<Options>(
    docs: "Generate Attabench charts",
    initial: Options(),
    options: [
        .flag(for: \.command, value: .listTasks, name: "list-tasks", docs: "List available task names in file and exit."),
        .flag(for: \.command, value: .listThemes, name: "list-themes", docs: "List available themes and exit."),
        .array(for: \.tasks, syntax: .upToNextOption, name: "tasks", metavariable: "<name>", docs: "Names of tasks to render."),
        .value(for: \.minSize, name: "min-size", metavariable: "<integer>", docs: "Minimum size"),
        .value(for: \.maxSize, name: "max-size", metavariable: "<integer>", docs: "Maximum size"),
        .value(for: \.minTime, name: "min-time", metavariable: "<time>", docs: "Minimum time"),
        .value(for: \.maxTime, name: "max-time", metavariable: "<time>", docs: "Maximum time"),
        .value(for: \.amortized, name: "amortized", metavariable: "yes|no", docs: "Amortized time (default: yes)"),
        .value(for: \.logarithmicSize, name: "logarithmic-size", metavariable: "yes|no", docs: "Logarithmic size scale (default: yes)"),
        .value(for: \.logarithmicTime, name: "logarithmic-time", metavariable: "yes|no", docs: "Logarithmic time scale (default: yes)"),
        .value(for: \.topBand, name: "top-band", metavariable: "<band>", docs: "Top band (default: sigma2)"),
        .value(for: \.centerBand, name: "center-band", metavariable: "<band>", docs: "Center band (default: average)"),
        .value(for: \.bottomBand, name: "bottom-band", metavariable: "<band>", docs: "Bottom band (default: minimum)"),
        .value(for: \.theme, name: "theme", metavariable: "<name>", docs: "Generate chart with thise theme"),
        .value(for: \.width, name: "width", metavariable: "<integer>", docs: "Width of generated image, in points."),
        .value(for: \.height, name: "height", metavariable: "<integer>", docs: "Height of generated image, in points."),
        .value(for: \.scale, name: "scale", metavariable: "<integer>", docs: "Number of pixels in a point. (Default: 1)"),
        .value(for: \.labelFontName, name: "label-font", metavariable: "<name>", docs: "Name of font to use for labels."),
        .value(for: \.monoFontName, name: "mono-font", metavariable: "<name>", docs: "Name of font to use for task titles."),
        .value(for: \.branding, default: true, name: "branding", metavariable: "on|off", docs: "Enable/disable Attabench branding (on by default)"),
        .value(for: \.preset, name: "preset", metavariable: "<name>", docs: "Use predefined set of options"),
        ],
    parameters: [
        .required(for: \.input, metavariable: "<input>", docs: "Path to .attaresult file"),
        .required(for: \.output, metavariable: "<output>", docs: "Path to image file"),
        ]) { options in
            var options = options
            options.applyPreset()
            let inputURL = URL(fileURLWithPath: options.input)
            let outputURL = URL(fileURLWithPath: options.output)
            let data = try Data(contentsOf: inputURL)
            let model = try JSONDecoder().decode(Attaresult.self, from: data)

            switch options.command {
            case .listTasks:
                for task in model.tasks.value {
                    print(task.name)
                }
            case .listThemes:
                for theme in BenchmarkTheme.Predefined.themes {
                    print(theme.name)
                }
            case .render:
                try model.render(inputURL, options, outputURL)
            }
}

do {
    try parser.parse()
    exit(0)
}
catch let error as OptionError {
    complain(error.message)
    exit(1)
}
catch {
    complain(error.localizedDescription)
    exit(1)
}
