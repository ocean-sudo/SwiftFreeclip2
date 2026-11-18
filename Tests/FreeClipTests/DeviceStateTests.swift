import Testing
@testable import FreeClip

@Test func connectionStateMovesThroughDiscoveryAndRFCOMM() {
    var machine = DeviceConnectionStateMachine()

    #expect(machine.phase == .disconnected)
    machine.beginDiscovery()
    #expect(machine.phase == .discovering)
    machine.beginRFCOMM()
    #expect(machine.phase == .openingRFCOMM)
    machine.didConnect()
    #expect(machine.phase == .connected)
    #expect(machine.retryAttempt == 0)
}

@Test func reconnectBackoffGrowsAndCaps() {
    var machine = DeviceConnectionStateMachine()

    let delays = (0..<6).map { _ in machine.scheduleRetry() }

    #expect(delays == [2, 4, 8, 16, 30, 30])
    #expect(machine.phase == .waitingToReconnect(seconds: 30))
    #expect(machine.retryAttempt == 6)
}

@Test func successfulReconnectResetsBackoff() {
    var machine = DeviceConnectionStateMachine()
    #expect(machine.scheduleRetry() == 2)
    #expect(machine.scheduleRetry() == 4)

    machine.beginDiscovery()
    machine.beginRFCOMM()
    machine.didConnect()

    #expect(machine.phase == .connected)
    #expect(machine.scheduleRetry() == 2)
}
