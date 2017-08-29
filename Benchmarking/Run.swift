// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import OptionParser

enum OutputFormat: String, OptionValue {
    case pretty
    case json
}

struct RunOptions {
    var tasks: [String] = []
    var sizes: [Int] = []
    var outputFormat: OutputFormat = .pretty
    var iterations: Int = 3
    var minDuration: Double = 0
    var maxDuration: Double = .infinity
}

extension Benchmark {
    func listTasks() {
        for task in taskTitles {
            print(task)
        }
    }

    func run(tasks: [BenchmarkTask<Input>],
             sizes: [Int],
             output: OutputProtocol,
             minDuration: TimeInterval,
             maxDuration: TimeInterval,
             iterations: Int) throws {
        var sizes = sizes
        while !sizes.isEmpty {
            for size in sizes {
                let input = self.inputGenerator(size)
                var found = false
                for task in tasks {
                    try output.begin(task: task.title, size: size)
                    guard let instance = TaskInstance(task: task, size: size, input: input) else { continue }
                    var minimum: TimeInterval? = nil
                    var duration: TimeInterval = 0
                    var iteration = 0
                    repeat {
                        let elapsed = instance.run()
                        minimum = Swift.min(elapsed, minimum ?? elapsed)
                        try output.progress(task: task.title, size: size, time: elapsed)
                        duration += elapsed
                        iteration += 1
                    } while (duration < maxDuration
                        && (iteration < iterations || duration < minDuration))
                    try output.finish(task: task.title, size: size, time: minimum!)
                    found = true
                }
                if !found {
                    sizes = sizes.filter { $0 != size }
                }
            }
        }
    }

    func run(_ options: RunOptions) throws {
        var tasks: [BenchmarkTask<Input>] = try options.tasks.map { title in
            guard let task = self.tasks[title] else {
                throw OptionError("Unknown task '\(title)'")
            }
            return task
        }
        if tasks.isEmpty {
            tasks = taskTitles.map { self.tasks[$0]! }
        }
        var sizes = options.sizes
        guard !sizes.isEmpty else {
            throw OptionError("Need at least one size")
        }
        if let i = sizes.index(where: { $0 < 1 }) {
            throw OptionError("Invalid size \(sizes[i])")
        }
        guard options.iterations > 0 else {
            throw OptionError("Invalid iteration count")
        }

        let output: OutputProtocol
        switch options.outputFormat {
        case .pretty:
            output = PrettyOutput(to: OutputFile(.standardOutput))
        case .json:
            output = JSONOutput(to: OutputFile(.standardOutput))
        }
        try self.run(tasks: tasks,
                 sizes: sizes,
                 output: output,
                 minDuration: options.minDuration,
                 maxDuration: options.maxDuration,
                 iterations: options.iterations)
    }

    public func start() {
        let parser = OptionParser<Void>(
            docs: "",
            initial: (),
            options: [],
            commands: [
                .command(for: Void.self, name: "list", docs: "List available tasks.",
                         initial: { _ in () },
                         options: [],
                         parameters: [],
                         action: { _ in self.listTasks() }),
                .command(for: RunOptions.self,
                         name: "run", docs: "Run selected benchmarks.",
                         initial: { (_: Void) -> RunOptions in RunOptions() },
                         options: [
                            .array(of: String.self, for: \.tasks,
                                   name: "tasks", metavariable: "<name>",
                                   docs: "Benchmark tasks to run (default: all benchmarks)"),
                            .flag(for: \.tasks, value: [], name: "all", docs: "Run all benchmarks"),
                            .array(of: Int.self, for: \.sizes,
                                   name: "sizes", docs: "Input sizes to measure"),
                            .value(for: \.iterations,
                                   name: "iterations", metavariable: "<int>",
                                   docs: "Number of iterations to run (default: 1)"),
                            .value(for: \.minDuration,
                                   name: "min-duration", metavariable: "<seconds>",
                                   docs: "Repeat each task for at least this amount of seconds (default: 0.0)"),
                            .value(for: \.maxDuration,
                                   name: "max-duration", metavariable: "<seconds>",
                                   docs: "Stop repeating tasks after this amount of time (default: +infinity)"),
                            .value(for: \.outputFormat,
                                   name: "format", metavariable: "pretty|json",
                                   docs: "Output format (default: pretty)")],
                         parameters: [],
                         action: { options in try self.run(options) })])

        do {
            try parser.parse()
            exit(0)
        }
        catch let error as OptionError {
            complain(error.message)
            exit(1)
        }
        catch {
            complain(error.localizedDescription)
            exit(1)
        }
    }
}


struct TaskInstance<Input> {
    let task: BenchmarkTask<Input>
    let size: Int
    let instance: (BenchmarkTimer) -> Void

    init?(task: BenchmarkTask<Input>, size: Int, input: Input) {
        self.task = task
        self.size = size
        guard let instance = task.generate(input: input) else { return nil }
        self.instance = instance
    }

    @inline(never)
    func run() -> TimeInterval {
        return BenchmarkTimer.measure(instance)
    }
}
