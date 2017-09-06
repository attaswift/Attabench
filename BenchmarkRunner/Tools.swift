// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

extension URL {
    func verifyResourceIsReachable() throws {
        guard try self.checkResourceIsReachable() else {
            throw CocoaError.error(.fileNoSuchFile, url: self)
        }
    }

    var isResourceReachable: Bool {
        return (try? self.checkResourceIsReachable()) ?? false
    }
}

extension String {
    init(posixError: Int32) {
        var c = 256
        var p = UnsafeMutablePointer<Int8>.allocate(capacity: c)
        loop: while true {
            switch strerror_r(posixError, p, c) {
            case 0, EINVAL:
                break loop
            case ERANGE:
                p.deallocate(capacity: c)
                c *= 2
                p = .allocate(capacity: c)
            default:
                preconditionFailure("Unexpected return value from strerror_r")
            }
        }
        self = String(cString: p)
        p.deallocate(capacity: c)
    }

    init(signal: Int32) {
        self.init(cString: strsignal(signal))
    }
}

