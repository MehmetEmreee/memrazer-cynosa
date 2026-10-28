// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import CynosaKit
import SwiftUI

/// Background agent (LSUIElement): lives in the menu bar, starts at login, opens its window on demand.
@main
struct CynosaApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private static let firstRunKey = "firstRunDone"

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "memrazer-cynosa")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuPanel(openWindow: { [weak self] in self?.openWindow() }).environmentObject(model)
        )

        // First manual launch shows the window once; later launches (including at login) stay in the background.
        if !UserDefaults.standard.bool(forKey: Self.firstRunKey) {
            UserDefaults.standard.set(true, forKey: Self.firstRunKey)
            openWindow()
        }
    }

    /// Host-rendered effects keep running after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening the app again from Finder or Launchpad brings the window up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return false
    }

    // MARK: Status item

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            model.refreshLoginItem()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        model.refreshLoginItem()

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Ayarları Aç…", #selector(openWindowAction), key: ","))
        menu.addItem(.separator())

        let effects = NSMenuItem(title: "Efekt", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for kind in EffectKind.allCases {
            let it = item(kind.title, #selector(selectEffect(_:)))
            it.representedObject = kind.rawValue
            it.state = model.settings.kind == kind ? .on : .off
            it.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
            submenu.addItem(it)
        }
        effects.submenu = submenu
        menu.addItem(effects)

        let login = item("Girişte Aç", #selector(toggleLogin))
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Çık", #selector(quit), key: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    /// Detach the menu once closed so the next left click opens the panel again.
    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    @objc private func openWindowAction() { openWindow() }

    @objc private func selectEffect(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = EffectKind(rawValue: raw) else { return }
        model.settings.kind = kind
    }

    @objc private func toggleLogin() { model.launchAtLogin.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Window

    func openWindow() {
        popover.performClose(nil)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "memrazer-cynosa"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(model))
            w.contentMinSize = NSSize(width: 720, height: 560)
            w.center()
            w.setFrameAutosaveName("main")
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    let openWindow: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(spacing: 12) {
            KeyboardView(frame: model.preview)
                .frame(height: 64)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.05)))

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EffectKind.allCases) { kind in
                    Button { model.settings.kind = kind } label: {
                        Image(systemName: kind.symbol)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(model.settings.kind == kind ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(model.settings.kind == kind ? Color.accentColor : Color.primary.opacity(0.06)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(kind.title)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: $model.settings.brightness, in: 0...100)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            .disabled(!model.connected)

            Divider()

            HStack {
                Toggle("Girişte aç", isOn: $model.launchAtLogin).toggleStyle(.checkbox).font(.callout)
                Spacer()
                Button(action: openWindow) { Image(systemName: "gearshape") }
                    .help("Ayarları aç")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Çık")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 300)
    }
}
