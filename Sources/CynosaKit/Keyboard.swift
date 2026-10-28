// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import IOKit.hid
import os

let log = Logger(subsystem: "io.github.mehmetemreee.memrazer-cynosa", category: "device")

public struct DeviceInfo: Equatable, Sendable {
    public var firmware: String
    public var serial: String
}

/// Thread-safe handle to one connected Cynosa V2. All I/O runs on a private serial queue.
public final class Keyboard: @unchecked Sendable {
    private let transport: ReportTransport
    private let queue = DispatchQueue(label: "memrazer-cynosa.io", qos: .userInteractive)
    /// What the device's custom-frame buffer holds; nil when unknown (startup, effect change, error).
    private var shown: Frame?

    public init(transport: ReportTransport) {
        self.transport = transport
    }

    @discardableResult
    public func send(_ report: RazerReport) throws -> RazerReport {
        try queue.sync {
            if report.commandClass == 0x0F && report.commandID == 0x02 { shown = nil } // effect change
            return try transport.exchange(report)
        }
    }

    /// Writes a frame as one unit on the I/O queue. Only rows that differ from what the
    /// device already shows are sent; an identical frame costs no USB traffic at all.
    /// Returns the number of rows written.
    @discardableResult
    public func show(_ frame: Frame) throws -> Int {
        try queue.sync {
            let rows = (0..<Frame.rows).filter { shown?.row($0) != frame.row($0) }
            guard !rows.isEmpty else { return 0 }
            do {
                for r in rows {
                    _ = try transport.exchange(Command.frameRow(r, colors: frame.row(r)))
                }
                _ = try transport.exchange(Command.showCustomFrame())
                shown = frame
            } catch {
                shown = nil
                throw error
            }
            return rows.count
        }
    }

    /// Forces the next `show` to rewrite every row.
    public func invalidateFrame() { queue.sync { shown = nil } }

    public func info() throws -> DeviceInfo {
        let fw = try send(Command.firmware())
        let sn = try send(Command.serial())
        let raw = (0..<22).map { sn[arg: $0] }.prefix { $0 != 0 }
        return DeviceInfo(firmware: "\(fw[arg: 0]).\(fw[arg: 1])",
                          serial: String(decoding: raw, as: UTF8.self))
    }

    public func brightness() throws -> UInt8 { try send(Command.getBrightness())[arg: 2] }
    public func setBrightness(_ v: UInt8) throws { try send(Command.setBrightness(v)) }
    public func gameMode() throws -> Bool { try send(Command.getGameMode())[arg: 2] == 1 }
    public func setGameMode(_ on: Bool) throws { try send(Command.setGameMode(on)) }
}

extension Keyboard {
    /// Synchronous lookup without hot-plug tracking (CLI use).
    public static func open() throws -> Keyboard {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, DeviceMonitor.matching)
        let device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first(where: HIDTransport.isControlInterface)
        return try open(hid: device)
    }

    /// Prefers raw USB control transfers; falls back to IOHID (needs Input Monitoring).
    static func open(hid device: IOHIDDevice?) throws -> Keyboard {
        do {
            return Keyboard(transport: try USBTransport())
        } catch {
            log.notice("USB transport unavailable (\(error.localizedDescription, privacy: .public)), trying HID")
            guard let device else { throw error }
            let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard r == kIOReturnSuccess else { throw DeviceError.io("HID open", r) }
            return Keyboard(transport: HIDTransport(device: device))
        }
    }
}

/// Tracks connect / disconnect of the Cynosa V2 control interface on the main run loop.
public final class DeviceMonitor {
    static let matching = [
        kIOHIDVendorIDKey: Cynosa.vendorID,
        kIOHIDProductIDKey: Cynosa.productID,
    ] as CFDictionary

    public var onChange: ((Keyboard?) -> Void)?
    public private(set) var keyboard: Keyboard?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var current: IOHIDDevice?

    public init() {}

    public func start() {
        IOHIDManagerSetDeviceMatching(manager, Self.matching)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue().attached(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<DeviceMonitor>.fromOpaque(ctx!).takeUnretainedValue().detached(device)
        }, ctx)
        // Scheduling alone delivers matching callbacks; IOHIDManagerOpen would seize every interface and trip TCC.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    public func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func attached(_ device: IOHIDDevice) {
        guard current == nil, HIDTransport.isControlInterface(device) else { return }
        do {
            keyboard = try Keyboard.open(hid: device)
        } catch {
            log.error("open failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        log.info("Cynosa V2 connected")
        current = device
        onChange?(keyboard)
    }

    private func detached(_ device: IOHIDDevice) {
        guard device == current else { return }
        log.info("Cynosa V2 disconnected")
        current = nil
        keyboard = nil
        onChange?(nil)
    }
}
