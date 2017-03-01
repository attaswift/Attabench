//
//  ColoredView.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-23.
//  Copyright © 2017 Károly Lőrentey.
//

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
        NSRectFill(dirtyRect)
        super.draw(dirtyRect)
    }
}
