import AppKit
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let shortcutChanged = Notification.Name("snip.shortcutChanged")
}

struct Shortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int  // Carbon modifier mask
    var keyLabel: String

    static let `default` = Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | shiftKey, keyLabel: "S")

    var display: String {
        (modifiers & controlKey != 0 ? "⌃" : "") + (modifiers & optionKey != 0 ? "⌥" : "")
            + (modifiers & shiftKey != 0 ? "⇧" : "") + (modifiers & cmdKey != 0 ? "⌘" : "") + keyLabel
    }

    init(keyCode: Int, modifiers: Int, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Returns nil unless the event includes at least one of ⌃ ⌥ ⌘ (a bare letter would hijack typing).
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m = 0
        if f.contains(.control) { m |= controlKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.command) { m |= cmdKey }
        guard m & (controlKey | optionKey | cmdKey) != 0 else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: m, keyLabel: Shortcut.label(for: event))
    }

    private static func label(for e: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return special[Int(e.keyCode)] ?? (e.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

enum ShortcutAction: UInt32, CaseIterable {
    case screenshot = 1, recording = 2, fullScreenshot = 3, fullRecording = 4

    var title: String {
        switch self {
        case .screenshot: "Screenshot (select an area)"
        case .recording: "Screen recording (select an area)"
        case .fullScreenshot: "Full-screen screenshot"
        case .fullRecording: "Full-screen recording"
        }
    }
    var shortName: String {
        switch self {
        case .screenshot: "screenshots"
        case .recording: "recording"
        case .fullScreenshot: "full-screen screenshots"
        case .fullRecording: "full-screen recording"
        }
    }
    var storageKey: String {
        switch self {
        case .screenshot: "captureShortcut"
        case .recording: "recordShortcut"
        case .fullScreenshot: "fullScreenshotShortcut"
        case .fullRecording: "fullRecordShortcut"
        }
    }
    var defaultShortcut: Shortcut {
        switch self {
        case .screenshot: .default
        case .recording: Shortcut(keyCode: kVK_ANSI_R, modifiers: controlKey | shiftKey, keyLabel: "R")
        case .fullScreenshot: Shortcut(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey | shiftKey, keyLabel: "S")
        case .fullRecording: Shortcut(keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey | shiftKey, keyLabel: "R")
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    @Published private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]
    @Published var soundEnabled: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    private init() {
        for a in ShortcutAction.allCases {
            if let data = UserDefaults.standard.data(forKey: a.storageKey),
               let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
                shortcuts[a] = s
            } else {
                shortcuts[a] = a.defaultShortcut
            }
        }
    }

    func shortcut(_ a: ShortcutAction) -> Shortcut { shortcuts[a] ?? a.defaultShortcut }

    /// Registers every hotkey (at launch, and after recording a new shortcut).
    func registerAll() {
        for a in ShortcutAction.allCases {
            if !HotKey.shared.register(shortcut(a), id: a.rawValue) { HotKey.shared.register(a.defaultShortcut, id: a.rawValue) }
        }
    }

    /// Switches an action to a new shortcut. Returns an error message, or nil on success.
    func apply(_ new: Shortcut, for action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcut($0) == new }) {
            return "\(new.display) is already used for \(other.shortName)."
        }
        guard HotKey.shared.register(new, id: action.rawValue) else {
            HotKey.shared.register(shortcut(action), id: action.rawValue)
            return "\(new.display) is already used by the system or another app."
        }
        shortcuts[action] = new
        if let data = try? JSONEncoder().encode(new) { UserDefaults.standard.set(data, forKey: action.storageKey) }
        NotificationCenter.default.post(name: .shortcutChanged, object: nil)
        return nil
    }
}

/// Plays Snip's feedback sounds, unless they're turned off in Settings.
enum Sound {
    private static let shutter = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
        byReference: true)

    static func screenshot() {
        guard Settings.shared.soundEnabled else { return }
        (shutter ?? NSSound(named: "Pop"))?.play()
    }

    static func recordingSaved() {
        guard Settings.shared.soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(ShortcutAction.allCases, id: \.self) { ShortcutRow(action: $0) }
            Toggle("Play sounds (camera shutter on screenshots)", isOn: $settings.soundEnabled)
            Text("Click a button, then press the keys you want. Include ⌃, ⌥ or ⌘. Esc cancels.\nFull-screen shortcuts capture the display under your mouse instantly, with no selection step.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject private var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(action.title).font(.headline)
            HStack {
                Button(recording ? "Press new shortcut…" : settings.shortcut(action).display) { recording ? stop() : start() }
                    .frame(minWidth: 170)
                    .controlSize(.large)
                Button("Reset to \(action.defaultShortcut.display)") { reset() }
                    .disabled(settings.shortcut(action) == action.defaultShortcut)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.red) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        HotKey.shared.unregisterAll()  // so an existing combo can be re-recorded instead of firing
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { stop(); return }  // esc
        guard let s = Shortcut(event: event) else {
            message = "Include at least one of ⌃, ⌥ or ⌘."
            return
        }
        stop()
        message = settings.apply(s, for: action)
    }

    private func reset() {
        message = settings.apply(action.defaultShortcut, for: action)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            Settings.shared.registerAll()
        }
    }
}
