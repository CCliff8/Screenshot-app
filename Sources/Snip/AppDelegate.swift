import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var captureItem: NSMenuItem!
    private var recordItem: NSMenuItem!
    private var statusMenu: NSMenu!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildStatusItem()
        buildWindow()
        HotKey.shared.actions[ShortcutAction.screenshot.rawValue] = { [weak self] in self?.capture() }
        HotKey.shared.actions[ShortcutAction.recording.rawValue] = { [weak self] in self?.toggleRecording() }
        Settings.shared.registerAll()
        updateTitles()
        NotificationCenter.default.addObserver(forName: .shortcutChanged, object: nil, queue: .main) { [weak self] _ in
            self?.updateTitles()
        }
        NotificationCenter.default.addObserver(forName: .recordingChanged, object: nil, queue: .main) { [weak self] _ in
            self?.recordingChanged()
        }
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: setup

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Snip"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView())
        window.setFrameAutosaveName("SnipMainWindow")
        if !window.setFrameUsingName("SnipMainWindow") { window.center() }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snip")
        let menu = NSMenu()
        captureItem = item("Take Screenshot", #selector(capture))
        menu.addItem(captureItem)
        recordItem = item("Record Screen", #selector(toggleRecording))
        menu.addItem(recordItem)
        menu.addItem(item("Open Snip", #selector(showWindow)))
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusMenu = menu
    }

    private func buildMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item("Settings…", #selector(openSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Snip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Snip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let file = NSMenu(title: "File")
        file.addItem(item("Take Screenshot", #selector(capture)))
        file.addItem(item("Record Screen", #selector(toggleRecording)))
        file.addItem(item("Save", #selector(save), "s"))
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(undo), "z"))
        let redo = item("Redo", #selector(redo), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Copy Image", #selector(copyImage), "c"))
        add(edit, to: main)

        NSApp.mainMenu = main
    }

    private func add(_ submenu: NSMenu, to menu: NSMenu) {
        let holder = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        menu.addItem(holder)
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: actions

    private func updateTitles() {
        captureItem.title = "Take Screenshot  (\(Settings.shared.shortcut(.screenshot).display))"
        recordItem.title = "Record Screen  (\(Settings.shared.shortcut(.recording).display))"
    }

    @objc func toggleRecording() {
        Task { @MainActor in
            if RecordingController.shared.isRecording { await RecordingController.shared.stop() }
            else { await CaptureController.shared.start(mode: .recording) }
        }
    }

    /// While recording, the menu-bar icon turns red with a timer; clicking it stops the recording.
    private func recordingChanged() {
        let button = statusItem.button
        timer?.invalidate()
        if RecordingController.shared.isRecording {
            statusItem.menu = nil
            button?.target = self
            button?.action = #selector(toggleRecording)
            button?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
            button?.contentTintColor = .systemRed
            let tick = { [weak self] in
                let secs = Int(Date().timeIntervalSince(RecordingController.shared.startedAt))
                self?.statusItem.button?.title = String(format: " %d:%02d", secs / 60, secs % 60)
            }
            tick()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in tick() }
        } else {
            statusItem.menu = statusMenu
            button?.action = nil
            button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Snip")
            button?.contentTintColor = nil
            button?.title = ""
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Snip Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func capture() { Task { @MainActor in await CaptureController.shared.start() } }
    @objc func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func save() { NotificationCenter.default.post(name: .editorSave, object: nil) }
    @objc func undo() { NotificationCenter.default.post(name: .editorUndo, object: nil) }
    @objc func redo() { NotificationCenter.default.post(name: .editorRedo, object: nil) }
    @objc func copyImage() { NotificationCenter.default.post(name: .editorCopy, object: nil) }
}
