// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

class BenchmarkTask<Input> {
    let title: String
    let body: (Input) -> ((BenchmarkTimer) -> Void)?

    init(_ title: String, _ body: @escaping (Input) -> ((BenchmarkTimer) -> Void)?) {
        precondition(!title.starts(with: "-"), "Benchmark task title must not begin with '-'")
        self.title = title
        self.body = body
    }

    func generate(input: Input) -> ((BenchmarkTimer) -> Void)? {
        return self.body(input)
    }
}

public class Benchmark<Input> {
    public let title: String
    public var descriptiveTitle: String? = nil
    public var descriptiveAmortizedTitle: String? = nil

    public private(set) var taskTitles: [String] = []
    
    private(set) var tasks: [String: BenchmarkTask<Input>] = [:]
    let inputGenerator: (Int) -> Input

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

