import Foundation

enum FreeClipCommand {
    static let batteryRead: UInt16 = 0x0108
    static let deviceInfoRead: UInt16 = 0x0107
    static let doubleTapRead: UInt16 = 0x0120
    static let doubleTapWrite: UInt16 = 0x011F
    static let tripleTapRead: UInt16 = 0x0126
    static let tripleTapWrite: UInt16 = 0x0125
    static let longTapRead: UInt16 = 0x2B17
    static let longTapWrite: UInt16 = 0x2B16
    static let swipeRead: UInt16 = 0x2B1F
    static let swipeWrite: UInt16 = 0x2B1E
    static let equalizerRead: UInt16 = 0x2B4A
    static let equalizerWrite: UInt16 = 0x2B49
    static let lowLatency: UInt16 = 0x2B6C
    static let dualConnectEnabledRead: UInt16 = 0x2B2F
    static let dualConnectEnabledWrite: UInt16 = 0x2B2E
    static let dualConnectEnumerate: UInt16 = 0x2B31
    static let dualConnectPreferredWrite: UInt16 = 0x2B32
    static let dualConnectExecute: UInt16 = 0x2B33
}

enum EqualizerPreset: UInt8 {
    case defaultSound = 1
    case bass = 2
    case treble = 3
    case voice = 9

    var title: String {
        switch self {
        case .defaultSound: "默认"
        case .bass: "重低音"
        case .treble: "高音"
        case .voice: "人声"
        }
    }
    static func title(for id: UInt8) -> String {
        EqualizerPreset(rawValue: id)?.title ?? "设备预设 \(id)"
    }
}

enum FreeClipAction: Int {
    case off = -1
    case assistant = 0
    case pause = 1
    case next = 2
    case previous = 7
    case volumeUp = 18
    case volumeDown = 19

    var title: String {
        switch self {
        case .off: "关闭"
        case .assistant: "语音助手"
        case .pause: "播放/暂停"
        case .next: "下一首"
        case .previous: "上一首"
        case .volumeUp: "增大音量"
        case .volumeDown: "减小音量"
        }
    }
    static func title(for code: Int) -> String {
        FreeClipAction(rawValue: code)?.title ?? "设备动作 \(code)"
    }

}

struct DualConnectDevice: Identifiable, Equatable {
    let address: [UInt8]
    let name: String
    let connectionState: UInt8
    let autoConnect: Bool
    let preferred: Bool

    var id: String { address.map { String(format: "%02X", $0) }.joined() }
    var isConnected: Bool { connectionState > 0 }
    var isPlaying: Bool { connectionState == 9 }
}
