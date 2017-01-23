//
//  Runner.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Cocoa
import BenchmarkingTools

protocol RunnerDelegate: class {
    func runner(_ runner: Runner, didStartMeasuringSuite suite: String, benchmark: String, size: Int)
    func runner(_ runner: Runner, didMeasureInstanceInSuite suite: String, benchmark: String, size: Int, withResult time: TimeInterval)
    func runner(_ runner: Runner, didStopMeasuringSuite suite: String)
}

private let cachesFolder = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
private let saveFolder = cachesFolder.appendingPathComponent("hu.lorentey.Benchmark")

class Runner {
    var suites: [BenchmarkSuiteProtocol] = []
    var suitesByTitle: [String: BenchmarkSuiteProtocol] = [:]
    var resultsByTitle: [String: BenchmarkSuiteResults] = [:]

    weak var delegate: RunnerDelegate? = nil

    enum State {
        case idle
        case running
        case stopping
    }

    private let lock = NSLock()
    private var _state: State = .idle

    private let queue = DispatchQueue(label: "hu.lorentey.Benchmark.RunnerQueue")

    init() {
    }

    func saveURL(for suite: BenchmarkSuiteProtocol) throws -> URL {
        let name = suite.title.replacingOccurrences(of: "/", with: "-")
        if (try? saveFolder.checkResourceIsReachable()) != true {
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return saveFolder.appendingPathComponent("\(name).plist")
    }

    func load(_ suite: BenchmarkSuiteProtocol) {
        precondition(self.suitesByTitle[suite.title] == nil)
        self.suites.append(suite)
        self.suitesByTitle[suite.title] = suite

        if let url = try? self.saveURL(for: suite),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let results = BenchmarkSuiteResults(from: plist) {
            print("Loaded \(url)")
            self.resultsByTitle[suite.title] = results
        }
    }

    func save() throws {
        for suite in suites {
            let results = self.results(for: suite)
            let data = try! PropertyListSerialization.data(fromPropertyList: results.encode(), format: .xml, options: 0)
            try data.write(to: saveURL(for: suite))
        }
    }

    func reset() {
        self.resultsByTitle = [:]
        try? FileManager.default.removeItem(at: saveFolder)
    }

    var state: State {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _state
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _state = newValue
        }
    }

    func results(for suite: BenchmarkSuiteProtocol) -> BenchmarkSuiteResults {
        if let results = resultsByTitle[suite.title] { return results }
        let results = BenchmarkSuiteResults()
        resultsByTitle[suite.title] = results
        return results
    }

    func results(for title: String) -> BenchmarkSuiteResults {
        return self.results(for: suitesByTitle[title]!)
    }


    func _stopIfNeeded(_ suite: BenchmarkSuiteProtocol) -> Bool {
        guard self.state == .stopping else { return false }
        self.state = .idle
        DispatchQueue.main.async {
            self.delegate?.runner(self, didStopMeasuringSuite: suite.title)
        }
        return true
    }

    func _run(suite: BenchmarkSuiteProtocol, benchmarks: [String], sizes: [Int], i: Int, j: Int, forget: Bool) {
        if self._stopIfNeeded(suite) { return }

        let benchmark = benchmarks[i]
        let size = sizes[j]
        DispatchQueue.main.sync {
            self.delegate?.runner(self, didStartMeasuringSuite: suite.title, benchmark: benchmark, size: size)
        }
        if let time = suite.run(benchmarks[i], sizes[j]) {
            DispatchQueue.main.sync {
                self.results(for: suite.title).addMeasurement(benchmark, size, time)
                self.delegate?.runner(self, didMeasureInstanceInSuite: suite.title, benchmark: benchmark, size: size, withResult: time)
            }
        }
        if self._stopIfNeeded(suite) { return }

        queue.async {
            if i + 1 < benchmarks.count {
                self._run(suite: suite, benchmarks: benchmarks, sizes: sizes, i: i + 1, j: j, forget: forget)
            }
            else {
                if forget {
                    suite.forgetInstances()
                }
                self._run(suite: suite, benchmarks: benchmarks, sizes: sizes, i: 0, j: (j + 1) % sizes.count, forget: forget)
            }
        }
    }

    func start(suite: BenchmarkSuiteProtocol, randomized: Bool, subdivisions: Int = 8) {
        precondition(state == .idle)
        state = .running

        let benchmarks = suite.benchmarkTitles
        let results = self.results(for: suite)

        let range = results.scaleRange
        var sizes: Set<Int> = []
        for i in subdivisions * range.lowerBound ... subdivisions * range.upperBound {
            let size = exp2(Double(i) / Double(subdivisions))
            sizes.insert(Int(size))
        }

        precondition(!benchmarks.isEmpty && !sizes.isEmpty)

        queue.async {
            self._run(suite: suite, benchmarks: benchmarks, sizes: sizes.sorted(),
                      i: 0, j: 0, forget: randomized)
        }
    }

    func stop() {
        precondition(state == .running)
        state = .stopping
    }
}
