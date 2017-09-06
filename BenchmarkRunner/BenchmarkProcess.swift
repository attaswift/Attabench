 // Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import Darwin
import BenchmarkIPC
import BenchmarkModel

public protocol BenchmarkDelegate {
    func benchmark(_ benchmark: BenchmarkProcess, didReceiveListOfTasks tasks: [String])
    func benchmark(_ benchmark: BenchmarkProcess, willMeasureTask task: String, atSize size: Int)
    func benchmark(_ benchmark: BenchmarkProcess, didMeasureTask task: String, atSize size: Int, withResult time: Time)
    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardOutput line: String)
    func benchmark(_ benchmark: BenchmarkProcess, didPrintToStandardError line: String)
    func benchmark(_ benchmark: BenchmarkProcess, didFailWithError error: String)
    func benchmarkDidStop(_ benchmark: BenchmarkProcess)
}

extension BenchmarkDelegate {
    public func benchmark(_ benchmark: BenchmarkProcess, didSendListOfTasks tasks: [String]) {}
    public func benchmark(_ benchmark: BenchmarkProcess, didFailWithError error: String) {}
}

public class BenchmarkProcess {
    private struct Delegate: CommandLineDelegate {
        unowned let benchmark: BenchmarkProcess

        init(_ benchmark: BenchmarkProcess) {
            self.benchmark = benchmark
        }

        func commandLineProcess(_ process: CommandLineProcess, didPrintToStandardOutput line: String) {
            precondition(process === benchmark.process)
            var line = line
            if line.last == "\n" { line.removeLast() }
            benchmark.delegate.benchmark(benchmark, didPrintToStandardOutput: line)
        }

        func commandLineProcess(_ process: CommandLineProcess, didPrintToStandardError line: String) {
            precondition(process === benchmark.process)
            var line = line
            if line.last == "\n" { line.removeLast() }
            benchmark.delegate.benchmark(benchmark, didPrintToStandardError: line)
        }

        func commandLineProcess(_ process: CommandLineProcess, channel: CommandLineProcess.Channel, didFailWithError error: Int32) {
            precondition(process === benchmark.process)
            guard error != 0 else { return } // EOF
            guard process.isRunning else { return }
            benchmark.fail(String(posixError: error))
        }

        func commandLineProcess(_ process: CommandLineProcess, didExitWithState state: CommandLineProcess.ExitState) {
            precondition(process === benchmark.process)
            benchmark.cleanup()
            guard !benchmark.hasFailed else { return }
            switch state {
            case .exit(0):
                benchmark.delegate.benchmarkDidStop(benchmark)
            case .exit(let code):
                benchmark.fail("Process exited with code \(code)")
            case .uncaughtSignal(SIGTERM):
                benchmark.fail("Process terminated")
            case .uncaughtSignal(SIGKILL):
                benchmark.fail("Process killed")
            case .uncaughtSignal(let signal):
                benchmark.fail(String(signal: signal))
            }
        }
    }
    public let url: URL
    public let delegate: BenchmarkDelegate
    public let delegateQueue: DispatchQueue
    public let command: BenchmarkIPC.Command

    let fm = FileManager()
    let temporaryFolder: URL
    let reportQueue = DispatchQueue(label: "org.attaswift.Attabench.report")
    var reportChannel: DispatchIO

    var process: CommandLineProcess! = nil
    var killTimer: DispatchSourceTimer? = nil
    var hasFailed = false

    public init(url: URL, command: Command, delegate: BenchmarkDelegate, on delegateQueue: DispatchQueue) throws {
        let input = try JSONEncoder().encode(command)
        self.url = url
        self.delegate = delegate
        self.delegateQueue = delegateQueue
        self.command = command

        self.temporaryFolder = try fm.createTemporaryFolder("Attabench.XXXXXXX")
        let reportPipe = temporaryFolder.appendingPathComponent("report.fifo")
        do {
            // Create report channel.
            try fm.createFIFO(at: reportPipe)

            let reportFD = open(reportPipe.path, O_RDWR) // We won't write, but having it prevents early EOF in DispatchIO
            guard reportFD != -1 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSURLErrorKey: reportPipe])
            }
            reportChannel = DispatchIO(type: .stream,
                                       fileDescriptor: reportFD,
                                       queue: reportQueue,
                                       cleanupHandler: { result in close(reportFD) })
            reportChannel.setLimit(lowWater: 1)
            reportChannel.setInterval(interval: .milliseconds(100))

            reportChannel.readRecords(on: delegateQueue, delimitedBy: 0x0A) { chunk in
                switch chunk {
                case .endOfFile:
                    self.fail("Report file closed")
                case .error(ECANCELED):
                    break // Ignore
                case .error(let error):
                    self.fail(String(posixError: error))
                case .record(let data):
                    self.processReport(data)
                }
            }
        }
        catch {
            try? fm.removeItem(at: temporaryFolder)
            throw error
        }

        // Create process
        self.process = CommandLineProcess(launchPath: "/bin/sh",
                                          workingDirectory: url.path,
                                          arguments: ["run.sh", "attabench", reportPipe.path],
                                          delegate: Delegate(self), on: delegateQueue)
        self.process.launch()
        if !input.isEmpty {
            self.process.sendToStandardInput(input)
        }
        self.process.closeStandardInput()
    }

    public func stop() {
        guard process.isRunning else { return }
        guard killTimer == nil else { return }
        process.terminate()
        let timer = DispatchSource.makeTimerSource(flags: [], queue: reportQueue)
        timer.setEventHandler { self.process.kill() }
        timer.resume()
        timer.schedule(deadline: .now() + 2.0, leeway: .milliseconds(250))
        killTimer = timer
    }

    private func cleanup() {
        reportChannel.close(flags: [])
        if let timer = killTimer {
            timer.cancel()
            self.killTimer = nil
        }
        try? fm.removeItem(at: self.temporaryFolder)
    }

    private func fail(_ error: String) {
        guard !hasFailed else { return }
        hasFailed = true
        stop()
        delegate.benchmark(self, didFailWithError: error)
    }

    private func processReport(_ data: Data) {
        do {
            let report = try JSONDecoder().decode(BenchmarkIPC.Report.self, from: data)
            switch report {
            case let .list(tasks: tasks):
                delegate.benchmark(self, didReceiveListOfTasks: tasks)
            case let .begin(task: task, size: size):
                delegate.benchmark(self, willMeasureTask: task, atSize: size)
            case let .finish(task: task, size: size, time: time):
                delegate.benchmark(self, didMeasureTask: task, atSize: size, withResult: Time(time))
            }
        }
        catch {
            if let string = String(data: data, encoding: .utf8) {
                fail("Corrupt report received: \(string)")
            }
            else {
                fail("Corrupt report received: \(data)")
            }
        }
    }
}
