// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

extension DispatchData {
    init(_ data: Data) {
        // Data and DispatchData are toll-free bridged in Objective-C, but I don't think we can exploit this in Swift
        self.init(bytes: UnsafeRawBufferPointer(start: (data as NSData).bytes, count: data.count))
    }
}

extension DispatchIO {
    enum Chunk<Payload> {
        case record(Payload)
        case endOfFile
        case error(Int32)
    }

    /// Read variable-length records delimited by `delimiter`.
    func readRecords(on queue: DispatchQueue, delimitedBy delimiter: UInt8, handler: @escaping (Chunk<Data>) -> Void) {
        // FIXME This code is horrible
        var pending = Data()
        self.read(offset: 0, length: Int(bitPattern: SIZE_MAX), queue: queue) { done, data, err in
            if var data = data {
                // Find record boundaries and send complete records to handler (including delimiter).
                while let index = data.index(of: delimiter) {
                    pending.append(contentsOf: data.subdata(in: 0 ..< index + 1))
                    handler(.record(pending))
                    pending = Data()
                    data = data.subdata(in: index + 1 ..< data.count)
                }
                pending.append(contentsOf: data)
            }
            if done {
                // Send last partial record.
                if !pending.isEmpty {
                    handler(.record(pending))
                    pending.removeAll()
                }
                handler(err != 0 ? .error(err) : .endOfFile)
            }
        }
    }

    func readUTF8Lines(on queue: DispatchQueue, handler: @escaping (Chunk<String>) -> Void) {
        self.readRecords(on: queue, delimitedBy: 0x0A) { chunk in
            switch chunk {
            case .record(let data):
                if let line = String(data: data, encoding: .utf8) {
                    // FIXME report decoding errors, don't just ignore them
                    handler(.record(line))
                }
            case .endOfFile:
                handler(.endOfFile)
            case .error(let err):
                handler(.error(err))
            }
        }
    }
}
