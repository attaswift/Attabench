// Copyright © 2017 Károly Lőrentey.
// This file is part of Attabench: https://github.com/attaswift/Attabench
// For licensing information, see the file LICENSE.md in the Git repository above.

import Cocoa
import BenchmarkCharts

extension ChartView: NSDraggingSource, NSPasteboardWriting, NSFilePromiseProviderDelegate {
    var imageFileBasename: String {
        guard let chart = self.chart else { return documentBasename }
        let taskString = chart.tasks.count == 1
            ? chart.tasks[0]
            : "\(chart.tasks.count) Tasks"
        return "\(documentBasename) - \(taskString)"
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        guard image != nil else { return [] }
        return .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        return true
    }

    func save(_ data: Data, to destination: URL, withExtension pathExtension: String) throws -> String {
        let name = self.documentBasename.replacingOccurrences(of: "/", with: "-")
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

        let iconProvider: () -> [NSDraggingImageComponent] = {
            let iconComponent = NSDraggingImageComponent(key: .icon)
            let icon = NSImage(size: iconSize, flipped: false) { bounds in
                image.draw(in: bounds)
                return true
            }
            iconComponent.contents = icon
            iconComponent.frame = CGRect(origin: .zero, size: iconSize)
            return [iconComponent]
        }

        let filePromiseProvider = NSFilePromiseProvider(fileType: UTI.png, delegate: self)
        filePromiseProvider.userInfo = image

        let imageItem = NSDraggingItem(pasteboardWriter: filePromiseProvider)
        let origin = self.convert(start, from: nil)
        imageItem.draggingFrame = CGRect(origin: CGPoint(x: origin.x - iconSize.width / 2,
                                                         y: origin.y - iconSize.height / 2),
                                         size: iconSize)
        imageItem.imageComponentsProvider = iconProvider

//        dragPromisedFiles(ofTypes: ["png", "pdf"],
//                          from: CGRect(x: start.x - 26, y: start.y - 12, width: 32, height: 32),
//                          source: self, slideBack: true, event: downEvent)
//
        beginDraggingSession(with: [imageItem], event: downEvent, source: self)
    }

    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                    fileNameForType fileType: String) -> String {
        let ext = NSWorkspace.shared.preferredFilenameExtension(forType: fileType)!
        return "\(imageFileBasename).\(ext)"
    }

    public func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider,
                                    writePromiseTo url: URL,
                                    completionHandler: @escaping (Error?) -> Void) {
        do {
            let image = filePromiseProvider.userInfo as! NSImage
            switch filePromiseProvider.fileType {
            case UTI.png:
                try image.pngData().write(to: url)
            case UTI.pdf:
                try image.pdfData().write(to: url)
            default:
                throw CocoaError(CocoaError.Code.featureUnsupported)
            }
            completionHandler(nil)
        }
        catch {
            completionHandler(error)
        }
    }


    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        return [.png, .pdf]
    }

    public func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        return .promised
    }

    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .png, .fileContentsType(forPathExtension: "png"):
            return image?.pngData()
        case .pdf, .fileContentsType(forPathExtension: "pdf"):
            return image?.pdfData()
        case .filePromise:
            return nil
        default:
            print("Unknown pasteboard type \(type)")
            return nil
        }
    }

}
