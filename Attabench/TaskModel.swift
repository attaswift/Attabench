// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit

class TaskModel: Hashable {
    let name: String
    let checked: BoolVariable = false
    let isRunnable: BoolVariable = false

    init(name: String, checked: Bool) {
        self.name = name
        self.checked.value = checked
    }

    var hashValue: Int {
        return name.hashValue
    }

    static func ==(left: TaskModel, right: TaskModel) -> Bool {
        return left.name == right.name
    }
}
