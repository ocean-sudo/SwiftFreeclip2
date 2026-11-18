import Foundation
import Testing
@testable import FreeClip

/// Opt in with FREECLIP_HARDWARE_TESTS=1 on a Mac paired with a real FreeClip 2.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FREECLIP_HARDWARE_TESTS"] == "1"))
@MainActor
func readsBatteryAndPhysicalEarbudIdentityFromFreeClip2() async {
    let controller = Controller()
    defer { controller.stop() }

    guard let device = controller.devices.first(where: {
        ($0.name ?? "").localizedCaseInsensitiveContains("FreeClip 2")
    }) else {
        Issue.record("A paired HUAWEI FreeClip 2 is required for this hardware test")
        return
    }
    if controller.status == "选择已配对的设备" {
        controller.connect(device)
    }

    let loaded = await waitFor(timeout: 30) {
        controller.values?.count == 3
            && controller.earbudIdentityMap != nil
            && controller.lowLatency != nil
            && controller.equalizerID != nil
            && controller.doubleTapLeft != nil
            && controller.tripleTapLeft != nil
            && controller.longTapLeft != nil
            && controller.swipeAction != nil
            && controller.dualConnectEnabled != nil
            && !controller.dualConnectDevices.isEmpty
    }
    if !loaded {
        Issue.record("Live hardware state did not arrive; controller status: \(controller.status)")
    }
    #expect(loaded)

    #expect(controller.values?.count == 3)
    #expect(controller.earbudIdentityMap != nil)
    #expect(controller.lowLatency != nil)
    #expect(controller.equalizerID != nil)
    #expect(controller.doubleTapLeft != nil)
    #expect(controller.tripleTapLeft != nil)
    #expect(controller.longTapLeft != nil)
    #expect(controller.swipeAction != nil)
    #expect(controller.dualConnectEnabled != nil)
    #expect(!controller.dualConnectDevices.isEmpty)

    if let value = controller.lowLatency {
        controller.setLowLatency(value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.equalizerID {
        controller.setEqualizer(value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.doubleTapLeft {
        controller.setDoubleTap(left: true, action: value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.tripleTapLeft {
        controller.setTripleTap(left: true, action: value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.longTapLeft {
        controller.setLongTap(left: true, action: value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.swipeAction {
        controller.setSwipeAction(value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let value = controller.dualConnectEnabled {
        controller.setDualConnectEnabled(value)
        let verified = await waitForStatus(controller, "设置已由设备读回确认")
        #expect(verified)
    }
    if let device = controller.dualConnectDevices.first(where: \.autoConnect) {
        controller.setAutoConnect(device.autoConnect, device: device)
        let verified = await waitForStatus(controller, "自动连接设置已读回确认")
        #expect(verified)
    } else {
        Issue.record("A device with auto-connect enabled is needed for the no-op readback check")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FREECLIP_HARDWARE_TESTS"] == "1"))
@MainActor
func verifiesRealSettingChangesReadbackAndReconnectOnFreeClip2() async {
    let controller = Controller()
    defer { controller.stop() }

    guard let device = controller.devices.first(where: {
        ($0.name ?? "").localizedCaseInsensitiveContains("FreeClip 2")
    }) else {
        Issue.record("A paired HUAWEI FreeClip 2 is required for this hardware test")
        return
    }
    if controller.status == "选择已配对的设备" {
        controller.connect(device)
    }

    let loaded = await waitFor(timeout: 30) {
        controller.values?.count == 3
            && controller.earbudIdentityMap != nil
            && controller.lowLatency != nil
            && controller.equalizerID != nil
            && controller.equalizerOptions.count > 1
            && controller.doubleTapLeft != nil
            && controller.doubleTapRight != nil
            && controller.doubleTapOptions.count > 1
            && controller.tripleTapLeft != nil
            && controller.tripleTapRight != nil
            && controller.tripleTapOptions.count > 1
            && controller.longTapLeft != nil
            && controller.longTapRight != nil
            && controller.longTapOptions.count > 1
            && controller.swipeAction != nil
            && controller.swipeOptions.count > 1
            && controller.dualConnectEnabled != nil
            && !controller.dualConnectDevices.isEmpty
    }
    #expect(loaded)
    guard loaded else { return }

    print("HARDWARE_STATE battery=\(controller.values ?? []) identity=\(String(describing: controller.earbudIdentityMap))")
    print("HARDWARE_STATE lowLatency=\(String(describing: controller.lowLatency)) eq=\(String(describing: controller.equalizerID)) eqOptions=\(controller.equalizerOptions)")
    print("HARDWARE_STATE double=\(String(describing: controller.doubleTapLeft))/\(String(describing: controller.doubleTapRight)) options=\(controller.doubleTapOptions)")
    print("HARDWARE_STATE triple=\(String(describing: controller.tripleTapLeft))/\(String(describing: controller.tripleTapRight)) options=\(controller.tripleTapOptions)")
    print("HARDWARE_STATE long=\(String(describing: controller.longTapLeft))/\(String(describing: controller.longTapRight)) options=\(controller.longTapOptions)")
    print("HARDWARE_STATE swipe=\(String(describing: controller.swipeAction)) options=\(controller.swipeOptions)")
    print("HARDWARE_STATE dualEnabled=\(String(describing: controller.dualConnectEnabled)) devices=\(controller.dualConnectDevices.map { "\($0.name)[state=\($0.connectionState),auto=\($0.autoConnect),pref=\($0.preferred)]" })")

    if let original = controller.lowLatency {
        let altered = !original
        controller.setLowLatency(altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.lowLatency == altered)
        controller.setLowLatency(original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.lowLatency == original)
    }

    if let original = controller.equalizerID,
       let altered = controller.equalizerOptions.first(where: { $0 != original }) {
        controller.setEqualizer(altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.equalizerID == altered)
        controller.setEqualizer(original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.equalizerID == original)
    }

    if let original = controller.doubleTapLeft,
       let altered = controller.doubleTapOptions.first(where: { $0 != original }) {
        controller.setDoubleTap(left: true, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.doubleTapLeft == altered)
        controller.setDoubleTap(left: true, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.doubleTapLeft == original)
    }

    if let original = controller.doubleTapRight,
       let altered = controller.doubleTapOptions.first(where: { $0 != original }) {
        controller.setDoubleTap(left: false, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.doubleTapRight == altered)
        controller.setDoubleTap(left: false, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.doubleTapRight == original)
    }

    if let original = controller.tripleTapLeft,
       let altered = controller.tripleTapOptions.first(where: { $0 != original }) {
        controller.setTripleTap(left: true, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.tripleTapLeft == altered)
        controller.setTripleTap(left: true, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.tripleTapLeft == original)
    }

    if let original = controller.tripleTapRight,
       let altered = controller.tripleTapOptions.first(where: { $0 != original }) {
        controller.setTripleTap(left: false, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.tripleTapRight == altered)
        controller.setTripleTap(left: false, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.tripleTapRight == original)
    }

    if let original = controller.longTapLeft,
       let altered = controller.longTapOptions.first(where: { $0 != original }) {
        controller.setLongTap(left: true, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.longTapLeft == altered)
        controller.setLongTap(left: true, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.longTapLeft == original)
    }

    if let original = controller.longTapRight,
       let altered = controller.longTapOptions.first(where: { $0 != original }) {
        controller.setLongTap(left: false, action: altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.longTapRight == altered)
        controller.setLongTap(left: false, action: original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.longTapRight == original)
    }

    if let original = controller.swipeAction,
       let altered = controller.swipeOptions.first(where: { $0 != original }) {
        controller.setSwipeAction(altered)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.swipeAction == altered)
        controller.setSwipeAction(original)
        #expect(await waitForStatus(controller, "设置已由设备读回确认"))
        #expect(controller.swipeAction == original)
    }

    if let target = controller.dualConnectDevices.first {
        let original = target.autoConnect
        controller.setAutoConnect(!original, device: target)
        #expect(await waitForStatus(controller, "自动连接设置已读回确认"))
        #expect(controller.dualConnectDevices.first(where: { $0.id == target.id })?.autoConnect == !original)
        controller.setAutoConnect(original, device: target)
        #expect(await waitForStatus(controller, "自动连接设置已读回确认"))
        #expect(controller.dualConnectDevices.first(where: { $0.id == target.id })?.autoConnect == original)
    }

    controller.closeChannelForTesting()
    let disconnected = await waitFor(timeout: 5) {
        controller.values == nil
    }
    #expect(disconnected)

    let reconnected = await waitFor(timeout: 20) {
        controller.values?.count == 3 && controller.earbudIdentityMap != nil
    }
    #expect(reconnected)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FREECLIP_HARDWARE_TESTS"] == "1"))
@MainActor
func inspectsWearingAndIdentityFrames() async {
    let controller = Controller()
    defer { controller.stop() }

    guard let device = controller.devices.first(where: {
        ($0.name ?? "").localizedCaseInsensitiveContains("FreeClip 2")
    }) else {
        Issue.record("A paired HUAWEI FreeClip 2 is required for this hardware test")
        return
    }
    if controller.status == "选择已配对的设备" {
        controller.connect(device)
    }

    let loaded = await waitFor(timeout: 20) {
        controller.values?.count == 3 && controller.earbudIdentityMap != nil
    }
    #expect(loaded)

    let sortedBattery = controller.lastBatteryParameters.keys.sorted().map { key in
        "\(key): \(controller.lastBatteryParameters[key] ?? [])"
    }.joined(separator: ", ")
    print("PROBE_BATTERY_0x0108: {\(sortedBattery)}")

    let sortedInfo = controller.lastDeviceInfoParameters.keys.sorted().map { key in
        let bytes = controller.lastDeviceInfoParameters[key] ?? []
        let ascii = String(bytes: bytes, encoding: .utf8) ?? bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\(key): \(bytes) (\(ascii))"
    }.joined(separator: " | ")
    print("PROBE_INFO_0x0107: {\(sortedInfo)}")
}

@MainActor
private func waitForStatus(_ controller: Controller, _ expected: String) async -> Bool {
    await waitFor(timeout: 5) { controller.status == expected }
}

@MainActor
private func pumpMainRunLoop(until deadline: Date) {
    _ = RunLoop.main.run(mode: .default, before: deadline)
}

@MainActor
private func waitFor(timeout: TimeInterval, until condition: () -> Bool) async -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !condition(), Date() < deadline {
        pumpMainRunLoop(until: Date(timeIntervalSinceNow: 0.02))
        await Task.yield()
    }
    return condition()
}
