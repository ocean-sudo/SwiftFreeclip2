import Testing
@testable import FreeClip

@Test func decodesCapturedFreeClip2BatteryResponse() {
    var decoder = HuaweiSPPCodec()
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
    let messages = decoder.receive(acknowledgement + response)
    #expect(messages.map(\.command) == [0x0106, 0x0108])
    #expect(messages.last?.parameters[2] == [0x23, 0x1E, 0x4C])
}

@Test func buffersSplitFramesAndRejectsCorruptChecksum() {
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
    #expect(decoder.receive(Array(response.prefix(13))).isEmpty)
    #expect(decoder.receive(Array(response.dropFirst(13))).last?.parameters[2] == [0x23, 0x1E, 0x4C])

    var corruptDecoder = HuaweiSPPCodec()
    var corrupt = response
    corrupt[30] ^= 0x01
    #expect(corruptDecoder.receive(corrupt).isEmpty)
}

@Test func buildsCapturedBatteryReadRequest() {
    #expect(HuaweiSPPCodec.batteryRequest == [
        0x5A, 0x00, 0x09, 0x00, 0x01, 0x08,
        0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0xFB, 0xB9
    ])
}

@Test func earSummaryIgnoresUnknownZeroAndCaseField() {
    #expect(BatteryReadout.lowestReportedEarLevel([0, 20, 98]) == 20)
    #expect(BatteryReadout.lowestReportedEarLevel([15, 10, 98]) == 10)
    #expect(BatteryReadout.lowestReportedEarLevel([0, 0, 98]) == nil)
    #expect(BatteryReadout.lowestReportedEarLevel(nil) == nil)
}

@Test func displaysCaseBatteryWithoutGuessingEarbudIdentity() {
    #expect(BatteryReadout.caseLevel([0, 20, 98]) == 98)
    #expect(BatteryReadout.caseLevel([15, 10, 0]) == nil)
    #expect(BatteryReadout.caseLevel([15, 10]) == nil)
}

@Test func parsesPhysicalSerialLabelsIndependentOfFieldOrder() {
    let mapping = PhysicalEarbudIdentityMap.decode(Array("R-RIGHT-2,L-LEFT-1".utf8))
    #expect(mapping?.serialNumber(for: .left) == "LEFT-1")
    #expect(mapping?.serialNumber(for: .right) == "RIGHT-2")
}

@Test func malformedOrMissingIdentityNeverAssignsPhysicalSides() {
    #expect(PhysicalEarbudIdentityMap.decode(Array("L-ONLY-ONE".utf8)) == nil)
    #expect(PhysicalEarbudIdentityMap.decode(Array("L-,R-RIGHT".utf8)) == nil)
    #expect(PhysicalEarbudIdentityMap.decode([0xFF, 0xFE]) == nil)
}

@Test func physicalEarbudsExposeChargingSlotsWithoutGuessingWornSide() {
    let slots = BatteryReadout.physicalEarbuds([91, 72, 51], chargingStates: [0, 1, 0])
    #expect(slots == [
        EarbudSlotStatus(index: 0, level: 91, isCharging: false),
        EarbudSlotStatus(index: 1, level: 72, isCharging: true)
    ])
    #expect(BatteryReadout.leftLevel([91, 72, 51], chargingStates: [0, 1, 0]) == 91)
    #expect(BatteryReadout.rightLevel([91, 72, 51], chargingStates: [0, 1, 0]) == nil)
    #expect(BatteryReadout.leftLevel([88, 88, 49], chargingStates: [1, 0, 0]) == nil)
    #expect(BatteryReadout.rightLevel([88, 88, 49], chargingStates: [1, 0, 0]) == 88)
}

@Test func threeDrawersKeepPermanentBudIDsAcrossEarSwaps() {
    let mapRight = PhysicalEarbudIdentityMap(leftSerialNumber: "AAA", rightSerialNumber: "BBB")
    let budsRight = BatteryReadout.permanentBuds(values: [88, 92, 48], chargingStates: [1, 0, 0], identityMap: mapRight)
    #expect(budsRight == [
        PlacedBud(id: 1, level: 88, isCharging: true, placement: .inCase),
        PlacedBud(id: 2, level: 92, isCharging: false, placement: .right)
    ])

    let mapSwapped = PhysicalEarbudIdentityMap(leftSerialNumber: "BBB", rightSerialNumber: "AAA")
    let budsSwapped = BatteryReadout.permanentBuds(values: [91, 88, 48], chargingStates: [0, 1, 0], identityMap: mapSwapped)
    #expect(budsSwapped == [
        PlacedBud(id: 1, level: 88, isCharging: true, placement: .inCase),
        PlacedBud(id: 2, level: 91, isCharging: false, placement: .left)
    ])
}
