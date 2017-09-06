// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

class StatusLabel: NSTextField {
    private var _status: String = ""
    private lazy var refreshStatus = RateLimiter(maxDelay: 0.1) { [unowned self] in
        self.stringValue = self._status
    }

    var refreshRate: TimeInterval {
        get { return refreshStatus.maxDelay }
        set { refreshStatus.maxDelay = newValue }
    }

    // Rate-limited status setter. Helpful if you need to update status frequently without consuming too much CPU.
    var lazyStatus: String {
        get {
            return _status
        }
        set {
            _status = newValue
            refreshStatus.later()
        }
    }

    // Update status text immediately.
    var immediateStatus: String {
        get {
            return _status
        }
        set {
            _status = newValue
            refreshStatus.now()
        }
    }
}

