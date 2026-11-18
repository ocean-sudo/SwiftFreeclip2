import SwiftUI
@preconcurrency import IOBluetooth

private enum PopoverTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case gestures = "手势"
    case devices = "设备"

    var id: String { rawValue }
}

private final class TabSelection: ObservableObject {
    @Published var tab: PopoverTab = .overview
}

struct FreeClipMenuView: View {
    @ObservedObject var controller: Controller
    @StateObject private var selection = TabSelection()

    var body: some View {
        VStack(spacing: 10) {
            headerSection

            Picker("", selection: $selection.tab) {
                ForEach(PopoverTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    switch selection.tab {
                    case .overview:
                        overviewTab
                    case .gestures:
                        gesturesTab
                    case .devices:
                        devicesTab
                    }
                }
                .padding(.vertical, 2)
            }
            .clipped()

            footerSection
        }
        .padding(14)
        .frame(width: 380, height: 490)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Header & Footer

    private var headerSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(controller.isChannelConnected ? Color.white : Color.primary.opacity(0.12))
                        .frame(width: 34, height: 34)
                    FreeClipIconView()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(controller.isChannelConnected ? statusColor : .secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("FreeClip 2")
                            .font(.subheadline.weight(.semibold))
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(controller.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .liquidGlass(in: Capsule())

            Button {
                if controller.isChannelConnected {
                    controller.refresh()
                } else {
                    controller.reconnectSelectedOrDiscover()
                }
            } label: {
                Image(systemName: controller.isChannelConnected ? "arrow.clockwise" : "bolt.horizontal.circle")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .liquidGlass(in: Circle(), interactive: true)
            .help(controller.isChannelConnected ? "刷新电量与状态" : "重新连接耳机")
        }
    }

    private var statusColor: Color {
        if controller.isChannelConnected {
            return controller.values != nil ? Color(red: 0.16, green: 0.68, blue: 0.34) : Color(red: 0.92, green: 0.55, blue: 0.12)
        }
        return .secondary
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            if !controller.isChannelConnected {
                Button {
                    controller.reconnectSelectedOrDiscover()
                } label: {
                    Label("重新连接", systemImage: "bolt.horizontal.circle.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .liquidGlass(in: Capsule(), interactive: true, tint: .accentColor)
            }

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .liquidGlass(in: Capsule(), interactive: true)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            let buds = controller.permanentBuds
            HStack(spacing: 8) {
                ForEach(buds, id: \.id) { bud in
                    budCard(bud)
                }
                caseCard(
                    level: controller.caseBatteryLevel,
                    isCharging: (controller.chargingStates?.count ?? 0) >= 3 && controller.chargingStates?[2] == 1
                )
            }

            HStack(spacing: 8) {
                controlTile(
                    title: "低延迟",
                    subtitle: controller.lowLatency.map { $0 ? "已开启" : "已关闭" } ?? "未读取",
                    symbol: "bolt.fill",
                    isActive: controller.lowLatency == true,
                    isDisabled: controller.lowLatency == nil
                ) {
                    if let current = controller.lowLatency {
                        controller.setLowLatency(!current)
                    }
                }

                controlTile(
                    title: "双设备",
                    subtitle: controller.dualConnectEnabled.map { $0 ? "已开启" : "已关闭" } ?? "未读取",
                    symbol: "laptopcomputer.and.iphone",
                    isActive: controller.dualConnectEnabled == true,
                    isDisabled: controller.dualConnectEnabled == nil
                ) {
                    if let current = controller.dualConnectEnabled {
                        controller.setDualConnectEnabled(!current)
                    }
                }
            }

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(controller.equalizerID == nil ? 0.25 : 0.92))
                        .frame(width: 30, height: 30)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("EQ 音效")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Picker("", selection: Binding(
                    get: { Int(controller.equalizerID ?? 0) },
                    set: { controller.setEqualizer(UInt8($0)) }
                )) {
                    ForEach(controller.equalizerOptions, id: \.self) { presetID in
                        Text(EqualizerPreset.title(for: presetID)).tag(Int(presetID))
                    }
                }
                .labelsHidden()
                .frame(width: 135)
                .disabled(controller.equalizerID == nil || controller.equalizerOptions.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .liquidGlass(in: Capsule())

            if !controller.dualConnectDevices.isEmpty {
                glassCard(title: "当前连接设备", systemImage: "dot.radiowaves.left.and.right") {
                    VStack(spacing: 8) {
                        ForEach(controller.dualConnectDevices) { device in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(device.isConnected ? Color.white.opacity(0.92) : Color.primary.opacity(0.1))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: deviceSymbol(for: device.name))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(device.isPlaying ? Color(red: 0.16, green: 0.68, blue: 0.34) : (device.isConnected ? Color.accentColor : Color.secondary))
                                }

                                Text(device.name)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Text(deviceStatusText(device))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(device.isPlaying ? .green : (device.isConnected ? .primary : .secondary))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(
                                        (device.isPlaying ? Color.green : Color.primary).opacity(0.1),
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func controlTile(
        title: String,
        subtitle: String,
        symbol: String,
        isActive: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : Color.primary.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .liquidGlass(in: Capsule(), interactive: !isDisabled)
    }

    private func budCard(_ bud: PlacedBud) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(bud.level == nil ? Color.primary.opacity(0.1) : Color.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                    if bud.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(bud.level == nil ? Color.secondary : batteryColor(for: bud.level ?? 0))
                    } else {
                        FreeClipIconView()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(bud.level == nil ? Color.secondary : batteryColor(for: bud.level ?? 0))
                    }
                }
                Spacer(minLength: 2)
                placementBadge(bud.placement)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("耳机 \(bud.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(bud.level.map(displayBattery) ?? "未知")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(bud.level == nil ? .secondary : .primary)
            }

            progressBar(level: bud.level)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func caseCard(level: UInt8?, isCharging: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(level == nil ? Color.primary.opacity(0.1) : Color.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                    Image(systemName: NSImage(systemSymbolName: "case", accessibilityDescription: nil) != nil ? "case" : "battery.100")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(level == nil ? Color.secondary : batteryColor(for: level ?? 0))
                }
                Spacer(minLength: 2)
                if isCharging {
                    Text("充电中")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(red: 0.16, green: 0.68, blue: 0.34))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.16, green: 0.68, blue: 0.34).opacity(0.14), in: Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("充电盒")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(level.map(displayBattery) ?? "未知")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(level == nil ? .secondary : .primary)
            }

            progressBar(level: level)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func placementBadge(_ placement: BudPlacement) -> some View {
        let color: Color = switch placement {
        case .left, .right: Color.accentColor
        case .inCase: Color(red: 0.16, green: 0.68, blue: 0.34)
        case .unknown: Color.secondary
        }
        return Text(placement.title)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func progressBar(level: UInt8?) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.12))
                if let level, level > 0, level <= 100 {
                    Capsule()
                        .fill(batteryColor(for: level))
                        .frame(width: max(4, proxy.size.width * CGFloat(level) / 100.0))
                }
            }
        }
        .frame(height: 5)
    }

    // MARK: - Gestures Tab

    private var gesturesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            glassCard(title: "双击", systemImage: "hand.tap") {
                VStack(spacing: 8) {
                    gestureRow("左耳", value: controller.doubleTapLeft, options: controller.doubleTapOptions) {
                        controller.setDoubleTap(left: true, action: $0)
                    }
                    Divider().opacity(0.35)
                    gestureRow("右耳", value: controller.doubleTapRight, options: controller.doubleTapOptions) {
                        controller.setDoubleTap(left: false, action: $0)
                    }
                }
            }

            glassCard(title: "三击", systemImage: "hand.tap.fill") {
                VStack(spacing: 8) {
                    gestureRow("左耳", value: controller.tripleTapLeft, options: controller.tripleTapOptions) {
                        controller.setTripleTap(left: true, action: $0)
                    }
                    Divider().opacity(0.35)
                    gestureRow("右耳", value: controller.tripleTapRight, options: controller.tripleTapOptions) {
                        controller.setTripleTap(left: false, action: $0)
                    }
                }
            }

            glassCard(title: "长按", systemImage: "hand.point.up.left") {
                VStack(spacing: 8) {
                    gestureRow("左耳", value: controller.longTapLeft, options: controller.longTapOptions) {
                        controller.setLongTap(left: true, action: $0)
                    }
                    Divider().opacity(0.35)
                    gestureRow("右耳", value: controller.longTapRight, options: controller.longTapOptions) {
                        controller.setLongTap(left: false, action: $0)
                    }
                }
            }

            glassCard(title: "滑动", systemImage: "hand.draw") {
                gestureRow(
                    "双耳滑动",
                    value: controller.swipeAction,
                    options: controller.swipeOptions,
                    titles: [-1: "关闭", 0: "滑动调节音量"]
                ) {
                    controller.setSwipeAction($0)
                }
            }
        }
    }

    private func gestureRow(
        _ title: String,
        value: Int?,
        options: [Int],
        titles: [Int: String] = [:],
        onChange: @escaping @MainActor @Sendable (Int) -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Picker("", selection: Binding(
                get: { value ?? Int.min },
                set: onChange
            )) {
                ForEach(options, id: \.self) { action in
                    Text(titles[action] ?? FreeClipAction.title(for: action)).tag(action)
                }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(value == nil || options.isEmpty)
        }
    }

    // MARK: - Devices Tab

    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            glassCard(title: "双设备连接", systemImage: "laptopcomputer.and.iphone") {
                VStack(spacing: 10) {
                    HStack {
                        Toggle("启用双设备连接", isOn: Binding(
                            get: { controller.dualConnectEnabled ?? false },
                            set: controller.setDualConnectEnabled
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.subheadline)
                        .disabled(controller.dualConnectEnabled == nil)

                        Spacer()

                        Button("刷新") {
                            controller.refreshDualConnections()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if controller.dualConnectDevices.isEmpty {
                        Text("暂无已枚举的双设备记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(controller.dualConnectDevices) { device in
                            dualConnectDeviceRow(device)
                        }
                    }
                }
            }

            glassCard(title: "已配对蓝牙设备", systemImage: "bluetooth") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("系统已配对的 FreeClip 设备")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("查找") {
                            controller.discover()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if controller.devices.isEmpty {
                        Text("未找到已配对的 FreeClip；请先在系统设置中配对")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.devices, id: \.addressString) { device in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.9))
                                        .frame(width: 28, height: 28)
                                    FreeClipIconView()
                                        .frame(width: 16, height: 16)
                                        .foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name ?? "未知设备")
                                        .font(.subheadline)
                                    Text(device.addressString ?? "")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("连接") {
                                    controller.connect(device)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private func dualConnectDeviceRow(_ device: DualConnectDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(device.isConnected ? Color.white.opacity(0.92) : Color.primary.opacity(0.1))
                        .frame(width: 28, height: 28)
                    Image(systemName: deviceSymbol(for: device.name))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(device.isPlaying ? Color(red: 0.16, green: 0.68, blue: 0.34) : (device.isConnected ? Color.accentColor : Color.secondary))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(deviceStatusText(device))
                        .font(.caption2)
                        .foregroundStyle(device.isPlaying ? .green : .secondary)
                }
                Spacer()
                if device.preferred {
                    Label("首选", systemImage: "star.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Toggle("自动连接", isOn: Binding(
                    get: { device.autoConnect },
                    set: { controller.setAutoConnect($0, device: device) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.caption)

                Spacer()

                if !device.preferred {
                    Button("设为首选") {
                        controller.setPreferredDevice(device)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                Button(device.isConnected ? "断开" : "连接") {
                    controller.setConnected(!device.isConnected, device: device)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Helpers

    private func glassCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func displayBattery(_ value: UInt8) -> String {
        value > 0 && value <= 100 ? "\(value)%" : "未知"
    }

    private func batteryColor(for value: UInt8) -> Color {
        if value <= 15 { return Color(red: 0.90, green: 0.24, blue: 0.24) }
        if value <= 30 { return Color(red: 0.92, green: 0.55, blue: 0.12) }
        return Color(red: 0.16, green: 0.68, blue: 0.34)
    }

    private func deviceStatusText(_ device: DualConnectDevice) -> String {
        device.isPlaying ? "正在播放" : device.isConnected ? "已连接" : "未连接"
    }

    private func deviceSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("mac") || lower.contains("book") { return "laptopcomputer" }
        if lower.contains("ipad") || lower.contains("pad") { return "ipad" }
        if lower.contains("iphone") || lower.contains("find") || lower.contains("phone") { return "iphone" }
        return "desktopcomputer"
    }
}

private extension View {
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            let base = tint.map { Glass.clear.tint($0) } ?? Glass.clear
            let glass = interactive ? base.interactive() : base
            self.glassEffect(glass, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.75))
        }
    }
}
