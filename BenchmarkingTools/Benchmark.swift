//
//  Benchmark.swift
//  Attabench
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import SipHash

public class BenchmarkTimer {
    var elapsedTime: TimeInterval? = nil

    @inline(never)
    public func measure(_ body: () -> ()) {
        let start = Timestamp()
        body()
        let end = Timestamp()
        elapsedTime = end - start
    }
}

fileprivate class BenchmarkTask<Input> {
    let title: String
    let body: (Input) -> ((BenchmarkTimer) -> Void)?

    init(_ title: String, _ body: @escaping (Input) -> ((BenchmarkTimer) -> Void)?) {
        self.title = title
        self.body = body
    }

    func generate(input: Input) -> ((BenchmarkTimer) -> Void)? {
        return self.body(input)
    }
}

public struct BenchmarkInstanceKey: SipHashable {
    public let benchmark: String
    public let task: String
    public let size: Int

    public init(benchmark: String, task: String, size: Int) {
        self.benchmark = benchmark
        self.task = task
        self.size = size
    }

    public func appendHashes(to hasher: inout SipHasher) {
        hasher.append(benchmark)
        hasher.append(task)
        hasher.append(size)
    }
    
    public static func ==(left: BenchmarkInstanceKey, right: BenchmarkInstanceKey) -> Bool {
        return left.benchmark == right.benchmark && left.task == right.task && left.size == right.size
    }
}

public protocol BenchmarkProtocol {
    var title: String { get }
    var descriptiveTitle: String? { get }
    var descriptiveAmortizedTitle: String? { get }

    var taskTitles: [String] { get }
    func run(_ title: String, _ size: Int) -> TimeInterval?
    func forgetInputs() // FIXME: Move instances out of here
    func forgetInstances() // FIXME: Move instances out of here
}

public class Benchmark<Input>: BenchmarkProtocol {
    public let title: String
    public var descriptiveTitle: String? = nil
    public var descriptiveAmortizedTitle: String? = nil
    
    public private(set) var taskTitles: [String] = []
    private var tasks: [String: BenchmarkTask<Input>] = [:]
    private var instances: [BenchmarkInstanceKey: (BenchmarkTimer) -> Void] = [:]

    private let inputGenerator: (Int) -> Input
    public private(set) var sizes: [Int] = []
    private var inputs: [Int: Input] = [:] // Input size to input data

    public init<Generator: InputGeneratorProtocol>(title: String, inputGenerator: Generator) where Generator.Value == Input {
        self.title = title
        self.inputGenerator = inputGenerator.generate
    }

    public init(title: String, inputGenerator: @escaping (Int) -> Input) {
        self.title = title
        self.inputGenerator = inputGenerator
    }

    public func addTask(title: String, _ body: @escaping (Input) -> ((BenchmarkTimer) -> Void)?) {
        precondition(self.tasks[title] == nil)
        self.taskTitles.append(title)
        self.tasks[title] = BenchmarkTask(title, body)
    }

    public func addSimpleTask(title: String, _ body: @escaping (Input) -> Void) {
        self.addTask(title: title) { input in
            return { timer in timer.measure { body(input) } }
        }
    }

    public func addTimerTask(title: String, _ body: @escaping (Input, BenchmarkTimer) -> Void) {
        self.addTask(title: title) { input in
            return { timer in body(input, timer) }
        }
    }

    private func instance(for key: BenchmarkInstanceKey) -> ((BenchmarkTimer) -> Void)? {
        if let instance = instances[key] { return instance }
        guard let task = tasks[key.task] else { fatalError() }
        let input = self.input(for: key.size)
        let instance = task.generate(input: input)
        instances[key] = instance
        return instance
    }

    public func forgetInputs() {
        self.inputs = [:]
        forgetInstances()
    }

    public func forgetInstances() {
        self.instances = [:]
    }

    private func input(for size: Int) -> Input {
        if let input = inputs[size] { return input }
        let input = inputGenerator(size)
        sizes.append(size)
        inputs[size] = input
        return input
    }

    @discardableResult @inline(never)
    public func run(_ task: String, _ size: Int) -> TimeInterval? {
        let key = BenchmarkInstanceKey(benchmark: title, task: task, size: size)
        guard let instance = self.instance(for: key) else { return nil }
        let start = Timestamp()
        let timer = BenchmarkTimer()
        instance(timer)
        let stop = Timestamp()
        let elapsed = timer.elapsedTime ?? (stop - start)
        return elapsed
    }
}

extension Benchmark where Input == [Int] {
    public convenience init(title: String) {
        self.init(title: title, inputGenerator: RandomArrayGenerator())
    }
}

extension Benchmark where Input == ([Int], [Int]) {
    public convenience init(title: String) {
        self.init(title: title, inputGenerator: PairGenerator(RandomArrayGenerator(), RandomArrayGenerator()))
    }
}
