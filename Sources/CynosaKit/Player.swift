// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Drives an `Animation` on a dedicated thread, dropping frames if the device is slower.
/// The rate follows `Animation.preferredFPS` frame by frame and falls back to `fps`.
public final class AnimationPlayer: @unchecked Sendable {
    public let animation: Animation
    public let fps: Double
    /// Called on the player thread after every frame (sent or not).
    public var onFrame: ((Frame) -> Void)?
    /// Called on the player thread when the device goes away or fails repeatedly.
    public var onError: ((Error) -> Void)?

    private let keyboard: Keyboard?
    private let lock = NSLock()
    private var running = false
    private var paused = false
    private var thread: Thread?

    public init(animation: Animation, keyboard: Keyboard?, fps: Double = 30) {
        self.animation = animation
        self.keyboard = keyboard
        self.fps = min(max(fps, 1), 60)
    }

    public var isRunning: Bool { lock.withLock { running } }

    public func start() {
        lock.withLock {
            guard !running else { return }
            running = true
            let t = Thread { [weak self] in self?.loop() }
            t.name = "memrazer-cynosa.player"
            t.qualityOfService = .userInteractive
            thread = t
            t.start()
        }
    }

    public func stop() { lock.withLock { running = false } }

    public func setPaused(_ value: Bool) { lock.withLock { paused = value } }

    private func loop() {
        let origin = Date()
        var pausedFor: TimeInterval = 0
        var failures = 0
        var next = origin.timeIntervalSinceReferenceDate

        while true {
            let (isRunning, isPaused) = lock.withLock { (running, paused) }
            guard isRunning else { return }
            if isPaused {
                Thread.sleep(forTimeInterval: 0.1)
                pausedFor += 0.1
                next = Date().timeIntervalSinceReferenceDate
                continue
            }

            let t = Date().timeIntervalSince(origin) - pausedFor
            let frame = animation.frame(at: t)
            if let keyboard {
                do {
                    try keyboard.show(frame)
                    failures = 0
                } catch DeviceError.notConnected {
                    onError?(DeviceError.notConnected)
                    stop(); return
                } catch {
                    failures += 1
                    if failures >= 10 { onError?(error); stop(); return }
                }
            }
            onFrame?(frame)

            next += 1 / min(max(animation.preferredFPS ?? fps, 1), 60)
            let now = Date().timeIntervalSinceReferenceDate
            if next > now {
                Thread.sleep(forTimeInterval: next - now)
            } else {
                next = now // fell behind: skip ahead instead of bursting
            }
        }
    }
}
