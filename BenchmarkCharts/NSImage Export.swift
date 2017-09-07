// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import Quartz

extension NSImage {
    public func pngData(scale: Int = 4) -> Data {
        let cgimage = self.cgImage(forProposedRect: nil, context: nil, hints: [.CTM: NSAffineTransform(transform: AffineTransform.init(scale: CGFloat(scale)))])!
        let rep = NSBitmapImageRep(cgImage: cgimage)
        rep.size = self.size
        let data = rep.representation(using: .png, properties: [:])
        return data!
    }

    public func pdfData() -> Data {
        let document = PDFDocument()
        let page = PDFPage(image: self)!
        document.insert(page, at: 0)
        return document.dataRepresentation()!
    }
}
