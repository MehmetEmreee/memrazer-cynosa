// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CUSB
import IOKit.hid

public enum DeviceError: Error, Equatable, LocalizedError {
    case notConnected
    case io(String, IOReturn)
    case rejected(CommandStatus?)
    case mismatchedResponse
    case busy

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Klavye bağlı değil"
        case .io(let op, let code): return "\(op) hatası (\(String(format: "0x%08X", code)))"
        case .rejected(let s): return "Komut reddedildi (\(s.map { "\($0)" } ?? "bilinmeyen durum"))"
        case .mismatchedResponse: return "Beklenmeyen cevap"
        case .busy: return "Cihaz meşgul"
        }
    }
}

public protocol ReportTransport: AnyObject {
    func exchange(_ request: RazerReport) throws -> RazerReport
}

/// Shared request/response loop. After each write the response is polled until the
/// device stops reporting busy; stray short reads are discarded. Only a timed-out poll resends.
func exchange(_ request: RazerReport, attempts: Int, settle: useconds_t,
              write: ([UInt8]) -> IOReturn, read: (inout [UInt8]) -> (IOReturn, Int)) throws -> RazerReport {
    let sealed = request.sealed()
    let pollInterval: useconds_t = 300
    let maxPolls = 60
    var lastError: DeviceError = .busy

    for _ in 0..<attempts {
        let w = write(sealed.bytes)
        guard w == kIOReturnSuccess else {
            if w == kIOReturnNotAttached || w == kIOReturnNoDevice { throw DeviceError.notConnected }
            lastError = .io("SetReport", w)
            usleep(2000)
            continue
        }
        usleep(settle)

        for _ in 0..<maxPolls {
            var buffer = [UInt8](repeating: 0, count: RazerReport.length)
            let (g, length) = read(&buffer)
            if g == kIOReturnNotAttached || g == kIOReturnNoDevice { throw DeviceError.notConnected }
            guard g == kIOReturnSuccess else { lastError = .io("GetReport", g); break }
            guard length == RazerReport.length, let response = RazerReport(bytes: buffer), response.answers(sealed) else {
                lastError = .mismatchedResponse
                usleep(pollInterval)
                continue
            }
            switch response.status {
            case .success: return response
            case .busy, .new:
                lastError = .busy
                usleep(pollInterval)
            case let s:
                throw DeviceError.rejected(s)
            }
        }
    }
    throw lastError
}

/// USB control transfers straight to the device (no TCC prompt, no HID open).
/// Not thread-safe; callers serialize access (see `Keyboard`).
public final class USBTransport: ReportTransport {
    /// OpenRazer `report_index` for the Cynosa V2.
    public static let controlInterface: UInt16 = 1

    private let handle: OpaquePointer
    private let settle: useconds_t
    private let attempts: Int

    public init(vendorID: Int = Cynosa.vendorID, productID: Int = Cynosa.productID,
                settle: useconds_t = 600, attempts: Int = 5) throws {
        var err: IOReturn = 0
        guard let h = cusb_open(UInt16(vendorID), UInt16(productID), &err) else {
            throw err == kIOReturnNotFound ? DeviceError.notConnected : DeviceError.io("USB open", err)
        }
        handle = h
        self.settle = settle
        self.attempts = attempts
    }

    deinit { cusb_close(handle) }

    public func exchange(_ request: RazerReport) throws -> RazerReport {
        try CynosaKit.exchange(request, attempts: attempts, settle: settle, write: { bytes in
            bytes.withUnsafeBufferPointer { cusb_set_feature(handle, Self.controlInterface, $0.baseAddress, UInt16($0.count)) }
        }, read: { buffer in
            var done: UInt32 = 0
            let count = UInt16(buffer.count)
            let r = buffer.withUnsafeMutableBufferPointer { cusb_get_feature(handle, Self.controlInterface, $0.baseAddress, count, &done) }
            return (r, Int(done))
        })
    }
}

/// Feature reports through IOHID. Requires Input Monitoring when not run from a privileged terminal.
public final class HIDTransport: ReportTransport {
    let device: IOHIDDevice
    private let settle: useconds_t
    private let attempts: Int

    public init(device: IOHIDDevice, settle: useconds_t = 600, attempts: Int = 5) {
        self.device = device
        self.settle = settle
        self.attempts = attempts
    }

    public static func isControlInterface(_ device: IOHIDDevice) -> Bool {
        let size = IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
        return size >= RazerReport.length
    }

    public func exchange(_ request: RazerReport) throws -> RazerReport {
        try CynosaKit.exchange(request, attempts: attempts, settle: settle, write: { bytes in
            bytes.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
            }
        }, read: { buffer in
            var length = buffer.count
            let r = buffer.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &length)
            }
            return (r, length)
        })
    }
}
