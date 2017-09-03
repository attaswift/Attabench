// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

#if OBJCIO
    private let labelFontName = "Tiempos Text"
    private let monoFontName = "Akkurat TT"
#elseif LORENTEY
    private let labelFontName = "Palatino"
    private let monoFontName = "InputSansNarrow-Regular"
#else
    private let labelFontName = "Helvetica-Light"
    private let monoFontName = "Menlo"
#endif

private let presentationSize = CGSize(width: 1280, height: 720)
private let printSize = CGSize(width: 800, height: 260)

private func colorLineParams(index: Int, count: Int, lineWidth: CGFloat, hairLine: Bool, shadowRadius: CGFloat = 0) -> [LineParams] {
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

private func monoLineParams(index: Int, count: Int, lineWidth: CGFloat) -> [LineParams] {
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


public struct BenchmarkTheme {
    let imageSize: CGSize?
    let marginRatio: (x: CGFloat, y: CGFloat)
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
    let branding: TextParams?

    func lineParams(for kind: Gridline.Kind) -> LineParams {
        switch kind {
        case .major: return majorGridline
        case .minor: return minorGridline
        }
    }

    public enum Predefined {
        public static let screen = BenchmarkTheme(
            imageSize: nil,
            marginRatio: (0.02, 0.05),
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
            xPadding: 6,
            branding: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black))

        public static let presentation = BenchmarkTheme(
            imageSize: presentationSize,
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
            xPadding: 12,
            branding: TextParams(font: NSFont(name: labelFontName, size: 24)!, color: .black))

        public static let colorPrint = BenchmarkTheme(
            imageSize: printSize,
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
            xPadding: 6,
            branding: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black))

        public static let monochromePrint = BenchmarkTheme(
            imageSize: printSize,
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
            xPadding: 6,
            branding: TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black))

        public static let predefinedThemes: [String: BenchmarkTheme] = [
            "Screen": screen,
            "Presentation": presentation,
            "Color Print": colorPrint,
            "Monochrome Print": monochromePrint,
            ]
    }
}

