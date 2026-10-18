import AppKit
import ServiceManagement
import UniCopyCore
import Sparkle

@main enum UniCopyApp {
    static func main() {
        if CommandLine.arguments.contains("--test-worker") { exit(runWorkerSelfTest()) }
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let settings = UniCopySettings()
    // Checks the GitHub-hosted appcast (SUFeedURL in Info.plist) for new releases.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var statusItem: NSStatusItem!
    private var captureItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private var resultItem: NSMenuItem!
    private var hotkey: GlobalHotkey?
    private var shortcutWarning: String?
    private var recordingShortcut = false
    private let selection = SelectionController()
    private var task: Task<Void,Never>?
    private var worker: OCRWorker?
    private var session: UUID?
    private var settingsWindow: SettingsWindowController?
    private var resultWindow: NSWindow?
    private var resultText: NSTextView?
    private var toast: NSPanel?
    private var toastTimer: Timer?
    private var lastText = ""
    private var pasteboardCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.autosaveName = "UniCopy"
        statusItem.button?.image = NSImage(systemSymbolName:"text.viewfinder",accessibilityDescription:"UniCopy")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        captureItem = menuItem("Copy Text from Screen",#selector(capture)); menu.addItem(captureItem)
        cancelItem = menuItem("Cancel Current Capture",#selector(cancel)); cancelItem.isHidden = true; menu.addItem(cancelItem)
        resultItem = menuItem("Show Last Result…",#selector(showLastResult)); resultItem.isEnabled = false; menu.addItem(resultItem)
        menu.addItem(menuItem("Try Sample Text…",#selector(sample)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…",#selector(showSettings),key:","))
        menu.addItem(menuItem("Check for Updates…",#selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit UniCopy",#selector(quit),key:"q"))
        statusItem.menu = menu
        NSApp.mainMenu = mainMenu()
        registerShortcut()
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
        setStatus("Ready")
        if !CGPreflightScreenCaptureAccess() { showSettings() }
    }
    func applicationWillTerminate(_ notification: Notification) { cancel(); hotkey = nil; lastText = ""; toastTimer?.invalidate(); toast?.close() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return false }
    func applicationDidBecomeActive(_ notification: Notification) { syncControls() }
    func applicationDidResignActive(_ notification: Notification) { settingsWindow?.cancelRecording() }
    func menuWillOpen(_ menu: NSMenu) { syncControls() }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title:title,action:action,keyEquivalent:key); item.target = self; return item
    }
    // Shown in the menu bar only while a UniCopy window is open and the app is in the Dock.
    private func mainMenu() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(title: "UniCopy")
        app.addItem(menuItem("Settings…", #selector(showSettings), key: ","))
        app.addItem(menuItem("Check for Updates…", #selector(checkForUpdates)))
        app.addItem(.separator())
        app.addItem(menuItem("Quit UniCopy", #selector(quit), key: "q"))
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo); edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        for submenu in [app, edit, window] {
            let entry = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: ""); entry.submenu = submenu; main.addItem(entry)
        }
        return main
    }
    // The Dock icon and app menu appear only while Settings or a result is open.
    private func updateDockPresence() {
        let visible = settingsWindow?.window?.isVisible == true || resultWindow?.isVisible == true
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    private func registerShortcut() {
        hotkey = nil; shortcutWarning = nil
        guard !recordingShortcut, let shortcut = settings.shortcut else { syncControls(); return }
        let hotkey = GlobalHotkey(shortcut: shortcut)
        hotkey.action = { [weak self] in self?.capture() }
        if hotkey.available { self.hotkey = hotkey }
        else { shortcutWarning = "\(shortcut.display) is in use by another app. Choose another shortcut, or use the menu bar item." }
        syncControls()
    }
    private func changeShortcut(to shortcut: KeyboardShortcut?) -> String? {
        if let shortcut {
            guard shortcut.isValid else { return "Include Control, Option or Command with your key." }
            if let previous = settings.shortcut, previous.matches(shortcut), hotkey?.available == true { return nil }
            hotkey = nil
            let replacement = GlobalHotkey(shortcut: shortcut)
            guard replacement.available else { registerShortcut(); return "That shortcut is already in use. Your previous shortcut was kept." }
            settings.shortcut = shortcut
            replacement.action = { [weak self] in self?.capture() }
            if !recordingShortcut { hotkey = replacement }
        } else { settings.shortcut = nil; hotkey = nil }
        shortcutWarning = nil
        syncControls()
        return nil
    }
    private func syncControls() {
        if let shortcut = settings.shortcut, shortcut.keyName.count == 1 {
            captureItem?.keyEquivalent = shortcut.keyName.lowercased()
            var mask: NSEvent.ModifierFlags = []
            for (bit, flag) in [(KeyboardShortcut.control, NSEvent.ModifierFlags.control), (KeyboardShortcut.option, .option), (KeyboardShortcut.shift, .shift), (KeyboardShortcut.command, .command)] where shortcut.modifiers & bit != 0 { mask.insert(flag) }
            captureItem?.keyEquivalentModifierMask = mask
        } else { captureItem?.keyEquivalent = "" }
        settingsWindow?.updateState(screenAccess: CGPreflightScreenCaptureAccess(), busy: session != nil, shortcutWarning: shortcutWarning)
    }
    private func setStatus(_ value: String) {
        let hint = settings.shortcut.map { " · \($0.display) to copy text" } ?? ""
        statusItem.button?.toolTip = "UniCopy · " + value + (value == "Ready" ? hint : "")
    }
    private func setBusy(_ busy: Bool) { captureItem.isEnabled = !busy; cancelItem.isHidden = !busy; syncControls() }

    @objc private func capture() {
        guard session == nil else { return }
        guard CGPreflightScreenCaptureAccess() else { showSettings(); setStatus("Allow Screen Recording to capture text."); return }
        pasteboardCount = NSPasteboard.general.changeCount
        session = UUID(); setBusy(true); setStatus("Drag over text. Press Esc to cancel.")
        settingsWindow?.window?.orderOut(nil); resultWindow?.orderOut(nil); updateDockPresence()
        selection.start()
    }
    @objc private func cancel() {
        session = nil; selection.dismiss(); task?.cancel(); task = nil; worker?.cancel(); worker = nil
        if statusItem != nil { setBusy(false); setStatus("Ready") }
    }
    private func recognize(_ image: CGImage,token: UUID,copy: Bool) {
        let worker = OCRWorker(); self.worker = worker
        worker.recognize(image:image,correctLanguage:settings.correctLanguage,automaticLanguage:settings.automaticLanguage) { [weak self] result in
            guard let self, self.session == token else { return }
            self.worker = nil; self.task = nil; self.session = nil; self.setBusy(false)
            if let error = result.error { self.finish(error:error); return }
            guard !result.text.isEmpty else { self.setStatus("No text found. Your clipboard is unchanged."); self.showMessage("No text found",detail:"Try a smaller area with larger or clearer text."); return }
            self.lastText = self.settings.output(result.text)
            self.resultItem.isEnabled = true
            if copy && NSPasteboard.general.changeCount == self.pasteboardCount {
                self.writeClipboard(self.lastText); self.setStatus("Copied \(self.lastText.count) characters")
                self.showCopiedToast()
            } else {
                self.setStatus(copy ? "Text is ready. Your newer clipboard content was preserved." : "Sample recognised.")
                self.showResult(title:copy ? "Text Ready · Clipboard Preserved" : "Sample Text")
            }
        }
    }
    private func finish(error: String) {
        session = nil; task = nil; worker = nil; setBusy(false); setStatus(error)
        showMessage("Couldn’t capture text",detail:error)
    }
    private func showMessage(_ title: String,detail: String) {
        NSApp.activate(ignoringOtherApps:true)
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
        resultWindow?.close()
        showCopiedToast()
    }
    private func writeClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text,forType:.string)
    }
    private func showResult(title: String) {
        defer { updateDockPresence(); NSApp.activate(ignoringOtherApps:true) }
        if let window = resultWindow { window.title = title; resultText?.string = lastText; window.makeKeyAndOrderFront(nil); return }
        let view = NSView(frame:CGRect(x:0,y:0,width:520,height:360))
        let scroll = NSScrollView(frame:CGRect(x:20,y:65,width:480,height:275)); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(frame:scroll.bounds); text.isEditable = true; text.font = .systemFont(ofSize:15)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true; text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 6, height: 8)
        text.string = lastText; text.setAccessibilityLabel("Recognised text"); scroll.documentView = text; view.addSubview(scroll)
        let copy = NSButton(title:"Copy Text",target:self,action:#selector(copyResult)); copy.frame = CGRect(x:390,y:18,width:110,height:30); copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r"; copy.autoresizingMask = [.minXMargin]; view.addSubview(copy)
        let note = NSTextField(labelWithString:"Editable · Kept only until UniCopy quits"); note.font = .systemFont(ofSize:11); note.textColor = .secondaryLabelColor; note.frame = CGRect(x:20,y:25,width:310,height:17); view.addSubview(note)
        let window = NSWindow(contentRect:view.frame,styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title = title; window.contentView = view; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentMinSize = NSSize(width: 360, height: 240)
        resultWindow = window; resultText = text; window.center(); window.makeKeyAndOrderFront(nil)
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(settings: settings, updater: updater.updater)
            controller.onCapture = { [weak self] in self?.capture() }
            controller.onSample = { [weak self] in self?.sample() }
            controller.onRequestAccess = { [weak self] in _ = CGRequestScreenCaptureAccess(); self?.syncControls() }
            controller.onShortcutChange = { [weak self] in self?.changeShortcut(to: $0) }
            controller.onRecordingChange = { [weak self] value in self?.recordingShortcut = value; self?.registerShortcut() }
            controller.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
            controller.onClose = { [weak self] in
                self?.settingsWindow = nil
                DispatchQueue.main.async { self?.updateDockPresence() }
            }
            settingsWindow = controller
        }
        updateDockPresence()
        syncControls(); settingsWindow?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func checkForUpdates() {
        // A menu bar app isn't active by default; bring Sparkle's window forward.
        NSApp.activate(ignoringOtherApps: true); updater.checkForUpdates(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === resultWindow {
            resultWindow = nil; resultText = nil
            DispatchQueue.main.async { self.updateDockPresence() }
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
