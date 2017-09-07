// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
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

private func colorLineParams(index: Int, count: Int, lineWidth: CGFloat, hairLine: Bool, shadowRadius: CGFloat = 0) -> [BenchmarkTheme.LineParams] {
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
        return [BenchmarkTheme.LineParams(lineWidth: lineWidth, color: color, shadowRadius: shadowRadius),
                BenchmarkTheme.LineParams(lineWidth: 0.5, color: .black)]
    }
    else {
        return [BenchmarkTheme.LineParams(lineWidth: lineWidth, color: color, shadowRadius: shadowRadius)]
    }
}

private func monoLineParams(index: Int, count: Int, lineWidth: CGFloat) -> [BenchmarkTheme.LineParams] {
    let dash: [CGFloat]
    switch index {
    case 0: dash = []
    case 1: dash = [6, 3]
    case 2: dash = [0, 3]
    default:
        dash = [6, 3] + [0, 3].repeated(index - 2)
    }
    return [BenchmarkTheme.LineParams(lineWidth: lineWidth, color: .black, dash: dash)]
}


public struct BenchmarkTheme: Hashable {
    public var name: String
    public var imageSize: CGSize? = nil
    public var margins: (x: CGFloat, y: CGFloat) = (12, 12)
    public var backgroundColor: NSColor = .white
    public var title: TextParams = .init(font: NSFont(name: labelFontName, size: 24)!, color: NSColor.black)
    public var border: LineParams = .init(lineWidth: 0.5, color: NSColor.black)
    public var highlightedBorder: LineParams = .init(lineWidth: 4, color: NSColor.black)
    public var majorGridline: LineParams = .init(lineWidth: 0.75, color: NSColor(white: 0.3, alpha: 1))
    public var minorGridline: LineParams = .init(lineWidth: 0.5, color: NSColor(white: 0.3, alpha: 1), dash: [6, 3])
    public var axisLabel: TextParams = .init(font: NSFont(name: labelFontName, size: 10)!, color: .black)
    public var legend: TextParams = .init(font: NSFont(name: monoFontName, size: 12)!, color: .black)
    public var legendPadding: CGFloat = 6
    public var legendSampleLine: Bool = false
    public var lineParams: (Int, Int) -> [LineParams] = { i, c in colorLineParams(index: i, count: c, lineWidth: 4, hairLine: true) }
    public var xPadding: CGFloat = 6
    public var branding: TextParams? = TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black)

    public init(name: String) {
        self.name = name
    }

    public mutating func setLabelFontName(_ name: String) {
        title.fontName = name
        axisLabel.fontName = name
        branding?.fontName = name
    }

    public mutating func setMonoFontName(_ name: String) {
        legend.fontName = name
    }

    func lineParams(for kind: Gridline.Kind) -> LineParams {
        switch kind {
        case .major: return majorGridline
        case .minor: return minorGridline
        }
    }

    public var hashValue: Int { return name.hashValue }
    public static func ==(left: BenchmarkTheme, right: BenchmarkTheme) -> Bool {
        return left.name == right.name
    }

    public enum Predefined {
        public static let screen = BenchmarkTheme(name: "Screen")
        
        public static let presentation: BenchmarkTheme = {
            var theme = BenchmarkTheme(name: "Presentation")
            theme.imageSize = presentationSize
            theme.margins = (0, 0)
            theme.backgroundColor = NSColor.black
            theme.title = TextParams(font: NSFont(name: labelFontName, size: 48)!, color: NSColor.white)
            theme.border = LineParams(lineWidth: 0.5, color: NSColor.white)
            theme.highlightedBorder = LineParams(lineWidth: 4, color: NSColor.white)
            theme.majorGridline = LineParams(lineWidth: 0.75, color: NSColor(white: 0.3, alpha: 1))
            theme.minorGridline = LineParams(lineWidth: 0.5, color: NSColor(white: 0.7, alpha: 1), dash: [6, 3])
            theme.axisLabel = TextParams(font: NSFont(name: labelFontName, size: 24)!, color: .white)
            theme.legend = TextParams(font: NSFont(name: monoFontName, size: 20)!, color: .white)
            theme.legendPadding = 8
            theme.legendSampleLine = false
            theme.lineParams = { i, c in colorLineParams(index: i, count: c, lineWidth: 8, hairLine: false, shadowRadius: 3) }
            theme.xPadding = 12
            theme.branding = TextParams(font: NSFont(name: labelFontName, size: 18)!,
                                        color: NSColor(calibratedWhite: 1, alpha: 1))
            return theme
        }()

        public static let colorPrint: BenchmarkTheme = {
            var theme = BenchmarkTheme(name: "Color Print")
            theme.imageSize = CGSize(width: 800, height: 260)
            theme.margins = (0, 0)
            theme.backgroundColor = NSColor.white
            theme.title = TextParams(font: NSFont(name: labelFontName, size: 12)!, color: .black)
            theme.border = LineParams(lineWidth: 1, color: .black)
            theme.highlightedBorder = LineParams(lineWidth: 4, color: .black)
            theme.majorGridline = LineParams(lineWidth: 0.7, color: NSColor(white: 0.6, alpha: 1))
            theme.minorGridline = LineParams(lineWidth: 0.4, color: NSColor(white: 0.6, alpha: 1), dash: [2, 1])
            theme.axisLabel = TextParams(font: NSFont(name: labelFontName, size: 10)!, color: .black)
            theme.legend = TextParams(font: NSFont(name: monoFontName, size: 10)!, color: .black)
            theme.legendPadding = 6
            theme.legendSampleLine = false
            theme.lineParams = { i, c in colorLineParams(index: i, count: c, lineWidth: 4, hairLine: true) }
            theme.xPadding = 6
            theme.branding = TextParams(font: NSFont(name: labelFontName, size: 10)!,
                                        color: NSColor(calibratedWhite: 0, alpha: 1))
            return theme
        }()

        public static let monochromePrint: BenchmarkTheme = {
            var theme = BenchmarkTheme(name: "Monochrome Print")
            theme.imageSize = CGSize(width: 800, height: 320)
            theme.margins = (0, 0)
            theme.backgroundColor = NSColor.white
            theme.title = TextParams(font: NSFont(name: labelFontName, size: 18)!, color: .black)
            theme.border = LineParams(lineWidth: 1, color: .black)
            theme.highlightedBorder = LineParams(lineWidth: 4, color: .black)
            theme.majorGridline = LineParams(lineWidth: 0.7, color: NSColor(white: 0.6, alpha: 1))
            theme.minorGridline = LineParams(lineWidth: 0.4, color: NSColor(white: 0.6, alpha: 1), dash: [2, 1])
            theme.axisLabel = TextParams(font: NSFont(name: labelFontName, size: 14)!, color: .black)
            theme.legend = TextParams(font: NSFont(name: monoFontName, size: 14)!, color: .black)
            theme.legendPadding = 6
            theme.legendSampleLine = true
            theme.lineParams = { i, c in monoLineParams(index: i, count: c, lineWidth: 2) }
            theme.xPadding = 6
            theme.branding = TextParams(font: NSFont(name: labelFontName, size: 14)!, color: .black)
            return theme
        }()

        public static let themes: [BenchmarkTheme] = [
            screen,
            presentation,
            colorPrint,
            monochromePrint,
            ]

        public static func theme(named name: String) -> BenchmarkTheme? {
            return themes.first(where: { $0.name == name })
        }
    }
}

