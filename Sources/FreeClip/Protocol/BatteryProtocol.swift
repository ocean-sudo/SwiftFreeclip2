import Foundation

struct HuaweiSPPMessage: Equatable {
    let command: UInt16
    let parameters: [UInt8: [UInt8]]
}

enum BudPlacement: Equatable {
    case left
    case right
    case inCase
    case unknown

    var title: String {
        switch self {
        case .left: "左耳"
        case .right: "右耳"
        case .inCase: "盒中"
        case .unknown: "未知"
        }
    }
}

struct PlacedBud: Equatable {
    let id: Int
    let level: UInt8?
    let isCharging: Bool
    let placement: BudPlacement
}

struct ThreeDrawerState: Equatable {
    let left: PlacedBud?
    let right: PlacedBud?
    let caseLevel: UInt8?
    let inCaseBuds: [PlacedBud]
}

struct EarbudSlotStatus: Equatable {
    let index: Int
    let level: UInt8?
    let isCharging: Bool
}

enum BatteryReadout {
    /// Returns permanent physical buds (id 1 and 2) sorted by ID, each tagged with its current placement (left, right, inCase).
    static func permanentBuds(
        values: [UInt8]?,
        chargingStates: [UInt8]?,
        identityMap: PhysicalEarbudIdentityMap?
    ) -> [PlacedBud] {
        guard let values, values.count >= 2 else {
            return [
                PlacedBud(id: 1, level: nil, isCharging: false, placement: .unknown),
                PlacedBud(id: 2, level: nil, isCharging: false, placement: .unknown)
            ]
        }

        let permanentOrder: [String] = if let identityMap {
            [identityMap.leftSerialNumber, identityMap.rightSerialNumber].sorted()
        } else {
            []
        }

        func permanentID(forSlot slot: Int) -> Int {
            guard let identityMap, permanentOrder.count == 2 else { return slot + 1 }
            let serial = slot == 0 ? identityMap.leftSerialNumber : identityMap.rightSerialNumber
            return (permanentOrder.firstIndex(of: serial) ?? slot) + 1
        }

        return (0..<2).map { slot in
            let raw = values[slot]
            let validLevel: UInt8? = (raw > 0 && raw <= 100) ? raw : nil
            let isCharging = (chargingStates?.count ?? 0) > slot && chargingStates?[slot] == 1
            let placement: BudPlacement = if isCharging || validLevel == nil {
                .inCase
            } else if slot == 0 {
                .left
            } else {
                .right
            }
            return PlacedBud(
                id: permanentID(forSlot: slot),
                level: validLevel,
                isCharging: isCharging,
                placement: placement
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Maps reported slots into the 3 drawers (Left Ear, Right Ear, Charging Case) using permanent physical bud IDs (1 and 2).
    static func threeDrawers(
        values: [UInt8]?,
        chargingStates: [UInt8]?,
        identityMap: PhysicalEarbudIdentityMap?
    ) -> ThreeDrawerState {
        let caseLevel = caseLevel(values)
        guard let values, values.count >= 2 else {
            return ThreeDrawerState(left: nil, right: nil, caseLevel: caseLevel, inCaseBuds: [])
        }

        let permanentOrder: [String] = if let identityMap {
            [identityMap.leftSerialNumber, identityMap.rightSerialNumber].sorted()
        } else {
            []
        }

        func permanentID(forSlot slot: Int) -> Int {
            guard let identityMap, permanentOrder.count == 2 else { return slot + 1 }
            let serial = slot == 0 ? identityMap.leftSerialNumber : identityMap.rightSerialNumber
            return (permanentOrder.firstIndex(of: serial) ?? slot) + 1
        }

        var left: PlacedBud?
        var right: PlacedBud?
        var inCaseBuds: [PlacedBud] = []

        for slot in 0..<2 {
            let raw = values[slot]
            let validLevel: UInt8? = (raw > 0 && raw <= 100) ? raw : nil
            let isCharging = (chargingStates?.count ?? 0) > slot && chargingStates?[slot] == 1
            let placement: BudPlacement = (isCharging || validLevel == nil) ? .inCase : (slot == 0 ? .left : .right)
            let bud = PlacedBud(id: permanentID(forSlot: slot), level: validLevel, isCharging: isCharging, placement: placement)

            if isCharging || validLevel == nil {
                inCaseBuds.append(bud)
            } else if slot == 0 {
                left = bud
            } else {
                right = bud
            }
        }

        inCaseBuds.sort { $0.id < $1.id }
        return ThreeDrawerState(left: left, right: right, caseLevel: caseLevel, inCaseBuds: inCaseBuds)
    }

    /// Physical earbud slots (index 0 = Earbud 1, index 1 = Earbud 2) with charging state from parameter 3.
    static func physicalEarbuds(_ values: [UInt8]?, chargingStates: [UInt8]?) -> [EarbudSlotStatus] {
        guard let values, values.count >= 2 else { return [] }
        return (0..<2).map { index in
            let rawLevel = values[index]
            let level: UInt8? = (rawLevel > 0 && rawLevel <= 100) ? rawLevel : nil
            let isCharging = (chargingStates?.count ?? 0) > index && chargingStates?[index] == 1
            return EarbudSlotStatus(index: index, level: level, isCharging: isCharging)
        }
    }

    /// Left ear battery when out of the charging case (`index 0` follows worn left ear after adaptive detection).
    static func leftLevel(_ values: [UInt8]?, chargingStates: [UInt8]?) -> UInt8? {
        earLevel(at: 0, values: values, chargingStates: chargingStates)
    }

    /// Right ear battery when out of the charging case (`index 1` follows worn right ear after adaptive detection).
    static func rightLevel(_ values: [UInt8]?, chargingStates: [UInt8]?) -> UInt8? {
        earLevel(at: 1, values: values, chargingStates: chargingStates)
    }

    private static func earLevel(at index: Int, values: [UInt8]?, chargingStates: [UInt8]?) -> UInt8? {
        guard let values, values.count > index else { return nil }
        if (chargingStates?.count ?? 0) > index, chargingStates?[index] == 1 {
            return nil
        }
        let level = values[index]
        return level > 0 && level <= 100 ? level : nil
    }

    /// Lowest valid level in the two protocol fields upstream interprets as earbuds.
    static func lowestReportedEarLevel(_ values: [UInt8]?) -> UInt8? {
        guard let values else { return nil }
        var lowest: UInt8?
        for value in values.prefix(2) where value > 0 && value <= 100 {
            if let current = lowest {
                if value < current { lowest = value }
            } else {
                lowest = value
            }
        }
        return lowest
    }

    /// The third value is the case level in the FreeClip 2 battery response.
    static func caseLevel(_ values: [UInt8]?) -> UInt8? {
        guard let values, values.count == 3 else { return nil }
        let level = values[2]
        return level > 0 && level <= 100 ? level : nil
    }

}
/// Huawei SPP framing and incremental response decoding.
struct HuaweiSPPCodec {
    private var buffer: [UInt8] = []
    private static let maximumFrameLength = 260

    static func readRequest(command: UInt16, parameterIDs: [UInt8]) -> [UInt8] {
        var parameters: [UInt8] = []
        parameters.reserveCapacity(parameterIDs.count * 2)
        for parameterID in parameterIDs {
            parameters.append(parameterID)
            parameters.append(0)
        }
        return frame(command: command, parameters: parameters)
    }

    static func writeRequest(command: UInt16, parameters: [UInt8: [UInt8]]) -> [UInt8] {
        var body: [UInt8] = []
        for key in parameters.keys.sorted() {
            let value = parameters[key] ?? []
            body.append(key)
            body.append(UInt8(value.count))
            body.append(contentsOf: value)
        }
        return frame(command: command, parameters: body)
    }

    static var batteryRequest: [UInt8] {
        readRequest(command: 0x0108, parameterIDs: [1, 2, 3])
    }

    mutating func reset() { buffer.removeAll(keepingCapacity: true) }

    mutating func receive(_ bytes: [UInt8]) -> [HuaweiSPPMessage] {
        buffer.append(contentsOf: bytes)
        var messages: [HuaweiSPPMessage] = []
        while true {
            while !buffer.isEmpty && buffer[0] != 0x5A { buffer.removeFirst() }
            guard buffer.count >= 3 else { break }
            let frameLength = Int(buffer[1]) * 256 + Int(buffer[2]) + 5
            guard frameLength >= 8 && frameLength <= Self.maximumFrameLength else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= frameLength else { break }
            let frame = Array(buffer.prefix(frameLength))
            buffer.removeFirst(frameLength)
            let checksum = UInt16(frame[frameLength - 2]) << 8 | UInt16(frame[frameLength - 1])
            guard Self.crc(Array(frame.dropLast(2))) == checksum, frame[3] == 0 else { continue }

            let command = UInt16(frame[4]) << 8 | UInt16(frame[5])
            let checksumStart = frameLength - 2
            var parameters: [UInt8: [UInt8]] = [:]
            var index = 6
            var valid = true
            while index + 2 <= checksumStart {
                let type = frame[index]
                let count = Int(frame[index + 1])
                index += 2
                guard index + count <= checksumStart else {
                    valid = false
                    break
                }
                parameters[type] = Array(frame[index..<index + count])
                index += count
            }
            if valid && index == checksumStart {
                messages.append(HuaweiSPPMessage(command: command, parameters: parameters))
            }
        }
        return messages
    }

    private static func frame(command: UInt16, parameters: [UInt8]) -> [UInt8] {
        let body = [UInt8(command >> 8), UInt8(command & 0xFF)] + parameters
        var bytes = [UInt8(0x5A), UInt8((body.count + 1) >> 8), UInt8((body.count + 1) & 0xFF), 0] + body
        let checksum = crc(bytes)
        bytes += [UInt8(checksum >> 8), UInt8(checksum & 0xFF)]
        return bytes
    }

    private static func crc(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0
        for byte in bytes {
            value ^= UInt16(byte) << 8
            for _ in 0..<8 {
                value = value & 0x8000 != 0 ? (value << 1) ^ 0x1021 : value << 1
            }
        }
        return value
    }
}
