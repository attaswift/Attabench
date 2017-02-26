//
//  Benchmark.swift
//
//  Copyright © 2017 Károly Lőrentey.
//

import Foundation
import SipHash

extension Array {
    var randomElement: Element {
        precondition(count > 0)
        let index = Int(arc4random_uniform(UInt32(count)))
        return self[index]
    }
}

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

fileprivate class BenchmarkJob<Input> {
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
    public let job: String
    public let size: Int

    public init(benchmark: String, job: String, size: Int) {
        self.benchmark = benchmark
        self.job = job
        self.size = size
    }

    public func appendHashes(to hasher: inout SipHasher) {
        hasher.append(benchmark)
        hasher.append(job)
        hasher.append(size)
    }
    
    public static func ==(left: BenchmarkInstanceKey, right: BenchmarkInstanceKey) -> Bool {
        return left.benchmark == right.benchmark && left.job == right.job && left.size == right.size
    }
}

public protocol BenchmarkProtocol {
    var title: String { get }
    var descriptiveTitle: String? { get }
    var descriptiveAmortizedTitle: String? { get }

    var jobTitles: [String] { get }
    func run(_ title: String, _ size: Int) -> TimeInterval?
    func forgetInputs() // FIXME: Move instances out of here
    func forgetInstances() // FIXME: Move instances out of here
}

public class Benchmark<Input>: BenchmarkProtocol {
    public let title: String
    public var descriptiveTitle: String? = nil
    public var descriptiveAmortizedTitle: String? = nil
    
    public private(set) var jobTitles: [String] = []
    private var jobs: [String: BenchmarkJob<Input>] = [:]
    private var instances: [BenchmarkInstanceKey: (BenchmarkTimer) -> Void] = [:]

    private let inputGenerator: (Int) -> Input
    public private(set) var sizes: [Int] = []
    private var inputs: [Int: Input] = [:] // Input size to input data

    public init(title: String, inputGenerator: @escaping (Int) -> Input) {
        self.title = title
        self.inputGenerator = inputGenerator
    }

    public func addJob(title: String, _ body: @escaping (Input) -> ((BenchmarkTimer) -> Void)?) {
        precondition(self.jobs[title] == nil)
        self.jobTitles.append(title)
        self.jobs[title] = BenchmarkJob(title, body)
    }

    private func instance(for key: BenchmarkInstanceKey) -> ((BenchmarkTimer) -> Void)? {
        if let instance = instances[key] { return instance }
        guard let job = jobs[key.job] else { fatalError() }
        let input = self.input(for: key.size)
        let instance = job.generate(input: input)
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
    public func run(_ job: String, _ size: Int) -> TimeInterval? {
        let key = BenchmarkInstanceKey(benchmark: title, job: job, size: size)
        guard let instance = self.instance(for: key) else { return nil }
        let start = Timestamp()
        let timer = BenchmarkTimer()
        instance(timer)
        let stop = Timestamp()
        let elapsed = timer.elapsedTime ?? (stop - start)
        return elapsed
    }
}
