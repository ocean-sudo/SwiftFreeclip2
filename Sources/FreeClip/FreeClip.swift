import SwiftUI
import Combine
import ServiceManagement
@preconcurrency import IOBluetooth

@MainActor final class Controller: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate, IOBluetoothDeviceAsyncCallbacks {
    @Published var status = "未连接"
    @Published var devices: [IOBluetoothDevice] = []
    @Published var values: [UInt8]? = nil
    @Published var chargingStates: [UInt8]? = nil
    @Published var modelIdentifier: String? = nil
    @Published var earbudIdentityMap: PhysicalEarbudIdentityMap?
    @Published var lowLatency: Bool?
    @Published var equalizerID: UInt8?
    @Published var equalizerOptions: [UInt8] = []
    @Published var doubleTapLeft: Int?
    @Published var doubleTapOptions: [Int] = []
    @Published var tripleTapOptions: [Int] = []
    @Published var longTapOptions: [Int] = []
    @Published var swipeOptions: [Int] = []
    @Published var doubleTapRight: Int?
    @Published var tripleTapLeft: Int?
    @Published var tripleTapRight: Int?
    @Published var longTapLeft: Int?
    @Published var longTapRight: Int?
    @Published var swipeAction: Int?
    @Published var dualConnectEnabled: Bool?
    @Published var dualConnectDevices: [DualConnectDevice] = []
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    var leftBatteryLevel: UInt8? { BatteryReadout.leftLevel(values, chargingStates: chargingStates) }
    var rightBatteryLevel: UInt8? { BatteryReadout.rightLevel(values, chargingStates: chargingStates) }
    var caseBatteryLevel: UInt8? { BatteryReadout.caseLevel(values) }
    var permanentBuds: [PlacedBud] {
        BatteryReadout.permanentBuds(values: values, chargingStates: chargingStates, identityMap: earbudIdentityMap)
    }
    var isChannelConnected: Bool { channel?.isOpen() == true }
    private(set) var lastBatteryParameters: [UInt8: [UInt8]] = [:]
    private(set) var lastDeviceInfoParameters: [UInt8: [UInt8]] = [:]
    private var channel: IOBluetoothRFCOMMChannel?
    private var pendingSDPDevice: IOBluetoothDevice?
    private var decoder = HuaweiSPPCodec()
    private var selectedDevice: IOBluetoothDevice?
    private var reconnectTask: Task<Void, Never>?
    private var connectionState = DeviceConnectionStateMachine()
    private var batteryTimer: Timer?
    private var pendingReadbacks: [UInt16: [UInt8: Int]] = [:]
    private var pendingConnectionActions: [String: Bool] = [:]
    private var pendingAutoConnect: [String: Bool] = [:]
    private var pendingPreferredAddress: String?
    private var armedReadbacks: Set<UInt16> = []
    private var settingsRequested = false
    private var batteryRequestSent = false

    override init() {
        super.init()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        discover()
        if devices.count == 1, let device = devices.first {
            connect(device)
        }
    }
    func discover() {
        devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
            ($0.name ?? "").localizedCaseInsensitiveContains("FreeClip")
        }
        status = devices.isEmpty ? "未找到已配对的 FreeClip；请先在系统设置中配对" : "选择已配对的设备"
    }
    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        selectedDevice = nil
        pendingSDPDevice = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        let activeChannel = channel
        channel = nil
        activeChannel?.close()
        values = nil
        chargingStates = nil
        modelIdentifier = nil
        earbudIdentityMap = nil
        connectionState.reset()
        status = "未连接"
    }
    func connect(_ device: IOBluetoothDevice) {
        reconnectTask?.cancel()
        reconnectTask = nil
        selectedDevice = device
        connectionState.reset()
        beginConnection(to: device)
    }
    private func beginConnection(to device: IOBluetoothDevice) {
        connectionState.beginDiscovery()
        channel?.close()
        channel = nil
        values = nil
        chargingStates = nil
        modelIdentifier = nil
        earbudIdentityMap = nil
        settingsRequested = false
        batteryRequestSent = false
        if !device.isConnected() {
            let connectionResult = device.openConnection()
            guard connectionResult == kIOReturnSuccess else {
                status = "Bluetooth 连接失败（\(connectionResult)）"
                scheduleReconnect()
                return
            }
        }
        status = "正在查询设备服务"
        pendingSDPDevice = device
        let result = device.performSDPQuery(self)
        guard result == kIOReturnSuccess else {
            pendingSDPDevice = nil
            status = "SDP 服务查询失败（\(result)）"
            scheduleReconnect()
            return
        }
    }
    private func scheduleReconnect() {
        guard reconnectTask == nil, let device = selectedDevice else { return }
        let delay = connectionState.scheduleRetry()
        status = "连接中断，\(delay) 秒后重连"
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.beginConnection(to: device)
        }
    }
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        Task { @MainActor in self.openDiscoveredChannel(status: status) }
    }
    private func openDiscoveredChannel(status: IOReturn) {
        guard let device = pendingSDPDevice else { return }
        pendingSDPDevice = nil
        guard status == kIOReturnSuccess else {
            self.status = "SDP 服务查询失败（\(status)）"
            scheduleReconnect()
            return
        }
        let records = device.services as? [IOBluetoothSDPServiceRecord] ?? []
        var channelIDs: [BluetoothRFCOMMChannelID] = []
        for record in records {
            var channelID: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                channelIDs.append(channelID)
            }
        }
        guard channelIDs.contains(1) else {
            self.status = "SDP 未发现 RFCOMM Channel 1"
            scheduleReconnect()
            return
        }
        connectionState.beginRFCOMM()
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&opened, withChannelID: 1, delegate: self)
        guard let opened else {
            self.status = "RFCOMM Channel 1 打开失败（\(result)）"
            scheduleReconnect()
            return
        }
        channel = opened
        for _ in 0..<15 where !opened.isOpen() {
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard opened.isOpen() else {
            channel = nil
            self.status = "RFCOMM Channel 1 未打开"
            scheduleReconnect()
            return
        }
        self.status = "已连接；等待读取电量"
        connectionState.didConnect()
        refresh()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.channel?.isOpen() == true else { return }
            _ = self.sendFrame(HuaweiSPPCodec.readRequest(
                command: FreeClipCommand.deviceInfoRead,
                parameterIDs: Array(UInt8(0)..<UInt8(32))
            ))
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard self.channel?.isOpen() == true else { return }
            if !self.settingsRequested {
                self.refreshSettings()
            }
        }
    }
    func refresh() {
        if sendFrame(HuaweiSPPCodec.batteryRequest) {
            batteryRequestSent = true
        }
    }
    func reconnectSelectedOrDiscover() {
        if let selectedDevice {
            connect(selectedDevice)
        } else {
            discover()
            if devices.count == 1, let device = devices.first {
                connect(device)
            }
        }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            status = "开机启动设置失败：需从 .app 运行"
        }
    }
    func closeChannelForTesting() {
        channel?.close()
    }
    private func sendFrame(_ frame: [UInt8]) -> Bool {
        guard let channel, channel.isOpen() else { return false }
        var bytes = frame
        let result = bytes.withUnsafeMutableBytes {
            channel.writeSync($0.baseAddress, length: UInt16($0.count))
        }
        guard result == kIOReturnSuccess else {
            status = "蓝牙请求发送失败（\(result)）"
            self.channel?.close()
            self.channel = nil
            scheduleReconnect()
            return false
        }
        return true
    }
    private func refreshSettings() {
        settingsRequested = true
        dualConnectDevices = []
        let requests: [(UInt16, [UInt8])] = [
            (FreeClipCommand.lowLatency, [2]),
            (FreeClipCommand.equalizerRead, [1, 2, 3, 4, 5, 6, 7, 8]),
            (FreeClipCommand.doubleTapRead, [1, 2]),
            (FreeClipCommand.tripleTapRead, [1, 2]),
            (FreeClipCommand.longTapRead, [1, 2]),
            (FreeClipCommand.swipeRead, [1, 2]),
            (FreeClipCommand.dualConnectEnabledRead, [1]),
            (FreeClipCommand.dualConnectEnumerate, [1])
        ]
        Task { @MainActor [weak self] in
            for (command, parameters) in requests {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, self.channel?.isOpen() == true else { return }
                let frame = HuaweiSPPCodec.readRequest(command: command, parameterIDs: parameters)
                guard self.sendFrame(frame) else { return }
            }
        }
    }
    func setLowLatency(_ enabled: Bool) {
        writeAndVerify(
            writeCommand: FreeClipCommand.lowLatency,
            writeParameters: [1: [enabled ? 1 : 0]],
            readCommand: FreeClipCommand.lowLatency,
            readParameters: [2],
            expected: [2: enabled ? 1 : 0]
        )
    }
    func setEqualizer(_ preset: UInt8) {
        writeAndVerify(
            writeCommand: FreeClipCommand.equalizerWrite,
            writeParameters: [1: [preset]],
            readCommand: FreeClipCommand.equalizerRead,
            readParameters: [1, 2, 3, 4, 5, 6, 7, 8],
            expected: [2: Int(preset)]
        )
    }
    func setDoubleTap(left: Bool, action: Int) {
        setGesture(action, parameter: left ? 1 : 2,
                   writeCommand: FreeClipCommand.doubleTapWrite,
                   readCommand: FreeClipCommand.doubleTapRead)
    }
    func setTripleTap(left: Bool, action: Int) {
        setGesture(action, parameter: left ? 1 : 2,
                   writeCommand: FreeClipCommand.tripleTapWrite,
                   readCommand: FreeClipCommand.tripleTapRead)
    }
    func setLongTap(left: Bool, action: Int) {
        setGesture(action, parameter: left ? 1 : 2,
                   writeCommand: FreeClipCommand.longTapWrite,
                   readCommand: FreeClipCommand.longTapRead)
    }
    func setSwipeAction(_ action: Int) {
        let value = UInt8(truncatingIfNeeded: action)
        writeAndVerify(
            writeCommand: FreeClipCommand.swipeWrite,
            writeParameters: [1: [value], 2: [value]],
            readCommand: FreeClipCommand.swipeRead,
            readParameters: [1, 2],
            expected: [1: action, 2: action]
        )
    }
    private func setGesture(_ action: Int, parameter: UInt8, writeCommand: UInt16, readCommand: UInt16) {
        writeAndVerify(
            writeCommand: writeCommand,
            writeParameters: [parameter: [UInt8(truncatingIfNeeded: action)]],
            readCommand: readCommand,
            readParameters: [1, 2],
            expected: [parameter: action]
        )
    }
    private func writeAndVerify(
        writeCommand: UInt16,
        writeParameters: [UInt8: [UInt8]],
        readCommand: UInt16,
        readParameters: [UInt8],
        expected: [UInt8: Int]
    ) {
        let write = HuaweiSPPCodec.writeRequest(command: writeCommand, parameters: writeParameters)
        guard sendFrame(write) else { return }
        pendingReadbacks[readCommand] = expected
        armedReadbacks.remove(readCommand)
        status = "已发送设置，等待设备读回"
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard let self, self.pendingReadbacks[readCommand] == expected else { return }
            self.armedReadbacks.insert(readCommand)
            let read = HuaweiSPPCodec.readRequest(command: readCommand, parameterIDs: readParameters)
            guard self.sendFrame(read) else {
                self.pendingReadbacks[readCommand] = nil
                self.armedReadbacks.remove(readCommand)
                return
            }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.pendingReadbacks[readCommand] == expected {
                self.pendingReadbacks[readCommand] = nil
                self.armedReadbacks.remove(readCommand)
                self.status = "未收到设置读回验证"
            }
        }
    }
    func setDualConnectEnabled(_ enabled: Bool) {
        writeAndVerify(
            writeCommand: FreeClipCommand.dualConnectEnabledWrite,
            writeParameters: [1: [enabled ? 1 : 0]],
            readCommand: FreeClipCommand.dualConnectEnabledRead,
            readParameters: [1],
            expected: [1: enabled ? 1 : 0]
        )
    }
    func refreshDualConnections() {
        dualConnectDevices = []
        let request = HuaweiSPPCodec.readRequest(
            command: FreeClipCommand.dualConnectEnumerate, parameterIDs: [1]
        )
        _ = sendFrame(request)
    }
    func setPreferredDevice(_ device: DualConnectDevice) {
        pendingPreferredAddress = device.id
        status = "等待首选设备读回验证"
        let frame = HuaweiSPPCodec.writeRequest(
            command: FreeClipCommand.dualConnectPreferredWrite,
            parameters: [1: device.address]
        )
        guard sendFrame(frame) else { return }
        refreshAfterDeviceChange(address: device.id)
    }
    func setConnected(_ connected: Bool, device: DualConnectDevice) {
        pendingConnectionActions[device.id] = connected
        status = "等待双设备连接状态读回"
        let commandID: UInt8 = connected ? 1 : 2
        let frame = HuaweiSPPCodec.writeRequest(
            command: FreeClipCommand.dualConnectExecute,
            parameters: [commandID: device.address]
        )
        guard sendFrame(frame) else { return }
        refreshAfterDeviceChange(address: device.id)
    }
    func setAutoConnect(_ enabled: Bool, device: DualConnectDevice) {
        pendingAutoConnect[device.id] = enabled
        status = "等待自动连接设置读回"
        let commandID: UInt8 = enabled ? 4 : 5
        let frame = HuaweiSPPCodec.writeRequest(
            command: FreeClipCommand.dualConnectExecute,
            parameters: [commandID: device.address]
        )
        guard sendFrame(frame) else { return }
        refreshAfterDeviceChange(address: device.id)
    }
    private func refreshAfterDeviceChange(address: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self else { return }
            self.refreshDualConnections()
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.pendingPreferredAddress == address {
                self.pendingPreferredAddress = nil
                self.status = "首选设备读回验证失败"
            } else if self.pendingConnectionActions[address] != nil {
                self.pendingConnectionActions[address] = nil
                self.status = "双设备连接状态读回验证失败"
            } else if self.pendingAutoConnect[address] != nil {
                self.pendingAutoConnect[address] = nil
                self.status = "自动连接设置读回验证失败"
            }
        }
    }
    nonisolated func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: length))
        Task { @MainActor in self.receive(bytes) }
    }
    nonisolated func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        Task { @MainActor in
            self.channel = nil
            self.earbudIdentityMap = nil
            self.connectionState.didDisconnect()
            self.values = nil
            self.chargingStates = nil
            self.modelIdentifier = nil
            self.status = "连接已断开"
            self.scheduleReconnect()
        }
    }
    private func receive(_ bytes: [UInt8]) {
        for message in decoder.receive(bytes) {
            switch message.command {
            case FreeClipCommand.batteryRead:
                lastBatteryParameters = message.parameters
                if let battery = message.parameters[2], battery.count == 3 {
                    let previousCharging = chargingStates
                    values = battery
                    chargingStates = message.parameters[3]
                    status = "已收到电量与佩戴状态"
                    if previousCharging != chargingStates {
                        _ = sendFrame(HuaweiSPPCodec.readRequest(
                            command: FreeClipCommand.deviceInfoRead,
                            parameterIDs: Array(UInt8(0)..<UInt8(32))
                        ))
                    }
                }
            case FreeClipCommand.deviceInfoRead:
                lastDeviceInfoParameters = message.parameters
                if let modelBytes = message.parameters[15],
                   let model = String(bytes: modelBytes, encoding: .utf8),
                   !model.isEmpty {
                    modelIdentifier = model
                }
                if let identityBytes = message.parameters[24] {
                    earbudIdentityMap = PhysicalEarbudIdentityMap.decode(identityBytes)
                    status = earbudIdentityMap == nil
                        ? "耳机身份字段无法解析"
                        : "已连接 · 左右自适应映射"
                }
                if !batteryRequestSent {
                    refresh()
                }
            case FreeClipCommand.lowLatency:
                if let value = message.parameters[2]?.first {
                    lowLatency = value == 1
                }
            case FreeClipCommand.equalizerRead:
                if let value = message.parameters[2]?.first {
                    equalizerID = value
                }
                equalizerOptions = message.parameters[3] ?? []
            case FreeClipCommand.doubleTapRead:
                doubleTapLeft = signedParameter(1, in: message)
                doubleTapRight = signedParameter(2, in: message)
                doubleTapOptions = actionOptions(in: message)
            case FreeClipCommand.tripleTapRead:
                tripleTapLeft = signedParameter(1, in: message)
                tripleTapRight = signedParameter(2, in: message)
                tripleTapOptions = actionOptions(in: message)
            case FreeClipCommand.longTapRead:
                longTapLeft = signedParameter(1, in: message)
                longTapRight = signedParameter(2, in: message)
                longTapOptions = actionOptions(in: message)
            case FreeClipCommand.swipeRead:
                swipeAction = signedParameter(1, in: message)
                swipeOptions = actionOptions(in: message)
            case FreeClipCommand.dualConnectEnabledRead:
                if let value = message.parameters[1]?.first {
                    dualConnectEnabled = value == 1
                }
            case FreeClipCommand.dualConnectEnumerate:
                receiveDualConnectDevice(message)
            default:
                break
            }
            verifyReadback(message)
        }
    }
    private func actionOptions(in message: HuaweiSPPMessage) -> [Int] {
        (message.parameters[3] ?? []).map { Int(Int8(bitPattern: $0)) }
    }
    private func signedParameter(_ id: UInt8, in message: HuaweiSPPMessage) -> Int? {
        guard let value = message.parameters[id], value.count == 1 else { return nil }
        return Int(Int8(bitPattern: value[0]))
    }
    private func verifyReadback(_ message: HuaweiSPPMessage) {
        guard armedReadbacks.contains(message.command),
              let expected = pendingReadbacks[message.command],
              expected.keys.allSatisfy({ message.parameters[$0]?.count == 1 }) else { return }
        let matches = expected.allSatisfy { key, value in
            message.parameters[key]?.first.map { Int(Int8(bitPattern: $0)) } == value
        }
        pendingReadbacks[message.command] = nil
        armedReadbacks.remove(message.command)
        status = matches ? "设置已由设备读回确认" : "设备读回与设置不符"
    }
    private func receiveDualConnectDevice(_ message: HuaweiSPPMessage) {
        guard let address = message.parameters[4], address.count == 6,
              let connectionState = message.parameters[5]?.first else { return }
        let id = address.map { String(format: "%02X", $0) }.joined()
        let name = String(decoding: message.parameters[9] ?? [], as: UTF8.self)
        let device = DualConnectDevice(
            address: address,
            name: name.isEmpty ? "未知设备" : name,
            connectionState: connectionState,
            autoConnect: message.parameters[8]?.first == 1,
            preferred: message.parameters[7]?.first == 1
        )
        dualConnectDevices.removeAll { $0.id == id }
        dualConnectDevices.append(device)
        if pendingPreferredAddress == id && device.preferred {
            pendingPreferredAddress = nil
            status = "首选设备已读回确认"
        }
        if let expected = pendingConnectionActions[id], expected == device.isConnected {
            pendingConnectionActions[id] = nil
            status = "双设备连接状态已读回确认"
        }
        if let expected = pendingAutoConnect[id], expected == device.autoConnect {
            pendingAutoConnect[id] = nil
            status = "自动连接设置已读回确认"
        }
    }
    var menuBarTitle: String {
        BatteryReadout.lowestReportedEarLevel(values)
            .map { "\($0)%" } ?? ""
    }
}

@main
enum FreeClipMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = StatusBarAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var titleCancellable: AnyCancellable?
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = FreeClipStatusIcon.templateImage()
            button.imagePosition = .imageLeading
            button.title = controller.menuBarTitle.isEmpty ? "" : " \(controller.menuBarTitle)"
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item

        titleCancellable = controller.$values.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self, let button = self.statusItem?.button else { return }
            let title = self.controller.menuBarTitle
            button.title = title.isEmpty ? "" : " \(title)"
        }
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }
        let panel = ensurePanel()
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        var x = round(buttonRect.midX - panelSize.width / 2)
        if let visibleFrame = buttonWindow.screen?.visibleFrame {
            x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - panelSize.width - 8)
        }
        let origin = NSPoint(x: x, y: round(buttonRect.minY - panelSize.height - 6))
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startOutsideClickMonitor()
    }

    private func closePanel() {
        panel?.orderOut(nil)
        stopOutsideClickMonitor()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hostingView = NSHostingView(rootView: FreeClipMenuView(controller: controller))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = TransparentPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 490),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}

private final class TransparentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
