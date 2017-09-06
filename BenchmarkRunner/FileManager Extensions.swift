// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

extension FileManager {
    var userTemporaryDirectory: URL {
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    func createTemporaryFolder(_ template: String) throws -> URL {
        let tempFilename = userTemporaryDirectory.appendingPathComponent(template)
        let p = tempFilename.withUnsafeFileSystemRepresentation { p in strdup(p) }
        defer { free(p) }
        guard let q = mkdtemp(p) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        return URL(fileURLWithPath: self.string(withFileSystemRepresentation: q, length: strlen(p)),
                   isDirectory: true)
    }

    func createFIFO(at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { p in
            guard -1 != mkfifo(p, S_IWUSR | S_IRUSR) else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
            }
        }
    }
}
