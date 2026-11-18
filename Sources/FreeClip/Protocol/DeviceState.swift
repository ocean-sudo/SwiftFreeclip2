import Foundation

enum EarbudSide: Hashable {
    case left
    case right
}

/// Serial labels reported by device info; their relationship to worn sides is unverified.
struct PhysicalEarbudIdentityMap: Equatable {
    let leftSerialNumber: String
    let rightSerialNumber: String

    static func decode(_ bytes: [UInt8]) -> PhysicalEarbudIdentityMap? {
        guard let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        let entries = text.split(separator: ",", omittingEmptySubsequences: false)
        guard entries.count == 2 else { return nil }

        var leftSerial: String?
        var rightSerial: String?
        for entry in entries {
            guard entry.count > 2 else { return nil }
            let serial = String(entry.dropFirst(2))
            switch entry.prefix(2) {
            case "L-":
                guard leftSerial == nil else { return nil }
                leftSerial = serial
            case "R-":
                guard rightSerial == nil else { return nil }
                rightSerial = serial
            default:
                return nil
            }
        }
        guard let leftSerial, let rightSerial, leftSerial != rightSerial else { return nil }
        return PhysicalEarbudIdentityMap(leftSerialNumber: leftSerial, rightSerialNumber: rightSerial)
    }

    func serialNumber(for side: EarbudSide) -> String {
        side == .left ? leftSerialNumber : rightSerialNumber
    }

}

enum DeviceConnectionPhase: Equatable {
    case disconnected
    case discovering
    case openingRFCOMM
    case connected
    case waitingToReconnect(seconds: Int)
}

struct DeviceConnectionStateMachine {
    private(set) var phase: DeviceConnectionPhase = .disconnected
    private(set) var retryAttempt = 0

    mutating func beginDiscovery() {
        phase = .discovering
    }

    mutating func beginRFCOMM() {
        phase = .openingRFCOMM
    }

    mutating func didConnect() {
        phase = .connected
        retryAttempt = 0
    }

    mutating func didDisconnect() {
        phase = .disconnected
    }

    mutating func scheduleRetry() -> Int {
        let delay = ReconnectPolicy.delay(for: retryAttempt)
        retryAttempt += 1
        phase = .waitingToReconnect(seconds: delay)
        return delay
    }

    mutating func reset() {
        phase = .disconnected
        retryAttempt = 0
    }
}

enum ReconnectPolicy {
    static func delay(for attempt: Int) -> Int {
        var delay = 2
        for _ in 0..<max(0, min(attempt, 4)) {
            delay = min(delay * 2, 30)
        }
        return delay
    }
}
