// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import BenchmarkResults
import BenchmarkIPC
import GlueKit

class RunOptionsViewModel: NSObject {
    @objc dynamic var iterations: Int = 3 {
        didSet { if iterations != oldValue { didChangeSignal.send() } }
    }
    @objc dynamic var minimumDuration: Double = 0.01 {
        didSet { if minimumDuration != oldValue { didChangeSignal.send() } }
    }
    @objc dynamic var maximumDuration: Double = 10.0 {
        didSet { if maximumDuration != oldValue { didChangeSignal.send() } }
    }

    let didChangeSignal = Signal<Void>()
}

class RunOptionsViewController: NSViewController {
    @objc dynamic var model: Attaresult? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
