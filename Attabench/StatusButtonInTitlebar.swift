//
//  StatusButtonInTitlebar.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-23.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa

class StatusButtonInTitlebar: NSButton {

    override var isEnabled: Bool {
        get {
            return true
        }
        set {
            // Nope
        }
    }

    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
    }

    override func mouseDragged(with event: NSEvent) {
    }

    override func mouseUp(with event: NSEvent) {
    }
}

class StatusButtonCell: NSButtonCell {
    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let title = title.mutableCopy() as! NSMutableAttributedString
        let color = controlView.window?.isMainWindow == true
            ? NSColor(white: 0.2, alpha: 1)
            : NSColor(white: 0.6, alpha: 1)
        title.setAttributes([NSForegroundColorAttributeName: color], range: NSRange(0 ..< title.length))
        let bounds = title.boundingRect(with: frame.size, options: [])
        let frame = CGRect(x: floor(frame.midX - bounds.width / 2),
                           y: floor(frame.midY - bounds.height / 2 - (self.font?.descender ?? 0) / 2),
                           width: ceil(bounds.width),
                           height: ceil(bounds.height))
        title.draw(in: frame)
        return frame
    }
}
