// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Foundation

struct Gridline {
    enum Kind {
        case major
        case minor
    }
    let kind: Kind
    let position: CGFloat
    let label: String?

    init(_ kind: Kind, position: CGFloat, label: String? = nil) {
        self.kind = kind
        self.position = position
        self.label = label
    }
}
