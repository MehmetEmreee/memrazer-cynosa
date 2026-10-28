// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import CynosaKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 18) {
            KeyboardView(frame: model.preview)
                .frame(height: 150)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.05)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.06)))

            EffectBar(selection: $model.settings.kind)

            EffectControls()
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .top)

            Spacer(minLength: 0)
            Footer()
        }
        .padding(22)
        .frame(minWidth: 720, minHeight: 560)
        .background(.background)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { model.importGIFs($0) }
            return true
        }
    }
}

func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for p in providers {
        group.enter()
        _ = p.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.withLock { urls.append(url) } }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}

// MARK: - Effect bar

struct EffectBar: View {
    @Binding var selection: EffectKind

    var body: some View {
        HStack(spacing: 6) {
            ForEach(EffectKind.allCases) { kind in
                Button { selection = kind } label: {
                    VStack(spacing: 6) {
                        Image(systemName: kind.symbol).font(.system(size: 16, weight: .medium))
                        Text(kind.title).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(selection == kind ? Color.white : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selection == kind ? Color.accentColor : Color.primary.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Controls

struct Row<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 14) {
            Text(title).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            content
        }
        .frame(height: 28)
    }
}

struct ColorRow: View {
    @Binding var settings: Settings
    var allowTwo = true
    var allowRandom = true

    var body: some View {
        Row(title: "Renk") {
            if !settings.randomColors {
                ColorPicker("", selection: $settings.color1.color, supportsOpacity: false).labelsHidden()
                if allowTwo && settings.twoColors {
                    ColorPicker("", selection: $settings.color2.color, supportsOpacity: false).labelsHidden()
                }
            }
            if allowTwo || allowRandom {
                Picker("", selection: mode) {
                    if allowTwo || allowRandom { Text("Tek").tag(0) }
                    if allowTwo { Text("Çift").tag(1) }
                    if allowRandom { Text("Rastgele").tag(2) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            Spacer()
        }
    }

    private var mode: Binding<Int> {
        Binding(
            get: { settings.randomColors ? 2 : (settings.twoColors ? 1 : 0) },
            set: { settings.randomColors = $0 == 2; settings.twoColors = $0 == 1 }
        )
    }
}

struct EffectControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = $model.settings
        VStack(alignment: .leading, spacing: 10) {
            switch model.settings.kind {
            case .off, .spectrum:
                EmptyView()
            case .staticColor:
                ColorRow(settings: s, allowTwo: false, allowRandom: false)
            case .breathing:
                ColorRow(settings: s)
            case .wave:
                Row(title: "Yön") {
                    Picker("", selection: s.waveDirection) {
                        Image(systemName: "arrow.left").tag(WaveDirection.left)
                        Image(systemName: "arrow.right").tag(WaveDirection.right)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 120)
                    Spacer()
                }
                Row(title: "Hız") { Slider(value: s.waveSpeed, in: 0...1) }
            case .reactive:
                ColorRow(settings: s, allowTwo: false, allowRandom: false)
                Row(title: "Süre") { Slider(value: s.reactiveSpeed, in: 1...4, step: 1) }
            case .starlight:
                ColorRow(settings: s)
                Row(title: "Süre") { Slider(value: s.starSpeed, in: 1...3, step: 1) }
            case .fire:
                Row(title: "Alev") {
                    Picker("", selection: s.firePalette) {
                        Text("Klasik").tag(FirePalette.classic)
                        Text("Mavi").tag(FirePalette.blue)
                        Text("Yeşil").tag(FirePalette.green)
                        Text("Mor").tag(FirePalette.purple)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 300)
                    Spacer()
                }
                Row(title: "Yoğunluk") { Slider(value: s.fireIntensity, in: 0...1) }
            case .sky:
                Row(title: "Bulut") {
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                    Slider(value: s.skyClouds, in: 0...1)
                    Image(systemName: "cloud.fill").foregroundStyle(.secondary)
                }
                Row(title: "Hızlı gün") {
                    Toggle("", isOn: s.skyTimeLapse).toggleStyle(.switch).labelsHidden()
                    Spacer()
                }
                Row(title: "Uçak") {
                    Toggle("", isOn: s.skyPlanes).toggleStyle(.switch).labelsHidden()
                    Spacer()
                }
            case .rainbow:
                Row(title: "Hız") { Slider(value: s.rainbowSpeed, in: 10...360) }
            case .gif:
                GIFPanel(library: model.library)
            }
        }
        .animation(.snappy(duration: 0.2), value: model.settings.kind)
    }
}

// MARK: - GIF

struct GIFPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var library: GIFLibrary
    @State private var importing = false

    var body: some View {
        let s = $model.settings
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { importing = true } label: {
                        Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                            .frame(width: 112, height: 64)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(library.items, id: \.self) { name in
                        if let url = library.url(for: name) {
                            AnimatedImage(url: url)
                                .frame(width: 112, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(model.settings.gifFile == name ? Color.accentColor : .clear, lineWidth: 2.5))
                                .onTapGesture { model.select(gif: name) }
                                .contextMenu { Button("Sil", role: .destructive) { model.remove(gif: name) } }
                                .help(name)
                        }
                    }
                }
                .padding(2)
            }
            HStack(spacing: 24) {
                Picker("", selection: s.gifMode) {
                    Text("Doldur").tag(ScaleMode.fill)
                    Text("Sığdır").tag(ScaleMode.fit)
                    Text("Uzat").tag(ScaleMode.stretch)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                HStack {
                    Image(systemName: "tortoise").foregroundStyle(.secondary)
                    Slider(value: s.gifSpeed, in: 0.25...3)
                    Image(systemName: "hare").foregroundStyle(.secondary)
                }
                Toggle("Canlı", isOn: s.gifVivid).toggleStyle(.switch)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: GIFLibrary.types, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
                model.importGIFs(urls)
                scoped.forEach { $0.stopAccessingSecurityScopedResource() }
            }
        }
    }
}

struct AnimatedImage: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyUpOrDown
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.cgColor
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.image = NSImage(contentsOf: url)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {}
}

// MARK: - Footer

struct Footer: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connected ? "Cynosa V2" : "Bağlı değil").font(.system(size: 12, weight: .semibold))
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                } else if let info = model.info {
                    Text("v\(info.firmware)").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "sun.min").foregroundStyle(.secondary)
                Slider(value: $model.settings.brightness, in: 0...100).frame(width: 180)
                Image(systemName: "sun.max").foregroundStyle(.secondary)
            }
            Toggle(isOn: $model.gameMode) { Image(systemName: "gamecontroller") }
                .toggleStyle(.button)
                .help("Oyun modu")
        }
        .disabled(!model.connected)
    }
}
