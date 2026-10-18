import AppKit
import ServiceManagement
import UniCopyCore
import Sparkle

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onCapture: (() -> Void)?
    var onSample: (() -> Void)?
    var onRequestAccess: (() -> Void)?
    var onShortcutChange: ((KeyboardShortcut?) -> String?)?
    var onRecordingChange: ((Bool) -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onClose: (() -> Void)?
    private let settings: UniCopySettings
    private let updater: SPUUpdater
    private let tabs = NSTabView()
    private let navigation = NSTableView()
    private let sections: [(title: String, symbol: String, color: NSColor)] = [
        ("General", "gearshape.fill", .systemGray), ("Recognition", "text.viewfinder", .systemBlue),
        ("Shortcut", "command", .systemTeal)
    ]
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let shortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let generalMessage = NSTextField(wrappingLabelWithString: "")
    private let captureButton = NSButton(title: "Select Area…", target: nil, action: nil)
    private var recorder: ShortcutRecorder!
    // Width of a row inside a card; cards add 14pt padding on each side.
    private let width: CGFloat = 512
    private static let cardColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.04)
    }

    init(settings: UniCopySettings, updater: SPUUpdater) {
        self.settings = settings; self.updater = updater
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "UniCopy Settings"; window.isReleasedWhenClosed = false
        // An empty toolbar puts the page title beside the sidebar, as in System Settings.
        window.toolbar = NSToolbar(identifier: "UniCopySettings")
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 760, height: 440)
        super.init(window: window)
        window.delegate = self

        let sidebar = NSViewController(); sidebar.view = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        navigation.addTableColumn(column); navigation.headerView = nil
        navigation.style = .sourceList; navigation.rowHeight = 32
        navigation.intercellSpacing = NSSize(width: 0, height: 2)
        navigation.backgroundColor = .clear
        navigation.allowsEmptySelection = false; navigation.allowsMultipleSelection = false
        navigation.focusRingType = .none; navigation.delegate = self; navigation.dataSource = self
        navigation.setAccessibilityLabel("Settings sections")
        let navigationScroll = NSScrollView()
        navigationScroll.drawsBackground = false; navigationScroll.documentView = navigation
        navigationScroll.automaticallyAdjustsContentInsets = false
        navigationScroll.translatesAutoresizingMaskIntoConstraints = false; sidebar.view.addSubview(navigationScroll)
        NSLayoutConstraint.activate([
            navigationScroll.topAnchor.constraint(equalTo: sidebar.view.safeAreaLayoutGuide.topAnchor, constant: 6),
            navigationScroll.leadingAnchor.constraint(equalTo: sidebar.view.leadingAnchor),
            navigationScroll.trailingAnchor.constraint(equalTo: sidebar.view.trailingAnchor),
            navigationScroll.bottomAnchor.constraint(equalTo: sidebar.view.bottomAnchor, constant: -12)
        ])

        tabs.tabViewType = .noTabsNoBorder
        let pages = [general(), recognition(), shortcut()]
        for (index, content) in pages.enumerated() {
            let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
            let document = SettingsDocumentView()
            content.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(content)
            scroll.documentView = document
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                content.widthAnchor.constraint(equalToConstant: width + 28),
                content.centerXAnchor.constraint(equalTo: document.centerXAnchor),
                content.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
                content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
            ])
            let item = NSTabViewItem(identifier: index); item.view = scroll; tabs.addTabViewItem(item)
        }
        let detail = NSViewController(); detail.view = tabs
        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 200; sidebarItem.maximumThickness = 230
        sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.titlebarSeparatorStyle = .none
        split.addSplitViewItem(detailItem)
        window.contentViewController = split
        navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        window.title = sections[max(navigation.selectedRow, 0)].title
        window.setContentSize(NSSize(width: 780, height: 560))
        window.center()
        // Pages taller than the window otherwise open scrolled under the toolbar.
        window.layoutIfNeeded()
        for case let scroll as NSScrollView in tabs.tabViewItems.compactMap(\.view) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: -scroll.contentInsets.top))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateState(screenAccess: Bool, busy: Bool, shortcutWarning: String?) {
        permission.stringValue = screenAccess ? "Screen Recording is allowed. Capture is ready." : "Allow Screen Recording so UniCopy can read the area you select."
        captureButton.isEnabled = !busy
        if let shortcutWarning { showMessage(shortcutWarning, in: shortcutMessage) }
        recorder.shortcut = settings.shortcut
    }
    func cancelRecording() { recorder.stop() }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }
    func windowWillClose(_ notification: Notification) { cancelRecording(); onClose?() }
    func numberOfRows(in tableView: NSTableView) -> Int { sections.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let badge = NSView(); badge.wantsLayer = true
        badge.layer?.backgroundColor = sections[row].color.cgColor
        badge.layer?.cornerRadius = 6; badge.layer?.cornerCurve = .continuous
        let image = symbol(sections[row].symbol, size: 12); image.contentTintColor = .white
        let text = NSTextField(labelWithString: sections[row].title)
        cell.textField = text
        [badge, image, text].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        badge.addSubview(image); cell.addSubview(badge); cell.addSubview(text)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 22), badge.heightAnchor.constraint(equalToConstant: 22),
            image.centerXAnchor.constraint(equalTo: badge.centerXAnchor), image.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = navigation.selectedRow
        guard sections.indices.contains(index), tabs.numberOfTabViewItems > index else { return }
        cancelRecording(); tabs.selectTabViewItem(at: index); window?.title = sections[index].title
    }

    private func general() -> NSView {
        let stack = page()
        captureButton.target = self; captureButton.action = #selector(capture)
        stack.addArrangedSubview(group("Capture", [
            row(label("Copy text from your screen"), captureButton),
            row(label("Try it without screen access"), NSButton(title: "Try Sample Text", target: self, action: #selector(sample)))
        ], footer: [detail("Press your shortcut, drag over any text, and release. The text is copied to your clipboard.")]))

        styleDetail(permission)
        stack.addArrangedSubview(group("Screen Recording", [
            row(label("Screen access"), NSButton(title: "Allow…", target: self, action: #selector(requestAccess)), NSButton(title: "Open System Settings", target: self, action: #selector(openPrivacy)))
        ], footer: [permission, detail("UniCopy captures only the area you select, when you ask. Nothing is saved to disk or uploaded.")]))

        let login = NSSwitch(); login.target = self; login.action = #selector(changeLogin(_:))
        login.setAccessibilityLabel("Launch UniCopy at login")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        styleDetail(generalMessage)
        stack.addArrangedSubview(group("Startup", [row(label("Launch UniCopy at login"), login)], footer: [generalMessage]))
        showMessage("", in: generalMessage)

        let automatic = NSSwitch(); automatic.target = self; automatic.action = #selector(changeAutomaticUpdates(_:))
        automatic.state = updater.automaticallyChecksForUpdates ? .on : .off
        automatic.setAccessibilityLabel("Check for updates automatically")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        stack.addArrangedSubview(group("Updates", [
            row(label("Check for updates automatically"), automatic),
            row(label("UniCopy \(version)"), NSButton(title: "Check Now", target: self, action: #selector(checkForUpdates)))
        ], footer: [detail("Updates come from UniCopy releases on GitHub.")]))
        return stack
    }
    private func recognition() -> NSView {
        let stack = page()
        stack.addArrangedSubview(group("Text", [
            row(label("Join lines into one paragraph"), toggle(settings.joinLines, "Join lines into one paragraph", #selector(changeJoin(_:)))),
            row(label("Use language correction"), toggle(settings.correctLanguage, "Use language correction", #selector(changeCorrection(_:))))
        ], footer: [detail("Joining lines suits paragraphs; keep it off for lists, tables and code. Hold ⇧ when you release a selection to do the opposite once. Language correction helps natural sentences but can change names and code.")]))
        stack.addArrangedSubview(group("Languages", [
            row(label("Detect other languages automatically"), toggle(settings.automaticLanguage, "Detect other languages automatically", #selector(changeLanguage(_:))))
        ], footer: [detail("By default UniCopy reads your Mac’s preferred languages and English. Automatic detection covers other languages but is slower.")]))
        stack.addArrangedSubview(group("Privacy", [
            row(label("Recognition runs on this Mac"), detail("Apple Vision"))
        ], footer: [detail("Each capture is read by a small helper that exits right after. Only the latest result is kept, until UniCopy quits.")]))
        return stack
    }
    private func shortcut() -> NSView {
        let stack = page()
        recorder = ShortcutRecorder(shortcut: settings.shortcut)
        recorder.onChange = { [weak self] value in self?.onShortcutChange?(value) }
        recorder.onMessage = { [weak self] value in
            guard let self else { return }
            self.showMessage(value, in: self.shortcutMessage)
        }
        recorder.onRecordingChange = { [weak self] value in self?.onRecordingChange?(value) }
        recorder.setAccessibilityLabel("Copy text shortcut")
        let clear = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(clearShortcut))
        clear.isBordered = false; clear.contentTintColor = .tertiaryLabelColor
        clear.setAccessibilityLabel("Clear the copy text shortcut")
        styleDetail(shortcutMessage); shortcutMessage.isHidden = true
        stack.addArrangedSubview(group("Keyboard Shortcut", [row(label("Copy text from screen"), recorder, clear)],
            footer: [detail("Click the shortcut to record. Include Control, Option or Command. Press Escape to cancel or Delete to clear."), shortcutMessage]))
        let restore = row(label("Default shortcut (⌃⌥C)"), NSButton(title: "Restore", target: self, action: #selector(defaultShortcut)))
        stack.addArrangedSubview(group("Defaults", [restore], footer: [detail("If a combination is unavailable, your previous shortcut is kept. The menu bar item always works.")]))
        return stack
    }

    @objc private func capture() { onCapture?() }
    @objc private func sample() { onSample?() }
    @objc private func requestAccess() { onRequestAccess?() }
    @objc private func openPrivacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
    @objc private func changeJoin(_ sender: NSSwitch) { settings.joinLines = sender.state == .on }
    @objc private func changeCorrection(_ sender: NSSwitch) { settings.correctLanguage = sender.state == .on }
    @objc private func changeLanguage(_ sender: NSSwitch) { settings.automaticLanguage = sender.state == .on }
    @objc private func changeAutomaticUpdates(_ sender: NSSwitch) { updater.automaticallyChecksForUpdates = sender.state == .on }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func changeLogin(_ sender: NSSwitch) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            showMessage("", in: generalMessage)
        } catch { showMessage(error.localizedDescription, in: generalMessage) }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    @objc private func clearShortcut() {
        cancelRecording()
        showMessage(onShortcutChange?(nil) ?? "Shortcut cleared.", in: shortcutMessage)
        recorder.shortcut = settings.shortcut
    }
    @objc private func defaultShortcut() {
        cancelRecording()
        showMessage(onShortcutChange?(.defaultCapture) ?? "Default shortcut restored.", in: shortcutMessage)
        recorder.shortcut = settings.shortcut
    }

    private func toggle(_ on: Bool, _ name: String, _ action: Selector) -> NSSwitch {
        let control = NSSwitch(); control.state = on ? .on : .off
        control.target = self; control.action = action; control.setAccessibilityLabel(name)
        return control
    }
    private func vertical(spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing; return stack
    }
    private func row(_ views: NSView...) -> NSStackView {
        let stack = NSStackView(); stack.alignment = .centerY; stack.spacing = 10
        stack.distribution = .fill
        for (index, view) in views.enumerated() {
            stack.addArrangedSubview(view)
            if index == 0 && views.count > 1 {
                let spacer = NSView()
                spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                stack.addArrangedSubview(spacer)
            }
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
        return stack
    }
    private func showMessage(_ text: String, in field: NSTextField) {
        field.stringValue = text; field.isHidden = text.isEmpty
        // Collapse a footer whose only notes are empty messages.
        if let notes = field.superview as? NSStackView { notes.isHidden = notes.arrangedSubviews.allSatisfy(\.isHidden) }
    }
    private func page() -> NSStackView { vertical(spacing: 24) }
    // A bold heading, a rounded card of rows split by hairlines, then optional footnotes.
    private func group(_ title: String, _ rows: [NSView], footer: [NSView] = []) -> NSView {
        let section = vertical(spacing: 8)
        let heading = NSStackView(views: [label(title, weight: .semibold)])
        heading.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        section.addArrangedSubview(heading)
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.fillColor = Self.cardColor; box.borderWidth = 0
        box.cornerRadius = 10; box.contentViewMargins = .zero
        let contents = vertical(spacing: 10)
        for (index, view) in rows.enumerated() {
            if index > 0 { contents.addArrangedSubview(divider()) }
            contents.addArrangedSubview(view)
        }
        contents.translatesAutoresizingMaskIntoConstraints = false
        let interior = box.contentView!; interior.addSubview(contents)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: width + 28),
            contents.widthAnchor.constraint(equalToConstant: width),
            contents.leadingAnchor.constraint(equalTo: interior.leadingAnchor, constant: 14),
            contents.trailingAnchor.constraint(equalTo: interior.trailingAnchor, constant: -14),
            contents.topAnchor.constraint(equalTo: interior.topAnchor, constant: 10),
            contents.bottomAnchor.constraint(equalTo: interior.bottomAnchor, constant: -10)
        ])
        section.addArrangedSubview(box)
        if !footer.isEmpty {
            let notes = vertical(spacing: 4)
            notes.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 0, right: 10)
            footer.forEach { notes.addArrangedSubview($0) }
            section.addArrangedSubview(notes)
        }
        return section
    }
    private func divider() -> NSView {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: width).isActive = true
        return line
    }
    private func symbol(_ name: String, size: CGFloat) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        view.symbolConfiguration = .init(pointSize: size, weight: .medium)
        view.contentTintColor = .controlAccentColor
        view.setAccessibilityElement(false)
        return view
    }
    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); return label
    }
    private func detail(_ text: String) -> NSTextField { let label = NSTextField(wrappingLabelWithString: text); styleDetail(label); return label }
    private func styleDetail(_ label: NSTextField) { label.font = .systemFont(ofSize: 12); label.textColor = .secondaryLabelColor; label.preferredMaxLayoutWidth = width + 8 }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); translatesAutoresizingMaskIntoConstraints = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
