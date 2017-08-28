// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

private struct ErrorStream: TextOutputStream {
    mutating func write(_ string: String) {
        fputs(string, stderr)
    }
}
private var standardErrorStream = ErrorStream()

public func complain(_ things: Any..., separator: String = " ", terminator: String = "\n") {
    let message = things.lazy.map { "\($0)" }.joined(separator: separator)
    print(message, terminator: terminator, to: &standardErrorStream)
}
