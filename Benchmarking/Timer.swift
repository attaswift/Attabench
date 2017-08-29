// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation
import QuartzCore

public class BenchmarkTimer {
    var elapsedTime: TimeInterval? = nil

    @inline(never)
    static func measure(_ body: (BenchmarkTimer) -> Void) -> TimeInterval {
        let timer = BenchmarkTimer()
        let start = CACurrentMediaTime()
        body(timer)
        let end = CACurrentMediaTime()
        return timer.elapsedTime ?? (end - start)
    }

    @inline(never)
    public func measure(_ body: () -> ()) {
        let start = CACurrentMediaTime()
        body()
        let end = CACurrentMediaTime()
        elapsedTime = end - start
    }
}

