//
//  ChartRendering.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa
import BenchmarkModel

func min<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.min(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}

func max<C: Comparable>(_ a: C?, _ b: C?) -> C? {
    switch (a, b) {
    case let (a?, b?): return Swift.max(a, b)
    case let (a?, nil): return a
    case let (nil, b?): return b
    case (nil, nil): return nil
    }
}

enum BandIndex {
    case top
    case center
    case bottom

    static let all: [BandIndex] = [.top, .center, .bottom]
}

struct Curve {
    var title: String
    var topBand: [CGPoint] = []
    var centerBand: [CGPoint] = []
    var bottomBand: [CGPoint] = []

    init(title: String) {
        self.title = title
    }

    subscript(_ b: BandIndex) -> [CGPoint] {
        get {
            switch b {
            case .top: return topBand
            case .center: return centerBand
            case .bottom: return bottomBand
            }
        }
        set {
            switch b {
            case .top: topBand = newValue
            case .center: centerBand = newValue
            case .bottom: bottomBand = newValue
            }
        }
    }
}

struct RawCurve {
    struct Sample {
        let size: Int
        let time: Time
    }
    var title: String
    var topBand: [Sample] = []
    var centerBand: [Sample] = []
    var bottomBand: [Sample] = []

    init(title: String) {
        self.title = title
    }

    subscript(_ b: BandIndex) -> [Sample] {
        get {
            switch b {
            case .top: return topBand
            case .center: return centerBand
            case .bottom: return bottomBand
            }
        }
        set {
            switch b {
            case .top: topBand = newValue
            case .center: centerBand = newValue
            case .bottom: bottomBand = newValue
            }
        }
    }

    mutating func append(_ sample: Sample, at bi: BandIndex) {
        switch bi {
        case .top: topBand.append(sample)
        case .center: centerBand.append(sample)
        case .bottom: bottomBand.append(sample)
        }
    }
}

/// Contains a preprocessed copy of selected data from a bunch of benchmark results, according to given parameters.
public struct BenchmarkChart {
    public typealias Bounds = BenchmarkModel.Bounds
    public typealias Band = TimeSample.Band

    public struct Options {
        public var amortizedTime = true
        public var logarithmicTime = true
        public var logarithmicSize = true
        public var topBand: Band? = nil
        public var centerBand: Band? = .average
        public var bottomBand: Band? = nil

        public var displaySizeRange: ClosedRange<Int>? = nil
        public var displayAllMeasuredSizes = true

        public var displayTimeRange: ClosedRange<Time>? = nil
        public var displayAllMeasuredTimes = true

        public init() {}
        
        subscript(_ b: BandIndex) -> Band? {
            get {
                switch b {
                case .top: return topBand
                case .center: return centerBand
                case .bottom: return bottomBand
                }
            }
            set {
                switch b {
                case .top: topBand = newValue
                case .center: centerBand = newValue
                case .bottom: bottomBand = newValue
                }
            }
        }
    }

    public let title: String
    public let tasks: [String]
    public let options: Options
    private(set) var curves: [Curve] = []
    let sizeScale: ChartScale
    let timeScale: ChartScale

    public init(title: String,
                tasks: [Task],
                options: Options) {
        self.title = title
        self.tasks = tasks.map { $0.name }
        self.options = options

        #if false
            // TODO Move this
            if amortized {
                self.title = suite.benchmark.descriptiveAmortizedTitle
                    ?? suite.benchmark.descriptiveTitle?.appending(" (amortized)")
                    ?? suite.title.appending(" (amortized)")
            }
            else {
                self.title = suite.benchmark.descriptiveTitle ?? suite.title
            }
        #endif

        var minSize = options.displaySizeRange?.lowerBound
        var maxSize = options.displaySizeRange?.upperBound
        var minTime = options.displayTimeRange?.lowerBound
        var maxTime = options.displayTimeRange?.upperBound

        // Gather data.
        var rawCurves: [RawCurve] = []
        for task in tasks {
            var rawCurve = RawCurve(title: task.name)
            for (size, sample) in task.samples.sorted(by: { $0.key < $1.key }) {
                for bi in BandIndex.all {
                    guard let band = options[bi] else { continue }
                    guard let time = sample[band] else { continue }
                    let t = options.amortizedTime ? time / size : time
                    rawCurve.append(.init(size: size, time: t), at: bi)
                    if options.displayAllMeasuredSizes {
                        minSize = min(minSize, size)
                        maxSize = max(maxSize, size)
                    }
                    if options.displayAllMeasuredTimes {
                        minTime = min(minTime, t)
                        maxTime = max(maxTime, t)
                    }
                }
            }
            rawCurves.append(rawCurve)
        }

        // Set up horizontal and vertical scales.
        if let minSize = minSize, let maxSize = maxSize {
            let xrange = Double(minSize) ... Double(maxSize)
            if options.logarithmicSize {
                let labeler: (Int) -> String = { value in (1 << value).sizeLabel }
                self.sizeScale = LogarithmicScale(xrange, decimal: false, labeler: labeler)
            }
            else {
                let labeler: (Double) -> String = { value in Int(value).sizeLabel }
                self.sizeScale = LinearScale(xrange, decimal: false, labeler: labeler)
            }
        }
        else {
            self.sizeScale = EmptyScale()
        }

        if let minTime = minTime, let maxTime = maxTime {
            let yrange = minTime.seconds ... maxTime.seconds
            if options.logarithmicTime {
                let labeler: (Int) -> String = { value in "\(Time(orderOfMagnitude: value))" }
                self.timeScale = LogarithmicScale(yrange, decimal: true, labeler: labeler)
            }
            else {
                let labeler: (Double) -> String = { value in "\(Time(value))" }
                self.timeScale = LinearScale(yrange, decimal: true, labeler: labeler)
            }
        }
        else {
            // Empty chart.
            self.timeScale = EmptyScale()
        }

        // Calculate curves.
        func transform(_ s: RawCurve.Sample) -> CGPoint {
            return CGPoint(x: sizeScale.position(for: Double(s.size)),
                           y: timeScale.position(for: s.time.seconds))
        }
        for raw in rawCurves {
            var curve = Curve(title: raw.title)
            curve.topBand = raw.topBand.map(transform)
            curve.centerBand = raw.centerBand.map(transform)
            curve.bottomBand = raw.bottomBand.map(transform)
            curves.append(curve)
        }
    }
}

extension BenchmarkChart: CustomPlaygroundQuickLookable {
    public var customPlaygroundQuickLook: PlaygroundQuickLook {
        var options = BenchmarkRenderer.Options()
        options.showTitle = true
        options.legendPosition = .topLeft
        options.legendHorizontalMargin = 32
        options.legendVerticalMargin = 32
        let rect = CGRect(x: 0, y: 0, width: 1024, height: 640)
        let theme = BenchmarkTheme.Predefined.screen
        let renderer = BenchmarkRenderer(chart: self, theme: theme, options: options, in: rect)
        return .image(renderer.image)
    }
}
