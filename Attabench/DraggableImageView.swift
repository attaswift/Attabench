//
//  DraggableImageView.swift
//  Attabench
//
//  Created by Károly Lőrentey on 2017-01-21.
//  Copyright © 2017 Károly Lőrentey.
//

import Cocoa
import Quartz

extension NSImage {
    func pngData() -> Data {
        let cgimage = self.cgImage(forProposedRect: nil, context: nil, hints: [.CTM: NSAffineTransform(transform: AffineTransform.init(scale: 4))])!
        let rep = NSBitmapImageRep(cgImage: cgimage)
        rep.size = self.size
        let data = rep.representation(using: .png, properties: [:])
        return data!
    }

    func pdfData() -> Data {
        let document = PDFDocument()
        let page = PDFPage(image: self)!
        document.insert(page, at: 0)
        return document.dataRepresentation()!
    }
}

class DraggableImageView: NSImageView, NSDraggingSource {
    var name: String = "Image"

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard image != nil else { return [] }
        return .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        return true
    }

    func save(_ data: Data, to destination: URL, withExtension pathExtension: String) throws -> String {
        let name = self.name.replacingOccurrences(of: "/", with: "-")
        var filename = name + "." + pathExtension
        var num = 1
        var url = destination.appendingPathComponent(filename)
        while (try? url.checkResourceIsReachable()) == true {
            num += 1
            filename = "\(name) \(num).\(pathExtension)"
            url = destination.appendingPathComponent(filename)
        }
        try data.write(to: url)
        return filename
    }

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        Swift.print("dropDestination: \(dropDestination)")
        guard let image = self.image else { return nil }

        do {
            return try [
                self.save(image.pngData(), to: dropDestination, withExtension: "png"),
                self.save(image.pdfData(), to: dropDestination, withExtension: "pdf")
            ]
        }
        catch {
            return nil
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        session.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self, NSString.self, NSImage.self]) { draggingItem, index, stop in
            Swift.print(draggingItem)
        }
        return
    }

    var downEvent: NSEvent? = nil

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func shouldDelayWindowOrdering(for event: NSEvent) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        self.downEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = self.downEvent else { return }
        guard let image = self.image else { return }

        let iconSize = CGSize(width: 256, height: ceil(256 / image.size.width * image.size.height))

        let start = downEvent.locationInWindow
        let location = event.locationInWindow
        let distance = hypot(location.x - start.x, location.y - start.y)
        if distance < 5 { return }

        let item = NSDraggingItem(pasteboardWriter: image)
        let origin = self.convert(start, from: nil)
        item.draggingFrame = CGRect(origin: CGPoint(x: origin.x - iconSize.width / 2,
                                                    y: origin.y - iconSize.height / 2),
                                    size: iconSize)
        item.imageComponentsProvider = {
            let iconComponent = NSDraggingImageComponent(key: .icon)
            let icon = NSImage(size: iconSize, flipped: false) { bounds in
                image.draw(in: bounds)
                return true
            }
            iconComponent.contents = icon
            iconComponent.frame = CGRect(origin: .zero, size: iconSize)
            return [iconComponent]
        }

        dragPromisedFiles(ofTypes: ["png", "pdf"],
                          from: CGRect(x: start.x - 26, y: start.y - 12, width: 32, height: 32),
                          source: self, slideBack: true, event: downEvent)

        //beginDraggingSession(with: [item], event: downEvent, source: self)
    }
}
