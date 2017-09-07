// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

extension BenchmarkTheme {
    public struct TextParams {
        var font: NSFont
        var color: NSColor

        var attributes: [NSAttributedStringKey: Any] {
            return [.foregroundColor: color,
                    .font: font]
        }

        var fontName: String {
            get {
                return font.fontName
            }
            set {
                guard let font = NSFont(name: newValue, size: font.pointSize) else {
                    preconditionFailure("Font '\(newValue)' not found")
                }
                self.font = font
            }
        }
    }
}
