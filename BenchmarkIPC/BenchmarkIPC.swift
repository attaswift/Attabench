// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

public enum BenchmarkIPC {
    /// Represents an output format for the command line interface.
    /// Note that attabench internal IPC is always encoded in JSON; this option is ignored for that.
    public enum OutputFormat: String, Codable {
        case pretty
        case json
    }

    /// The options available for running benchmarks.
    public struct RunOptions: Codable {
        /// The tasks to run.
        public var tasks: [String]
        /// The sizes on which to run tasks.
        public var sizes: [Int]
        /// Output format for the command line interface. (Ignored for internal IPC.)
        public var outputFormat: OutputFormat
        /// The number of times to run each task/size measurement.
        /// The reported result is the minimum elapsed time across all iterations.
        /// (Depending on how slow/fast the task is, this count may get overridden by `minDuration` and/or `maxDuration`.)
        public var iterations: Int
        /// Repeat each particular task/size measurement until at least this amount of time has passed.
        /// (When this is positive, tasks may get run for more than `iterations` times.)
        public var minDuration: Double?
        /// Stop repeating a particular task/size measurement after this amount of time has passed.
        /// (When this is finite, tasks may get run for less than `iterations` times.)
        public var maxDuration: Double?

        public init(tasks: [String] = [],
                    sizes: [Int] = [],
                    outputFormat: OutputFormat = .pretty,
                    iterations: Int = 3,
                    minDuration: Double? = nil,
                    maxDuration: Double? = nil) {
            self.tasks = tasks
            self.sizes = sizes
            self.outputFormat = outputFormat
            self.iterations = iterations
            self.minDuration = minDuration
            self.maxDuration = maxDuration
        }
    }

    /// The benchmarking operation to perform.
    /// This is encoded as JSON, and then sent to the standard input of the benchmark process.
    public enum Command: Codable {
        /// Write available tasks to the report file, then exit immediately.
        case list
        /// Start running the specified measurements indefinitely.
        /// The benchmark process is expected to write a `RunProgressReport` value to the report file before/after
        /// each successful measurement.
        /// When enough measurements have been collected, the benchmark runner sends a SIGTERM signal to the
        /// benchmark process, which is expected to exit within 2 seconds after receiving it.
        /// If the benchmark process fails to exit by this deadline, the benchmark runner forcibly kills it with SIGKILL.
        case run(RunOptions)

        enum Code: String, Codable {
            case list
            case run
        }

        enum Key: String, CodingKey {
            case command
            case parameters
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            switch try container.decode(Code.self, forKey: .command) {
            case .list:
                self = .list
            case .run:
                self = .run(try container.decode(RunOptions.self, forKey: .parameters))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .list:
                try container.encode(Code.list, forKey: .command)
            case .run(let options):
                try container.encode(Code.run, forKey: .command)
                try container.encode(options, forKey: .parameters)
            }
        }
    }

    /// Information about the execution state and results of a running benchmark.
    /// Benchmark processes are expected to report their progress by encoding instances of this type
    /// as JSON to their report file.
    public enum Report: Codable {
        /// The list of available tasks. (The answer for a `.list` command.)
        /// The process should exit on its own after sending this report.
        case list(tasks: [String])
        /// A new measurement is starting to execute.
        case begin(task: String, size: Int)
        /// A task has been successfully benchmarked at the specified size.
        /// The reported time is the minimum of all individual measurements.
        case finish(task: String, size: Int, time: Double)

        enum Key: String, CodingKey {
            case code
            case tasks
            case task
            case size
            case time
        }

        enum Code: String, Codable {
            case list
            case begin
            case finish
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            switch try container.decode(Code.self, forKey: .code) {
            case .list:
                self = .list(tasks: try container.decode([String].self, forKey: .tasks))
            case .begin:
                self = .begin(task: try container.decode(String.self, forKey: .task),
                              size: try container.decode(Int.self, forKey: .size))
            case .finish:
                self = .finish(task: try container.decode(String.self, forKey: .task),
                               size: try container.decode(Int.self, forKey: .size),
                               time: try container.decode(Double.self, forKey: .time))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            switch self {
            case .list(tasks: let tasks):
                try container.encode(Code.list, forKey: .code)
                try container.encode(tasks, forKey: .tasks)
            case let .begin(task: task, size: size):
                try container.encode(Code.begin, forKey: .code)
                try container.encode(task, forKey: .task)
                try container.encode(size, forKey: .size)
            case let .finish(task: task, size: size, time: time):
                try container.encode(Code.finish, forKey: .code)
                try container.encode(task, forKey: .task)
                try container.encode(size, forKey: .size)
                try container.encode(time, forKey: .time)
            }
        }
    }
}


