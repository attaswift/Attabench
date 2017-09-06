// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

class RateLimiter: NSObject {
    var maxDelay: TimeInterval {
        didSet { now() }
    }
    let action: () -> Void
    private var scheduled = false
    private var async = false
    private var performing = false
    private var next = Date.distantPast

    init(maxDelay: TimeInterval, async: Bool = false, action: @escaping () -> Void) {
        self.maxDelay = maxDelay
        self.async = async
        self.action = action
    }

    private func cancel() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(RateLimiter.now), object: nil)
        scheduled = false
    }

    private func _now() {
        self.action()
        self.next = Date(timeIntervalSinceNow: self.maxDelay)
    }

    @objc func now() {
        if performing { return }
        cancel()
        if async {
            performing = true
            DispatchQueue.main.async {
                self._now()
                self.performing = false
            }
        }
        else {
            _now()
        }
    }

    func later() {
        if scheduled { return }
        if performing { return }
        let now = Date()
        if next < now {
            self.now()
        }
        else {
            self.perform(#selector(RateLimiter.now), with: nil, afterDelay: next.timeIntervalSince(now))
            scheduled = true
        }
    }

    func nowIfNeeded() {
        if scheduled { now() }
    }
}
