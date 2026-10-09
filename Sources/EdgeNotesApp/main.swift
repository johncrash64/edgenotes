import AppKit
import EdgeNotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: NoteStore?
    private var controller: EdgePanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store = NoteStore(repository: FileNoteRepository(directory: FileNoteRepository.defaultDirectory))
        store.load()
        store.seedIfEmpty()
        self.store = store

        let controller = EdgePanelController(store: store)
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
        menu.addItem(withTitle: "Quit EdgeNotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showNotes() { controller?.openDeck() }
    @objc private func newNote() { controller?.newNote() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
