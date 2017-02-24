//
//  Harness.swift
//  dotSwift
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017. Károly Lőrentey. All rights reserved.
//

import Cocoa
import BenchmarkingTools

protocol HarnessDelegate: class {
    func harness(_ harness: Harness, didStartMeasuringSuite suite: String, job: String, size: Int)
    func harness(_ harness: Harness, didMeasureInstanceInSuite suite: String, job: String, size: Int, withResult time: TimeInterval)
    func harness(_ harness: Harness, didStopMeasuringSuite suite: String)
}

let cachesFolder = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
let saveFolder = cachesFolder.appendingPathComponent("hu.lorentey.Benchmark")

extension BenchmarkSuiteProtocol {
    var saveURL: URL {
        let name = self.title.replacingOccurrences(of: "/", with: "-")
        return saveFolder.appendingPathComponent("\(name).plist")
    }
}

class Harness {
    var suites: [Suite] = []
    var suitesByTitle: [String: Suite] = [:]

    weak var delegate: HarnessDelegate? = nil

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

    func load(_ suite: BenchmarkSuiteProtocol) {
        precondition(self.suitesByTitle[suite.title] == nil)
        let harness = Suite(suite: suite)
        self.suites.append(harness)
        self.suitesByTitle[suite.title] = harness
    }

    func save() throws {
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        for suite in suites { try suite.save() }
    }

    func reset() throws {
        for suite in suites { try suite.reset() }
        try FileManager.default.removeItem(at: saveFolder)
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

    subscript(index: Int) -> Suite {
        return suites[index]
    }

    subscript(title: String) -> Suite {
        return suitesByTitle[title]!
    }

    func _stopIfNeeded(_ suite: Suite) -> Bool {
        guard self.state == .stopping else { return false }
        self.state = .idle
        DispatchQueue.main.async {
            self.delegate?.harness(self, didStopMeasuringSuite: suite.title)
        }
        return true
    }

    func _run(suite: Suite, jobs: [String], sizes: [Int], i: Int, j: Int, forget: Bool) {
        if self._stopIfNeeded(suite) { return }

        let job = jobs[i]
        let size = sizes[j]
        DispatchQueue.main.sync {
            self.delegate?.harness(self, didStartMeasuringSuite: suite.title, job: job, size: size)
        }
        if let time = suite.suite.run(jobs[i], sizes[j]) {
            DispatchQueue.main.sync {
                suite.addMeasurement(job, size, time)
                self.delegate?.harness(self, didMeasureInstanceInSuite: suite.title, job: job, size: size, withResult: time)
            }
        }
        if self._stopIfNeeded(suite) { return }

        queue.async {
            if i + 1 < jobs.count {
                self._run(suite: suite, jobs: jobs, sizes: sizes, i: i + 1, j: j, forget: forget)
            }
            else {
                if forget {
                    suite.suite.forgetInstances()
                }
                self._run(suite: suite, jobs: jobs, sizes: sizes,
                          i: 0, j: (j + 1) % sizes.count, forget: forget)
            }
        }
    }

    func start(suite: Suite, randomized: Bool, subdivisions: Int = 8) {
        precondition(state == .idle)
        state = .running

        let jobs = suite.selectedJobs

        let range = suite.scaleRange
        var sizes: Set<Int> = []
        for i in subdivisions * range.lowerBound ... subdivisions * range.upperBound {
            let size = exp2(Double(i) / Double(subdivisions))
            sizes.insert(Int(size))
        }

        precondition(!jobs.isEmpty && !sizes.isEmpty)

        queue.async {
            self._run(suite: suite, jobs: jobs, sizes: sizes.sorted(), i: 0, j: 0, forget: randomized)
        }
    }

    func stop() {
        precondition(state == .running)
        state = .stopping
    }
}

class Suite {
    let suite: BenchmarkSuiteProtocol
    var samplesByJob: [String: JobResults] = [:]

    var scaleRange: CountableClosedRange<Int> {
        didSet { saveConfig() }
    }
    private var _selectedJobSet: Set<String> = [] {
        didSet { saveConfig() }
    }

    var selectedJobSet: Set<String> {
        get {
            return _selectedJobSet
        }
        set {
            let value = newValue.intersection(suite.jobTitles)
            if value.isEmpty { _selectedJobSet = Set(suite.jobTitles) }
            else { _selectedJobSet = value }
        }
    }

    var selectedJobs: [String] {
        get {
            return suite.jobTitles.filter(selectedJobSet.contains)
        }
        set {
            selectedJobSet = Set(newValue)
        }
    }

    var title: String { return suite.title }
    var jobTitles: [String] { return suite.jobTitles }
    var sizeRange: ClosedRange<Int> { return (1 << scaleRange.lowerBound) ... (1 << scaleRange.upperBound) }

    init(suite: BenchmarkSuiteProtocol) {
        self.suite = suite

        do { // Load configuration
            let dict = UserDefaults.standard.dictionary(forKey: "Config-\(suite.title)") ?? [:]

            let minScale = dict["MinScale"] as? Int ?? 0
            let maxScale = dict["MaxScale"] as? Int ?? 20
            self.scaleRange = minScale ... maxScale

            let selected = dict["SelectedJobs"] as? [String] ?? []
            self._selectedJobSet = Set(selected).intersection(suite.jobTitles)
            if _selectedJobSet.isEmpty { _selectedJobSet = Set(suite.jobTitles) }
        }

        do { // Load saved results
            let url = suite.saveURL
            if let savedData = try? Data(contentsOf: url),
                let plist = (try? PropertyListSerialization.propertyList(from: savedData, format: nil)) as? [String: Any],
                let data = plist["Data"] as? [String: Any] {
                for (title, samples) in data {
                    guard let s = JobResults(from: samples) else { continue }
                    self.samplesByJob[title] = s
                }
                print("Loaded \(url)")
            }
        }
    }

    func save() throws {
        var encoded: [String: Any] = [:]
        for (title, samples) in samplesByJob {
            encoded[title] = samples.encode()
        }
        let plist: [String: Any] = ["Data": encoded]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: suite.saveURL)
        saveConfig()
    }

    func reset() throws {
        self.samplesByJob = [:]
    }

    private func saveConfig() {
        let dict: [String: Any] = [
            "MinScale": scaleRange.lowerBound,
            "MaxScale": scaleRange.upperBound,
            "SelectedJobs": Array(selectedJobs)
        ]
        UserDefaults.standard.set(dict, forKey: "Config-\(title)")
    }

    func samples(for job: String) -> JobResults {
        if let samples = samplesByJob[job] { return samples }
        precondition(suite.jobTitles.contains(job))
        let samples = JobResults()
        samplesByJob[job] = samples
        return samples
    }

    func addMeasurement(_ job: String, _ size: Int, _ time: TimeInterval) {
        samples(for: job).addMeasurement(time, forSize: size)
    }
}
