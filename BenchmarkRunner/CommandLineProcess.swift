// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

public protocol CommandLineDelegate {
    func commandLineProcess(_ process: CommandLineProcess, didPrintToStandardOutput line: String)
    func commandLineProcess(_ process: CommandLineProcess, didPrintToStandardError line: String)
    func commandLineProcess(_ process: CommandLineProcess, channel: CommandLineProcess.Channel, didFailWithError error: Int32)
    func commandLineProcess(_ process: CommandLineProcess, didExitWithState state: CommandLineProcess.ExitState)
}

public class CommandLineProcess {
    public enum Channel {
        case input
        case output
        case error
    }

    public enum ExitState: Equatable {
        case exit(Int32)
        case uncaughtSignal(Int32)

        public static func ==(left: ExitState, right: ExitState) -> Bool {
            switch (left, right) {
            case let (.exit(l), .exit(r)): return l == r
            case let (.uncaughtSignal(l), .uncaughtSignal(r)): return l == r
            default: return false
            }
        }
    }

    public let delegate: CommandLineDelegate // Note this isn't weak
    public let delegateQueue: DispatchQueue

    private let inputOutputQueue = DispatchQueue(label: "org.attaswift.CommandLineProcess.io")
    private let process: Process
    private let stdinChannel: DispatchIO
    private let stdoutChannel: DispatchIO
    private let stderrChannel: DispatchIO

    public init(launchPath: String, workingDirectory: String, arguments: [String], delegate: CommandLineDelegate, on delegateQueue: DispatchQueue) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue

        // Create pipes for stdin/out/err.
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Create task.
        process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        process.currentDirectoryPath = workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set up dispatch channels.
        stdinChannel = DispatchIO(type: .stream,
                                  fileDescriptor: stdinPipe.fileHandleForWriting.fileDescriptor,
                                  queue: inputOutputQueue,
                                  cleanupHandler: { result in stdinPipe.fileHandleForWriting.closeFile() })

        stdoutChannel = DispatchIO(type: .stream,
                                   fileDescriptor: stdoutPipe.fileHandleForReading.fileDescriptor,
                                   queue: inputOutputQueue,
                                   cleanupHandler: { result in stdoutPipe.fileHandleForReading.closeFile() })
        stdoutChannel.setLimit(lowWater: 1)

        stderrChannel = DispatchIO(type: .stream,
                                   fileDescriptor: stderrPipe.fileHandleForReading.fileDescriptor,
                                   queue: inputOutputQueue,
                                   cleanupHandler: { result in stderrPipe.fileHandleForReading.closeFile() })
        stderrChannel.setLimit(lowWater: 1)

        process.terminationHandler = { process in
            self.delegateQueue.async {
                self.stdinChannel.close(flags: .stop)
                self.stdoutChannel.close(flags: .stop)
                self.stderrChannel.close(flags: .stop)
                switch process.terminationReason {
                case .exit:
                    self.delegate.commandLineProcess(self, didExitWithState: .exit(process.terminationStatus))
                case .uncaughtSignal:
                    self.delegate.commandLineProcess(self, didExitWithState: .uncaughtSignal(process.terminationStatus))
                }
            }
        }
    }

    var isRunning: Bool { return process.isRunning }

    public func launch() {
        // Start reading output channels.
        stdoutChannel.readUTF8Lines(on: delegateQueue) { chunk in
            switch chunk {
            case .record(let line): self.delegate.commandLineProcess(self, didPrintToStandardOutput: line)
            case .endOfFile: self.delegate.commandLineProcess(self, channel: .output, didFailWithError: 0)
            case .error(let err): self.delegate.commandLineProcess(self, channel: .output, didFailWithError: err)
            }
        }
        stderrChannel.readUTF8Lines(on: delegateQueue) { chunk in
            switch chunk {
            case .record(let line): self.delegate.commandLineProcess(self, didPrintToStandardError: line)
            case .endOfFile: self.delegate.commandLineProcess(self, channel: .error, didFailWithError: 0)
            case .error(let err): self.delegate.commandLineProcess(self, channel: .error, didFailWithError: err)
            }
        }
        process.launch()
    }

    public func sendToStandardInput(_ data: Data) {
        stdinChannel.write(offset: 0, data: DispatchData(data), queue: delegateQueue) { [weak self] done, data, err in
            guard let this = self else { return }
            if done {
                this.delegate.commandLineProcess(this, channel: .input, didFailWithError: err)
            }
        }
    }

    public func closeStandardInput() {
        stdinChannel.close(flags: [])
    }

    public func terminate() {
        self.process.terminate()
    }

    public func kill() {
        guard self.process.isRunning else { return }
        Darwin.kill(self.process.processIdentifier, SIGKILL)
    }
}
