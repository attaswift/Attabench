// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import GlueKit

class TaskModel: Hashable {
    let name: StringVariable = ""
    let checked: BoolVariable = false

    init(name: String, checked: Bool) {
        self.name.value = name
        self.checked.value = checked
    }

    var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }

    static func ==(left: TaskModel, right: TaskModel) -> Bool {
        return left === right
    }
}
