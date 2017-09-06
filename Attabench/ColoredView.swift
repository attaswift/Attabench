// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa

@IBDesignable
class ColoredView: NSView {


    @IBInspectable
    var backgroundColor: NSColor = .clear {
        didSet {
            setNeedsDisplay(self.bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        self.backgroundColor.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}
