// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import OptionParser
import BenchmarkIPC

extension RunOptions.OutputFormat: OptionValue {}

struct AttabenchOptions {
    var reportFile: String = ""
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
             minimumDuration: TimeInterval?,
             maximumDuration: TimeInterval?,
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
                    } while (duration < maximumDuration ?? .infinity
                        && (iteration < iterations || duration < minimumDuration ?? 0))
                    try output.finish(task: task.title, size: size, time: minimum!)
                    found = true
                }
                if !found {
                    sizes = sizes.filter { $0 != size }
                }
            }
        }
    }

    func run(_ options: RunOptions, output: OutputProtocol? = nil) throws {
        print(options)
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

        let output = output ?? {
            switch options.outputFormat {
            case .pretty:
                return PrettyOutput(to: OutputFile(.standardOutput))
            case .json:
                return JSONOutput(to: OutputFile(.standardOutput))
            }
        }()
        try self.run(tasks: tasks,
                 sizes: sizes,
                 output: output,
                 minimumDuration: options.minimumDuration,
                 maximumDuration: options.maximumDuration,
                 iterations: options.iterations)
    }

    func attarun(reportFile: String) throws {
        let decoder = JSONDecoder()
        guard let outputHandle = FileHandle(forWritingAtPath: reportFile) else {
            throw CocoaError.error(.fileNoSuchFile)
        }
        defer { outputHandle.closeFile() }
        let output = OutputFile(outputHandle)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let command = try decoder.decode(Command.self, from: input)
        switch command {
        case .list:
            let list = try! JSONEncoder().encode(Report.list(tasks: self.taskTitles))
            try output.write(list + [0x0a])
            sleep(1)
        case .run(let options):
            try self.run(options, output: JSONOutput(to: output))
        }
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
                .command(for: AttabenchOptions.self,
                         name: "attabench", docs: "Run benchmarks inside an Attabench session",
                         initial: { _ in AttabenchOptions() },
                         parameters: [
                            .required(for: \.reportFile, metavariable: "<path>", docs: "Path to the report fifo")],
                         action: { options in
                            try self.attarun(reportFile: options.reportFile) }),
                .command(for: RunOptions.self,
                         name: "run", docs: "Run selected benchmarks.",
                         initial: { _ in RunOptions() },
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
                            .value(for: \.minimumDuration,
                                   name: "min-duration", metavariable: "<seconds>",
                                   docs: "Repeat each task for at least this amount of seconds (default: 0.0)"),
                            .value(for: \.maximumDuration,
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
