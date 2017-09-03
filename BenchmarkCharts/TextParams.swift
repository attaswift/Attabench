// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/lorentey/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

struct TextParams {
    let font: NSFont
    let color: NSColor

    var attributes: [NSAttributedStringKey: Any] {
        return [.foregroundColor: color,
                .font: font]
    }
}
