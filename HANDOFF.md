# FreeClip 2 项目交接

## 目标与约束

开发原生 macOS 菜单栏应用，使用 Swift 6、SwiftUI、IOBluetooth，Bluetooth Classic RFCOMM/SPP Channel 1；支持 Apple Silicon，不使用 Electron、WebView、Python、Rust 或常驻外部服务。按优先级完成：

1. **M1**：发现已配对的 FreeClip 2，建立 RFCOMM，收发真实协议帧，读取并显示电量，断线恢复。
2. **M2**：EQ、手势、低延迟、双设备管理真实读写，并以设备读回验证设置。
3. **M3**：验证物理耳机身份与实际佩戴位置的映射，固定显示左耳、右耳、充电盒；无法确认的左右状态显示未知。完成测试和可运行的 `.app`。

用户希望 agent 自主调试，已经授予蓝牙权限；需要真实硬件验证，不能用模拟 UI 或纯逻辑测试替代。参考项目与许可证见 `PROTOCOL_RESEARCH.md`；FreeBuds Kontrol 针对另一型号，不可直接视为 FreeClip 2 的兼容性证据。

## 已实现，不等于全部已验收

- `Sources/FreeClip/FreeClip.swift`：已配对设备发现、SDP、RFCOMM Channel 1、发送与接收、重连、定时电量请求，以及 SwiftUI `MenuBarExtra`。EQ、手势、低延迟和双设备管理已有设备命令及读回路径。
- `Sources/FreeClip/Protocol/`：SPP 帧编解码和 CRC、电量解析、连接状态和退避策略、设备身份字段和控制命令。
- `build-app.sh`：构建 `.build/FreeClip.app`，按 `org.freeclip.FreeClip2` 的稳定 designated requirement 做 ad-hoc 签名。包此前已成功构建、验证为 arm64，并启动；菜单栏显示耳机图标。其签名不是公证或 Developer ID 发布签名。
- `Tests/FreeClipTests/`：纯逻辑测试已迁移到 Swift Testing；`Tests/FreeClipHardwareTests/` 是显式 opt-in 的真实设备集成测试。
- 设备信息 `0x0107` 参数 24 曾返回 `L-…` / `R-…` 序列号标签，但未证明互换佩戴后标签、实际位置和电量字段的对应关系。当前 UI 将左右区域显示为未知；充电盒使用上游定义的第三个电量字段。不要把静态 L/R 标签当成已验证的动态佩戴位置。

## 最近验证与当前阻塞

- 最近一次 `./test-swift-testing.sh`：10 项纯逻辑 Swift Testing 测试通过；硬件测试默认跳过。`./test-protocol.sh` 的协议与状态烟测通过。
- 本机缺少 XCTest，且裸 `swift test --disable-xctest` 无法找到 `TestingMacros`。`test-swift-testing.sh` 从当前 Command Line Tools 路径显式加载宏插件，并调用 `swift test --disable-xctest`。测试链接器提示本机 Testing framework 目标版本为 macOS 14；这不改变 app 自身的 macOS 13 最低目标。
- 之前真实设备曾返回 CRC 正确的三字段电量帧；曾观察到 RFCOMM 关闭后重连并再次收到电量。一轮硬件测试曾读取设置并对多个设置写入原值、读回成功。详见 `PROTOCOL_RESEARCH.md`。这些是历史观察，**干净构建后目前不可复现**，不能当作当前验收通过。
- 最近真实设备测试打开 Channel 1 后 30 秒超时，状态为 `已连接；等待读取电量`；没有收到电量、身份或设置响应。macOS 日志显示 RFCOMM 打开成功、输出流有空间，但没有入站数据事件；这不能证明设备收到了请求。TCC 日志显示 app 和测试进程蓝牙授权允许。
- 已尝试在硬件测试等待期间泵送主 `NSRunLoop`，以及在启动时先请求电量再请求设备信息；均未恢复回应。根因未知。当前代码仍保留这些调整；应基于证据决定是否保留。
- 最后一次尝试重建底层蓝牙连接的命令**被中断**，没有获得结果。命令先请求退出 app，再尝试关闭并重新打开耳机连接，因此当前 app 和蓝牙连接状态需重新检查；不能假定连接已恢复。未执行解除配对。

## 下一步

1. 先检查 app 进程、耳机连接状态和是否存在其他占用 SPP 的应用。以 `FREECLIP_HARDWARE_TESTS=1 ./test-swift-testing.sh --filter readsBatteryAndPhysicalEarbudIdentityFromFreeClip2` 作为真实设备反馈；先退出菜单栏 app，避免同时占用通道。该测试会对部分设置写入**当前值**并请求读回，仍属于实际设备写操作。
2. 定位无回包的原因，区分主机写入、蓝牙链路和设备响应；不要靠伪造数据或屏蔽超时使测试通过。必要时重建蓝牙连接会短暂打断音频，但不要解除配对或改动用户配对记录。修复后验证真实电量帧、断线恢复和 app 界面。
3. 验证 M2 各项的真实改变和读回，包括双设备状态；历史的原值写回不证明所有控制可用。连接/断开设备及首选设备切换尚未测试，操作会影响用户设备，注意恢复原状态。
4. 通过协议证据和真实换戴实验确定物理身份与当前左右佩戴位置的关系；无法确定继续显示未知。不要把合成数据测试当成硬件证据。
5. 运行 Swift Testing、协议烟测，重建并实际启动 `.app`；说明测试范围、硬件结果及发布签名/公证状态。`PROTOCOL_RESEARCH.md` 保存协议来源与历史证据，新的结论应更新该文件。

## 给下一位 agent 的提示

先阅读现有 `AGENTS.md` 和 `PROTOCOL_RESEARCH.md`，以当前文件和实际运行结果为准。本交接是阶段快照，不是长期仓库规则。用户没有要求提交；保留现有未提交工作。
