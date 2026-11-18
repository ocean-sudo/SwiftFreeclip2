import Foundation

@main enum ProtocolSmoke {
    static func main() {
        let expectedRequest: [UInt8] = [
            0x5A, 0x00, 0x09, 0x00, 0x01, 0x08,
            0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0xFB, 0xB9
        ]
        precondition(HuaweiSPPCodec.batteryRequest == expectedRequest, "battery request frame mismatch")

        let acknowledgement: [UInt8] = [0x5A, 0x00, 0x03, 0x00, 0x01, 0x06, 0x3E, 0xBD]
        let response: [UInt8] = [
            0x5A, 0x00, 0x1B, 0x00, 0x01, 0x08,
            0x01, 0x01, 0x1E,
            0x02, 0x03, 0x23, 0x1E, 0x4C,
            0x03, 0x03, 0x00, 0x00, 0x00,
            0x04, 0x02, 0x14, 0x0A,
            0x05, 0x02, 0x00, 0x00,
            0x06, 0x01, 0x0A,
            0xB0, 0xAA
        ]

        var decoder = HuaweiSPPCodec()
        let messages = decoder.receive(acknowledgement + response)
        precondition(messages.map(\.command) == [0x0106, 0x0108], "combined frames were not decoded")
        precondition(messages.last?.parameters[2] == [0x23, 0x1E, 0x4C], "battery fields mismatch")

        var splitDecoder = HuaweiSPPCodec()
        precondition(splitDecoder.receive(Array(response.prefix(13))).isEmpty, "partial frame decoded too early")
        precondition(
            splitDecoder.receive(Array(response.dropFirst(13))).last?.parameters[2] == [0x23, 0x1E, 0x4C],
            "split frame was not reassembled"
        )

        var corruptDecoder = HuaweiSPPCodec()
        var corrupt = response
        corrupt[30] ^= 0x01
        precondition(corruptDecoder.receive(corrupt).isEmpty, "bad checksum was accepted")

        precondition(BatteryReadout.lowestReportedEarLevel([0, 20, 98]) == 20, "zero should be unknown")
        precondition(BatteryReadout.lowestReportedEarLevel([0, 0, 98]) == nil, "unknown ear levels should not display 0%")
        precondition(BatteryReadout.caseLevel([0, 20, 98]) == 98, "case should use the third protocol field")

        let identity = PhysicalEarbudIdentityMap.decode(Array("R-RIGHT-2,L-LEFT-1".utf8))
        precondition(identity?.serialNumber(for: .left) == "LEFT-1", "left serial label mismatch")
        precondition(identity?.serialNumber(for: .right) == "RIGHT-2", "right serial label mismatch")
        precondition(PhysicalEarbudIdentityMap.decode(Array("L-ONLY".utf8)) == nil, "incomplete identity was accepted")

        var connection = DeviceConnectionStateMachine()
        connection.beginDiscovery()
        precondition(connection.phase == .discovering, "discovery state mismatch")
        connection.beginRFCOMM()
        precondition(connection.phase == .openingRFCOMM, "RFCOMM state mismatch")
        precondition((0..<6).map { _ in connection.scheduleRetry() } == [2, 4, 8, 16, 30, 30], "backoff mismatch")
        connection.beginDiscovery()
        connection.beginRFCOMM()
        connection.didConnect()
        precondition(connection.phase == .connected && connection.retryAttempt == 0, "successful connection should reset backoff")
        print("Protocol and device-state smoke tests passed")
    }
}
