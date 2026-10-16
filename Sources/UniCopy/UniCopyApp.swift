import AppKit
import Carbon
import ServiceManagement
import UniCopyCore

@main enum UniCopyApp {
    static func main() {
        if CommandLine.arguments.contains("--test-worker") { exit(runWorkerSelfTest()) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private var resultItem: NSMenuItem!
    private var hotkey: GlobalHotkey?
    private let selection = SelectionController()
    private var task: Task<Void,Never>?
    private var worker: OCRWorker?
    private var session: UUID?
    private var preferences: NSWindow?
    private var resultWindow: NSWindow?
    private var resultText: NSTextView?
    private var statusLabel: NSTextField?
    private var permissionLabel: NSTextField?
    private var toast: NSPanel?
    private var toastTimer: Timer?
    private var lastText = ""
    private var pasteboardCount = 0
    private var joinLines = UserDefaults.standard.bool(forKey: "joinLines")
    private var automaticLanguage = UserDefaults.standard.bool(forKey:"automaticLanguage")
    private var correctLanguage = UserDefaults.standard.bool(forKey:"correctLanguage")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.autosaveName = "UniCopy"
        statusItem.button?.image = NSImage(systemSymbolName:"text.viewfinder",accessibilityDescription:"UniCopy")
        statusItem.button?.image?.isTemplate = true; statusItem.button?.toolTip = "UniCopy · Copy text from your screen"
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:""); item.target = self; menu.addItem(item); return item
        }
        captureItem = item("Copy Text from Screen  ⌃⌥C",#selector(capture))
        cancelItem = item("Cancel Current Capture",#selector(cancel)); cancelItem.isHidden = true
        resultItem = item("Show Last Result…",#selector(showLastResult)); resultItem.isEnabled = false
        _ = item("Try Sample Text…",#selector(sample))
        menu.addItem(.separator()); _ = item("Preferences…",#selector(showPreferences))
        menu.addItem(.separator()); _ = item("Quit UniCopy",#selector(quit)); statusItem.menu = menu
        hotkey = GlobalHotkey(key:UInt32(kVK_ANSI_C),signature:0x554E4943)
        hotkey?.action = { [weak self] in self?.capture() }
        selection.completion = { [weak self] selected in
            guard let self, let token = self.session else { return }
            guard let selected else { self.cancel(); return }
            self.setStatus("Recognising text…")
            self.task = Task { [weak self] in
                do {
                    let image = try await ScreenCapture.image(for:selected)
                    guard let self, self.session == token else { return }
                    self.recognize(image,token:token,copy:true)
                } catch {
                    guard let self, self.session == token else { return }
                    self.finish(error:error.localizedDescription)
                }
            }
        }
        if !CGPreflightScreenCaptureAccess() { showPreferences() }
    }
    func applicationWillTerminate(_ notification: Notification) { cancel(); hotkey = nil; lastText = ""; toastTimer?.invalidate(); toast?.close() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPreferences(); return false }
    func applicationDidBecomeActive(_ notification: Notification) { updatePermission() }
    func menuWillOpen(_ menu: NSMenu) { updatePermission() }
    private func setStatus(_ value: String) { statusLabel?.stringValue = value; statusItem.button?.toolTip = "UniCopy · " + value }
    private func setBusy(_ busy: Bool) { captureItem.isEnabled = !busy; cancelItem.isHidden = !busy }
    private func updatePermission() {
        permissionLabel?.stringValue = CGPreflightScreenCaptureAccess() ? "Screen Recording enabled. Capture is ready." : "Screen Recording permission is needed to capture the area you select."
    }
    @objc private func capture() {
        guard session == nil else { return }
        guard CGPreflightScreenCaptureAccess() else { showPreferences(); setStatus("Enable Screen Recording to capture text."); return }
        pasteboardCount = NSPasteboard.general.changeCount
        session = UUID(); setBusy(true); setStatus("Drag over text. Press Esc to cancel.")
        preferences?.orderOut(nil); resultWindow?.orderOut(nil)
        selection.start()
    }
    @objc private func cancel() {
        session = nil; selection.dismiss(); task?.cancel(); task = nil; worker?.cancel(); worker = nil
        if statusItem != nil { setBusy(false); setStatus("Ready · ⌃⌥C to copy text") }
    }
    private func recognize(_ image: CGImage,token: UUID,copy: Bool) {
        let worker = OCRWorker(); self.worker = worker
        worker.recognize(image:image,correctLanguage:correctLanguage,automaticLanguage:automaticLanguage) { [weak self] result in
            guard let self, self.session == token else { return }
            self.worker = nil; self.task = nil; self.session = nil; self.setBusy(false)
            if let error = result.error { self.finish(error:error); return }
            guard !result.text.isEmpty else { self.setStatus("No text found. Your clipboard is unchanged."); self.showMessage("No text found",detail:"Try a smaller area with larger or clearer text."); return }
            self.lastText = self.joinLines ? result.text.split(whereSeparator:\.isNewline).joined(separator:" ") : result.text
            self.resultItem.isEnabled = true
            if copy && NSPasteboard.general.changeCount == self.pasteboardCount {
                self.writeClipboard(self.lastText); self.setStatus("Copied \(self.lastText.count) characters · ⌃⌥C for another capture")
                self.showCopiedToast()
            } else {
                self.setStatus(copy ? "Text is ready. Your newer clipboard content was preserved." : "Sample recognised. Choose Copy to try it.")
                self.showResult(title:copy ? "Text Ready · Clipboard Preserved" : "Sample Text")
            }
        }
    }
    private func finish(error: String) {
        session = nil; task = nil; worker = nil; setBusy(false); setStatus(error)
        showMessage("Couldn’t capture text",detail:error)
    }
    private func showMessage(_ title: String,detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
    @objc private func sample() {
        guard session == nil else { return }
        let image = NSImage(size:CGSize(width:1100,height:360)); image.lockFocus()
        NSColor.white.setFill(); CGRect(x:0,y:0,width:1100,height:360).fill()
        let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:44),.foregroundColor:NSColor.black]
        ("Copy words, not screenshots." as NSString).draw(at:CGPoint(x:55,y:235),withAttributes:attrs)
        ("UniCopy keeps recognition on your Mac." as NSString).draw(at:CGPoint(x:55,y:150),withAttributes:attrs)
        ("Invoice 1042 — Total 123.45" as NSString).draw(at:CGPoint(x:55,y:65),withAttributes:attrs)
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
        let token = UUID(); session = token; setBusy(true); setStatus("Recognising sample text…")
        recognize(cgImage,token:token,copy:false)
    }
    private func showCopiedToast() {
        toastTimer?.invalidate(); toast?.close()
        let panel = NSPanel(contentRect:CGRect(x:0,y:0,width:280,height:64),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.level = .floating; panel.ignoresMouseEvents = true
        let background = NSVisualEffectView(frame:panel.contentView!.bounds); background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 14; background.layer?.masksToBounds = true
        let label = NSTextField(labelWithString:"✓  Copied \(lastText.count) characters")
        label.font = .systemFont(ofSize:14,weight:.medium); label.alignment = .center; label.frame = CGRect(x:10,y:23,width:260,height:20)
        background.addSubview(label); panel.contentView = background
        if let screen = NSScreen.screens.first(where:{$0.frame.contains(NSEvent.mouseLocation)}) {
            panel.setFrameOrigin(CGPoint(x:screen.visibleFrame.midX-140,y:screen.visibleFrame.minY+45))
        } else { panel.center() }
        toast = panel; panel.orderFrontRegardless()
        toastTimer = Timer.scheduledTimer(withTimeInterval:2,repeats:false) { [weak self] _ in self?.toast?.close(); self?.toast = nil; self?.toastTimer = nil }
    }
    @objc private func showLastResult() { showResult(title:"Last Result") }
    @objc private func copyResult() {
        if let resultText { lastText = String(resultText.string.prefix(200_000)) }
        writeClipboard(lastText)
        setStatus("Copied \(lastText.count) characters")
    }
    private func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text,forType:.string)
    }
    private func showResult(title: String) {
        if let window = resultWindow { window.title = title; resultText?.string = lastText; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let view = NSView(frame:CGRect(x:0,y:0,width:520,height:360))
        let scroll = NSScrollView(frame:CGRect(x:20,y:65,width:480,height:275)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let text = NSTextView(frame:scroll.bounds); text.isEditable = true; text.font = .systemFont(ofSize:15)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
        text.string = lastText; text.setAccessibilityLabel("Recognised text"); scroll.documentView = text; view.addSubview(scroll)
        let copy = NSButton(title:"Copy Text",target:self,action:#selector(copyResult)); copy.frame = CGRect(x:390,y:18,width:110,height:30); copy.bezelStyle = .rounded; view.addSubview(copy)
        let note = NSTextField(labelWithString:"Editable · Kept only until UniCopy quits"); note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor; note.frame = CGRect(x:20,y:25,width:310,height:17); view.addSubview(note)
        let window = NSWindow(contentRect:view.frame,styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = title; window.contentView = view; window.isReleasedWhenClosed = false; window.delegate = self
        resultWindow = window; resultText = text; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc private func requestPermission() { _ = CGRequestScreenCaptureAccess(); updatePermission() }
    @objc private func openPrivacy() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    @objc private func changeJoin(_ sender: NSButton) { joinLines = sender.state == .on; UserDefaults.standard.set(joinLines,forKey:"joinLines") }
    @objc private func changeLanguage(_ sender: NSButton) { automaticLanguage = sender.state == .on; UserDefaults.standard.set(automaticLanguage,forKey:"automaticLanguage") }
    @objc private func changeCorrection(_ sender: NSButton) { correctLanguage = sender.state == .on; UserDefaults.standard.set(correctLanguage,forKey:"correctLanguage") }
    @objc private func launchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { showMessage("Couldn’t change Launch at Login",detail:error.localizedDescription) }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func showPreferences() {
        if let preferences { updatePermission(); preferences.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        func label(_ text: String,size:CGFloat,weight:NSFont.Weight = .regular) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString:text); label.font = .systemFont(ofSize:size,weight:weight); return label
        }
        stack.addArrangedSubview(label("UniCopy",size:28,weight:.semibold))
        let intro = label("Copy words from anywhere on your screen.",size:14); intro.textColor = .secondaryLabelColor; stack.addArrangedSubview(intro)
        stack.addArrangedSubview(label("1. Press ⌃⌥C.\n2. Drag over the text you need.\n3. Release to recognise and copy it.",size:15))
        let capture = NSButton(title:"Select Screen Area  ⌃⌥C",target:self,action:#selector(capture)); capture.bezelStyle = .rounded; stack.addArrangedSubview(capture)
        stack.addArrangedSubview(NSButton(title:"Try Sample Text",target:self,action:#selector(sample)))
        let permission = label("",size:12); permission.textColor = .secondaryLabelColor; stack.addArrangedSubview(permission); permissionLabel = permission
        let buttons = NSStackView(views:[NSButton(title:"Enable Screen Recording…",target:self,action:#selector(requestPermission)),NSButton(title:"Open Settings",target:self,action:#selector(openPrivacy))]); buttons.spacing = 8; stack.addArrangedSubview(buttons)
        let join = NSButton(checkboxWithTitle:"Join recognised lines into one paragraph",target:self,action:#selector(changeJoin)); join.state = joinLines ? .on : .off; stack.addArrangedSubview(join)
        let language = NSButton(checkboxWithTitle:"Detect other languages automatically (slower)",target:self,action:#selector(changeLanguage)); language.state = automaticLanguage ? .on : .off; stack.addArrangedSubview(language)
        let correction = NSButton(checkboxWithTitle:"Use language correction for natural text",target:self,action:#selector(changeCorrection)); correction.state = correctLanguage ? .on : .off; stack.addArrangedSubview(correction)
        let login = NSButton(checkboxWithTitle:"Launch at login",target:self,action:#selector(launchAtLogin)); login.state = SMAppService.mainApp.status == .enabled ? .on : .off; stack.addArrangedSubview(login)
        let status = label("Ready. Try the sample without granting screen access.",size:11); status.textColor = .secondaryLabelColor; stack.addArrangedSubview(status); statusLabel = status
        let shortcut = hotkey?.available == true ? "" : "The shortcut is in use by another app. Use the UniCopy menu.\n"
        let note = label(shortcut + "No background recording, screenshots saved to disk, or cloud uploads. The recognition helper exits after each capture.",size:11); note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        let container = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:container.leadingAnchor,constant:26),stack.trailingAnchor.constraint(equalTo:container.trailingAnchor,constant:-26),stack.topAnchor.constraint(equalTo:container.topAnchor,constant:26),stack.bottomAnchor.constraint(equalTo:container.bottomAnchor,constant:-26)])
        let window = NSWindow(contentRect:CGRect(x:0,y:0,width:440,height:590),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "UniCopy"; window.contentView = container; window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); preferences = window; updatePermission(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === preferences { preferences = nil; statusLabel = nil; permissionLabel = nil }
        if notification.object as? NSWindow === resultWindow { resultWindow = nil; resultText = nil }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
