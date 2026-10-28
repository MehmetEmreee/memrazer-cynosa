// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import CynosaKit
import ServiceManagement
import SwiftUI

enum EffectKind: String, CaseIterable, Codable, Identifiable {
    case off, staticColor, breathing, spectrum, wave, reactive, starlight, fire, sky, rainbow, gif
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Kapalı"
        case .staticColor: "Sabit"
        case .breathing: "Nefes"
        case .spectrum: "Spektrum"
        case .wave: "Dalga"
        case .reactive: "Tepki"
        case .starlight: "Yıldız"
        case .fire: "Şömine"
        case .sky: "Gökyüzü"
        case .rainbow: "Gökkuşağı"
        case .gif: "GIF"
        }
    }

    var symbol: String {
        switch self {
        case .off: "power"
        case .staticColor: "circle.fill"
        case .breathing: "wind"
        case .spectrum: "rainbow"
        case .wave: "water.waves"
        case .reactive: "hand.tap"
        case .starlight: "sparkles"
        case .fire: "flame.fill"
        case .sky: "cloud.sun.fill"
        case .rainbow: "paintpalette.fill"
        case .gif: "photo.stack"
        }
    }
}

/// Every user-tunable parameter, persisted as one blob.
struct Settings: Codable, Equatable {
    var kind: EffectKind = .spectrum
    var color1 = RGB(0, 200, 255)
    var color2 = RGB(255, 0, 140)
    var twoColors = false
    var randomColors = false
    var waveDirection: WaveDirection = .right
    var waveSpeed: Double = 0.5        // 0 slow … 1 fast
    var reactiveSpeed: Double = 2      // 1…4
    var starSpeed: Double = 2          // 1…3
    var firePalette: FirePalette = .classic
    var fireIntensity: Double = 0.7
    var rainbowSpeed: Double = 90
    var gifFile: String?
    var gifMode: ScaleMode = .fill
    var gifSpeed: Double = 1
    var gifVivid = true
    var skyClouds: Double = 0.5
    var skyTimeLapse = false
    var skyPlanes = true
    var brightness: Double = 100

    var colors: [RGB] {
        randomColors ? [] : (twoColors ? [color1, color2] : [color1])
    }

    func effect(library: GIFLibrary) -> Effect? {
        switch kind {
        case .off: .off
        case .staticColor: .staticColor(color1)
        case .breathing: .breathing(colors)
        case .spectrum: .spectrum
        case .wave: .wave(waveDirection, speed: UInt8(max(1, (1 - waveSpeed) * 70 + 4)))
        case .reactive: .reactive(color1, speed: UInt8(reactiveSpeed))
        case .starlight: .starlight(colors, speed: UInt8(starSpeed))
        case .fire: .fire(firePalette, intensity: fireIntensity)
        case .sky: .sky(cloudiness: skyClouds, timeLapse: skyTimeLapse, planes: skyPlanes)
        case .rainbow: .rainbow(speed: rainbowSpeed)
        case .gif: gifFile.flatMap(library.url(for:)).map {
            .gif(path: $0.path, mode: gifMode, speed: gifSpeed, vivid: gifVivid)
        }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings { didSet { settingsChanged(from: oldValue) } }
    @Published private(set) var connected = false
    @Published private(set) var info: DeviceInfo?
    @Published private(set) var preview = Frame()
    @Published var gameMode = false { didSet { if gameMode != oldValue { setGameMode() } } }
    @Published var error: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { if launchAtLogin != oldValue, !syncingLoginItem { setLaunchAtLogin() } }
    }

    let library = GIFLibrary()

    private let monitor = DeviceMonitor()
    private let engine = EffectEngine()
    private var keyboard: Keyboard?
    private var previewPlayer: AnimationPlayer?
    private var applyTask: Task<Void, Never>?
    private var brightnessTask: Task<Void, Never>?
    private static let defaultsKey = "settings.v1"

    init() {
        settings = Self.loadSettings()
        monitor.onChange = { [weak self] kb in
            MainActor.assumeIsolated { self?.deviceChanged(kb) }
        }
        monitor.start()
        observeSleep()
        enableLaunchAtLoginOnFirstRun()
        apply()
    }

    /// Overlays saved keys onto defaults so new fields never wipe older saved settings.
    private static func loadSettings() -> Settings {
        // Pre-1.2 builds used the bundle id "dev.cynosa.app".
        let stored = UserDefaults.standard.data(forKey: defaultsKey)
            ?? UserDefaults(suiteName: "dev.cynosa.app")?.data(forKey: defaultsKey)
        guard let data = stored,
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(Settings())) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: defaults.merging(saved) { _, new in new }),
              let settings = try? JSONDecoder().decode(Settings.self, from: merged)
        else { return Settings() }
        return settings
    }

    // MARK: Device

    private func deviceChanged(_ kb: Keyboard?) {
        keyboard = kb
        connected = kb != nil
        info = nil
        guard let kb else { return }
        Task.detached {
            let info = try? kb.info()
            let game = (try? kb.gameMode()) ?? false
            await MainActor.run {
                self.info = info
                if self.gameMode != game { self.gameMode = game }
            }
        }
        pushBrightness()
        apply()
    }

    private func observeSleep() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.player?.setPaused(true) }
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engine.player?.setPaused(false) }
            }
        }
    }

    // MARK: Effects

    private func settingsChanged(from old: Settings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
        if settings.brightness != old.brightness { pushBrightness() }
        var a = settings, b = old
        a.brightness = 0; b.brightness = 0
        if a != b { scheduleApply() }
    }

    /// Coalesces bursts (colour wheel drags, sliders) into one device write.
    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    func apply() {
        guard let effect = settings.effect(library: library) else {
            engine.stop(); startPreview(nil); return
        }
        do {
            try engine.apply(effect, to: keyboard, onFrame: { [weak self] frame in
                DispatchQueue.main.async { self?.preview = frame }
            }, onError: { [weak self] err in
                DispatchQueue.main.async { self?.report(err) }
            })
            error = nil
        } catch {
            report(error)
        }
        startPreview(effect.isHostRendered ? nil : effect)
    }

    /// Hardware effects run on the keyboard itself; mirror them on screen with a local simulation.
    private func startPreview(_ effect: Effect?) {
        previewPlayer?.stop()
        previewPlayer = nil
        guard let effect else { return }
        let p = AnimationPlayer(animation: PreviewAnimation(effect), keyboard: nil, fps: 30)
        p.onFrame = { [weak self] frame in DispatchQueue.main.async { self?.preview = frame } }
        previewPlayer = p
        p.start()
    }

    private func pushBrightness() {
        brightnessTask?.cancel()
        let value = UInt8((settings.brightness / 100 * 255).rounded())
        let kb = keyboard
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled, let kb else { return }
            do { try kb.setBrightness(value) } catch { self?.report(error) }
        }
    }

    private func setGameMode() {
        guard let kb = keyboard else { return }
        do { try kb.setGameMode(gameMode) } catch { report(error) }
    }

    /// Starts at login by default; after the first run the user's choice wins.
    private func enableLaunchAtLoginOnFirstRun() {
        let key = "loginItemDefaulted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        try? SMAppService.mainApp.register()
        refreshLoginItem()
    }

    private var syncingLoginItem = false

    /// Picks up changes made in System Settings › General › Login Items without re-registering.
    func refreshLoginItem() {
        let enabled = SMAppService.mainApp.status == .enabled
        guard launchAtLogin != enabled else { return }
        syncingLoginItem = true
        launchAtLogin = enabled
        syncingLoginItem = false
    }

    private func setLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            report(error)
        }
    }

    private func report(_ err: Error) {
        if case DeviceError.notConnected = err { return }
        error = err.localizedDescription
    }

    // MARK: GIF

    func importGIFs(_ urls: [URL]) {
        var last: String?
        for url in urls {
            do { last = try library.add(url) } catch { report(error) }
        }
        if let last { select(gif: last) }
    }

    func select(gif name: String) {
        settings.gifFile = name
        settings.kind = .gif
    }

    func remove(gif name: String) {
        library.remove(name)
        if settings.gifFile == name {
            settings.gifFile = library.items.first
        }
    }
}
