// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

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
    let labeler: (Int) -> String
    let min: Double
    let max: Double
    let minExponent: Int
    let maxExponent: Int
    let grid: (major: Double, minor: Double)

    init(_ range: ClosedRange<Double>, decimal: Bool, labeler: @escaping (Int) -> String) {
        let range = (range.lowerBound > 0 ? range : 1e-30 ... range.upperBound)
        self.decimal = decimal
        self.labeler = labeler

        let step = decimal ? 10.0 : 2.0

        let smudge = 0.001
        
        // Find last major gridline below range.
        let rescaledUpperBound: Double
        if range.lowerBound < 1 {
            var s: Double = 1
            var minExponent = 0
            while range.lowerBound * s + smudge < 1 {
                s *= step
                minExponent -= 1
            }
            self.min = 1 / s
            self.minExponent = minExponent
            rescaledUpperBound = range.upperBound * s
        }
        else {
            var s: Double = 1
            var minExponent = 0
            while s * step <= range.lowerBound {
                s *= step
                minExponent += 1
            }
            self.min = s
            self.minExponent = minExponent
            rescaledUpperBound = range.upperBound / s
        }

        // Find first major gridline above range.
        var maxExponent = minExponent
        var s: Double = 1
        repeat {
            s *= step
            maxExponent += 1
        } while s < rescaledUpperBound * (1 - smudge)
        self.max = self.min * s
        self.maxExponent = maxExponent

        self.grid = (major: log(step) / (log(max) - log(min)),
                     minor: decimal ? log(2) / (log(max) - log(min)) : 0)
    }

    var gridlines: [Gridline] {
        var gridlines: [Gridline] = []
        let step = decimal ? 10.0 : 2.0
        for exponent in minExponent ... maxExponent {
            let position = self.position(for: pow(step, Double(exponent)))
            let label = self.labeler(exponent)
            gridlines.append(Gridline(.major, position: position, label: label))
        }
        if decimal {
            var value = 2 * min
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
        if value <= 0 { return 0 }
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

    init(_ range: ClosedRange<Double>, decimal: Bool, labeler: @escaping (Double) -> String) {
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
