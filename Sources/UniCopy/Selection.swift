import AppKit
import UniCopyCore

struct CaptureSelection {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let rect: CGRect
    let scale: CGFloat
}

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionController {
    private var panels: [SelectionPanel] = []
    var completion: ((CaptureSelection?) -> Void)?
    func start() {
        dismiss()
        for screen in NSScreen.screens {
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            panel.hidesOnDeactivate = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onSelection = { [weak self] rect in
                guard let self else { return }
                let result = rect.map { CaptureSelection(displayID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value,
                    screenFrame: screen.frame, rect: $0, scale: screen.backingScaleFactor) }
                self.dismiss(); self.completion?(result)
            }
            panel.contentView = view; panels.append(panel); panel.orderFrontRegardless()
            if screen.frame.contains(NSEvent.mouseLocation) { panel.makeKey(); panel.makeFirstResponder(view) }
        }
    }
    func dismiss() {
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
    }
}

final class SelectionView: NSView {
    var onSelection: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow,from: nil); selection = nil; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CaptureGeometry.selection(from: start, to: convert(event.locationInWindow,from: nil), bounds: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { onSelection?(nil); return }
        onSelection?(CaptureGeometry.selection(from: start,to: convert(event.locationInWindow,from:nil),bounds:bounds))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSelection?(nil) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.16).setFill(); bounds.fill()
        if let selection {
            NSGraphicsContext.current?.cgContext.clear(selection)
            NSColor.white.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 1.5; path.stroke()
        }
        let hint = "Drag over text · Release to capture · Esc to cancel"
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:14,weight:.medium), .foregroundColor:NSColor.white]
        let size = (hint as NSString).size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width-size.width-30)/2,y: bounds.height-85,width:size.width+30,height:38)
        NSColor(calibratedWhite:0.12,alpha:0.9).setFill(); NSBezierPath(roundedRect:box,xRadius:12,yRadius:12).fill()
        (hint as NSString).draw(at:CGPoint(x:box.minX+15,y:box.minY+10),withAttributes:attributes)
    }
}
