// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Darwin
import BigInt

public struct Timestamp {
    let tick: UInt64

    public init() {
        self.tick = mach_absolute_time()
    }
}

private let timeInfo: mach_timebase_info = {
    var info = mach_timebase_info()
    guard mach_timebase_info(&info) == KERN_SUCCESS else { fatalError("Can't get mach_timebase_info") }
    guard info.denom > 0 else { fatalError("mach_timebase_info.denom == 0") }
    return info
}()

public func -(left: Timestamp, right: Timestamp) -> Time {
    let elapsed = BigInt(left.tick) - BigInt(right.tick)
    return Time(picoseconds: elapsed * 1000 * BigInt(timeInfo.numer) / BigInt(timeInfo.denom))
}
