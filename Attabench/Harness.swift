//
//  Harness.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-20.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa
import BenchmarkingTools

protocol HarnessDelegate: class {
    func harness(_ harness: Harness, willStartMeasuring instance: BenchmarkInstanceKey)
    func harness(_ harness: Harness, didMeasure instance: BenchmarkInstanceKey, withResult time: Time)
    func harnessDidStopRunning(_ harness: Harness)
}

let bundleIdentifier = Bundle.main.bundleIdentifier!
let cachesFolder = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
let saveFolder = cachesFolder.appendingPathComponent(bundleIdentifier)

extension BenchmarkProtocol {
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

    private let queue = DispatchQueue(label: bundleIdentifier + ".RunnerQueue")

    init() {
    }

    func load(_ benchmark: BenchmarkProtocol) {
        precondition(self.suitesByTitle[benchmark.title] == nil)
        let harness = Suite(benchmark: benchmark)
        self.suites.append(harness)
        self.suitesByTitle[benchmark.title] = harness
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
            self.delegate?.harnessDidStopRunning(self)
        }
        return true
    }

    func _run(suite: Suite, tasks: [String], sizes: [Int], i: Int, j: Int, forget: Bool) {
        if self._stopIfNeeded(suite) { return }

        let task = tasks[i]
        let size = sizes[j]
        let instance = BenchmarkInstanceKey(benchmark: suite.title, task: task, size: size)
        DispatchQueue.main.sync {
            self.delegate?.harness(self, willStartMeasuring: instance)
        }
        if let time = suite.benchmark.run(tasks[i], sizes[j]) {
            DispatchQueue.main.sync {
                suite.addMeasurement(task, size, time)
                self.delegate?.harness(self, didMeasure: instance, withResult: time)
            }
        }
        if forget {
            suite.benchmark.forgetInstances()
        }
        if self._stopIfNeeded(suite) { return }

        queue.async {
            if i + 1 < tasks.count {
                self._run(suite: suite, tasks: tasks, sizes: sizes, i: i + 1, j: j, forget: forget)
            }
            else {
                if forget {
                    suite.benchmark.forgetInputs()
                }
                self._run(suite: suite, tasks: tasks, sizes: sizes,
                          i: 0, j: (j + 1) % sizes.count, forget: forget)
            }
        }
    }

    func start(suite: Suite, randomized: Bool, subdivisions: Int = 8) {
        precondition(state == .idle)
        state = .running

        let tasks = suite.selectedTasks

        let range = suite.scaleRange
        var sizes: Set<Int> = []
        for i in subdivisions * range.lowerBound ... subdivisions * range.upperBound {
            let size = exp2(Double(i) / Double(subdivisions))
            sizes.insert(Int(size))
        }

        precondition(!tasks.isEmpty && !sizes.isEmpty)

        queue.async {
            self._run(suite: suite, tasks: tasks, sizes: sizes.sorted(), i: 0, j: 0, forget: randomized)
        }
    }

    func stop() {
        precondition(state == .running)
        state = .stopping
    }
}

class Suite: Codable {
    let benchmark: BenchmarkProtocol
    var samplesByTask: [String: TaskResults] = [:]

    var scaleRange: CountableClosedRange<Int> {
        didSet { saveConfig() }
    }
    private var _selectedTaskSet: Set<String> = [] {
        didSet { saveConfig() }
    }

    var selectedTaskSet: Set<String> {
        get {
            return _selectedTaskSet
        }
        set {
            let value = newValue.intersection(benchmark.taskTitles)
            if value.isEmpty { _selectedTaskSet = Set(benchmark.taskTitles) }
            else { _selectedTaskSet = value }
        }
    }

    var selectedTasks: [String] {
        get {
            return benchmark.taskTitles.filter(selectedTaskSet.contains)
        }
        set {
            selectedTaskSet = Set(newValue)
        }
    }

    var title: String { return benchmark.title }
    var taskTitles: [String] { return benchmark.taskTitles }
    var sizeRange: ClosedRange<Int> { return (1 << scaleRange.lowerBound) ... (1 << scaleRange.upperBound) }

    init(benchmark: BenchmarkProtocol) {
        self.benchmark = benchmark

        do { // Load configuration
            let dict = UserDefaults.standard.dictionary(forKey: "BenchmarkConfig-\(benchmark.title)") ?? [:]

            let minScale = dict["MinScale"] as? Int ?? 0
            let maxScale = dict["MaxScale"] as? Int ?? 20
            self.scaleRange = minScale ... maxScale

            let selected = dict["SelectedTasks"] as? [String] ?? []
            self._selectedTaskSet = Set(selected).intersection(benchmark.taskTitles)
            if _selectedTaskSet.isEmpty { _selectedTaskSet = Set(benchmark.taskTitles) }
        }

        do { // Load saved results
            let url = benchmark.saveURL
            if let savedData = try? Data(contentsOf: url),
                let plist = (try? PropertyListSerialization.propertyList(from: savedData, format: nil)) as? [String: Any],
                let data = plist["Data"] as? [String: Any] {
                for (title, samples) in data {
                    guard let s = TaskResults(from: samples) else { continue }
                    self.samplesByTask[title] = s
                }
                print("Loaded \(url)")
            }
        }
    }

    func save() throws {
        var encoder = PropertyListEncoder()
        let data = try PropertyListEncoder().encode(samplesByTask)

        var encoded: [String: Any] = [:]
        for (title, samples) in samplesByTask {
            encoded[title] = samples.encode()
        }
        let plist: [String: Any] = ["Data": encoded]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: benchmark.saveURL)
        saveConfig()
    }

    func reset() throws {
        self.samplesByTask = [:]
        try? FileManager.default.removeItem(at: benchmark.saveURL)
    }

    private func saveConfig() {
        let dict: [String: Any] = [
            "MinScale": scaleRange.lowerBound,
            "MaxScale": scaleRange.upperBound,
            "SelectedTasks": Array(selectedTasks)
        ]
        UserDefaults.standard.set(dict, forKey: "BenchmarkConfig-\(title)")
    }

    func samples(for task: String) -> TaskResults {
        if let samples = samplesByTask[task] { return samples }
        precondition(benchmark.taskTitles.contains(task))
        let samples = TaskResults()
        samplesByTask[task] = samples
        return samples
    }

    func addMeasurement(_ task: String, _ size: Int, _ time: Time) {
        samples(for: task).addMeasurement(time, forSize: size)
    }
}
