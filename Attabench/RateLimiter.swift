// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

class RateLimiter: NSObject {
    let maxDelay: TimeInterval
    let action: () -> Void
    private var scheduled = false
    private var next = Date.distantPast

    init(maxDelay: TimeInterval, action: @escaping () -> Void) {
        self.maxDelay = maxDelay
        self.action = action
    }

    private func cancel() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(RateLimiter.now), object: nil)
        scheduled = false
    }

    @objc func now() {
        cancel()
        action()
        next = Date(timeIntervalSinceNow: maxDelay)
    }

    func later() {
        if scheduled { return }
        let now = Date()
        if next < now {
            self.now()
        }
        else {
            self.perform(#selector(RateLimiter.now), with: nil, afterDelay: next.timeIntervalSince(now))
            scheduled = true
        }
    }

}
