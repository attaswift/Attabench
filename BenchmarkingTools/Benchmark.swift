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

fileprivate struct InstanceKey: SipHashable {
    let title: String
    let size: Int

    init(_ title: String, _ size: Int) {
        self.title = title
        self.size = size
    }

    func appendHashes(to hasher: inout SipHasher) {
        hasher.append(title)
        hasher.append(size)
    }
    
    var hashValue: Int {
        return title.hashValue &+ size
    }

    static func ==(left: InstanceKey, right: InstanceKey) -> Bool {
        return left.title == right.title && left.size == right.size
    }
}

public protocol BenchmarkSuiteProtocol {
    var title: String { get }
    var descriptiveTitle: String? { get }
    var descriptiveAmortizedTitle: String? { get }

    var jobTitles: [String] { get }
    func run(_ title: String, _ size: Int) -> TimeInterval?
    func forgetInstances() // FIXME: Move instances out of here
}

public class BenchmarkSuite<Input>: BenchmarkSuiteProtocol {
    public let title: String
    public var descriptiveTitle: String? = nil
    public var descriptiveAmortizedTitle: String? = nil
    
    public private(set) var jobTitles: [String] = []
    private var jobs: [String: BenchmarkJob<Input>] = [:]
    private var instances: [InstanceKey: (BenchmarkTimer) -> Void] = [:]

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

    private func instance(for key: InstanceKey) -> ((BenchmarkTimer) -> Void)? {
        if let instance = instances[key] { return instance }
        guard let job = jobs[key.title] else { fatalError() }
        let input = self.input(for: key.size)
        let instance = job.generate(input: input)
        instances[key] = instance
        return instance
    }

    public func forgetInstances() {
        self.instances = [:]
        self.inputs = [:]
    }

    private func input(for size: Int) -> Input {
        if let input = inputs[size] { return input }
        let input = inputGenerator(size)
        sizes.append(size)
        inputs[size] = input
        return input
    }

    @discardableResult @inline(never)
    public func run(_ title: String, _ size: Int) -> TimeInterval? {
        guard let instance = self.instance(for: InstanceKey(title, size)) else { return nil }
        let start = Timestamp()
        let timer = BenchmarkTimer()
        instance(timer)
        let stop = Timestamp()
        let elapsed = timer.elapsedTime ?? (stop - start)
        return elapsed
    }
}
