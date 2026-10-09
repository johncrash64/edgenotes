import AppKit
import EdgeNotesCore
import ServiceManagement
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: NoteStore?
    private var controller: EdgePanelController?
    private var editor: EditorController?
    private var statusItem: NSStatusItem?
    private var loginItem: NSMenuItem?
    private let logger = Logger(subsystem: "com.johncrash64.edgenotes", category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = NoteStore(repository: FileNoteRepository(directory: FileNoteRepository.defaultDirectory))
        store.load()
        store.seedIfEmpty()
        self.store = store

        let editor = EditorController(store: store)
        self.editor = editor

        let controller = EdgePanelController(store: store)
        controller.onEditNote = { [weak editor] id in editor?.open(noteID: id) }
        controller.show()
        self.controller = controller

        installMainMenu()
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
    }

    /// Never shown (agent app), but AppKit resolves ⌘A/C/V/X/Z through it.
    private func installMainMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "EdgeNotes")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Notes", action: #selector(showNotes), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Note", action: #selector(newNote), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        loginItem = login
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EdgeNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// Reflects the real login-item state every time the menu opens, since the
    /// user can also change it in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem?.state = .on
            loginItem?.title = "Launch at Login"
        case .requiresApproval:
            loginItem?.state = .mixed
            loginItem?.title = "Launch at Login (approve in Settings…)"
        default:
            loginItem?.state = .off
            loginItem?.title = "Launch at Login"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            logger.error("Could not change login item: \(error.localizedDescription, privacy: .public)")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc private func showNotes() { controller?.openDeck() }
    @objc private func newNote() { controller?.newNote() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
