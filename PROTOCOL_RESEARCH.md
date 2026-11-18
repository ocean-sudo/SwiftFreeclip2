# FreeClip 2 protocol evidence

Research date: 2026-11-15

## Confirmed by upstream source (not independently verified on hardware)

- OpenFreebuds documents **HUAWEI FreeClip 2 (BTFT0027)** with Huawei SPP on port 1 and a dedicated `OfbDriverHuaweiFreeClip2` implementation. The driver source sets `_spp_service_port = 1`.
  - [Device support](https://github.com/melianmiko/OpenFreebuds/blob/main/docs/devices/HUAWEI_FreeClip_2.md)
  - [FreeClip 2 driver](https://github.com/melianmiko/OpenFreebuds/blob/main/openfreebuds/driver/huawei/driver/per_model/free_clip_2.py)
- Its battery handler requests parameters `[1, 2, 3]`. Parameter 1 is an aggregate level; parameter 2 is interpreted as left/right/case levels when it contains three bytes and TWS is enabled; parameter 3 is charging state.
  - [Battery handler](https://github.com/melianmiko/OpenFreebuds/blob/main/openfreebuds/driver/huawei/handler/battery.py)
  - The battery handler assigns parameter-2 bytes in left/right/case order. The device-info handler reads command `0x0107` and parses parameter 24 as `L-<serial>,R-<serial>`. Neither establishes that these labels follow the actual worn position after the earbuds are swapped. The app therefore keeps both worn-side areas unknown until that relationship is verified.
  - [Info handler](https://github.com/melianmiko/OpenFreebuds/blob/main/openfreebuds/driver/huawei/handler/info.py)
- FreeBuds Kontrol is a native Swift macOS app using RFCOMM/SPP, but documents support only for FreeBuds SE 4 ANC (BTFT0026); it explicitly says other models are unsupported. Its architecture must not be taken as evidence of FreeClip 2 compatibility.
  - [README](https://github.com/hikmetozcann/freebuds-kontrol/blob/main/README.md)
  - [Architecture](https://github.com/hikmetozcann/freebuds-kontrol/blob/main/docs/ARCHITECTURE.md)
  - [Validation scope](https://github.com/hikmetozcann/freebuds-kontrol/blob/main/docs/VALIDATION.md)

## License

OpenFreebuds identifies its license as GPL-3.0. FreeBuds Kontrol identifies GPL-3.0-only and describes its transport/interface as original work informed by OpenFreebuds. This implementation does not copy their source; any future reuse of code must retain the applicable license obligations.

- [OpenFreebuds LICENSE](https://github.com/melianmiko/OpenFreebuds/blob/main/LICENSE)
- [Kontrol LICENSE](https://github.com/hikmetozcann/freebuds-kontrol/blob/main/LICENSE)
- [Kontrol NOTICE](https://github.com/hikmetozcann/freebuds-kontrol/blob/main/NOTICE.md)

## Hardware probe

On the user's Mac, IOBluetooth enumerated a paired device named `HUAWEI FreeClip 2`; the app resolved SDP, found RFCOMM/SPP channel 1, and opened it. The model designation BTFT0027 remains inferred from the name; the device identifier was not independently queried.

The app sent battery request `0x0108` and received checksum-valid three-byte parameter-2 responses (for example, `[33, 26, 76]` and `[61, 23, 100]`). The third field is interpreted as the case level; the first two are not assigned to worn sides without further evidence.

An app-triggered RFCOMM close caused the delegate's close callback, SDP discovery reran, channel 1 reopened, and another battery response arrived. This verifies the reconnect path on hardware.

The hardware integration test read low-latency state, EQ and advertised presets `[1, 10, 3, 9]`, double/triple/long-tap, swipe, dual-connect enablement, and the enumerated paired-device list. It then wrote each existing value unchanged and verified readback, including auto-connect for a device already enabled. Connecting/disconnecting devices and changing the preferred device remain untested to avoid disrupting the user's pairings.

The opt-in Swift Testing hardware test is run with `FREECLIP_HARDWARE_TESTS=1 ./test-swift-testing.sh --filter readsBatteryAndPhysicalEarbudIdentityFromFreeClip2`. Earlier runs after a clean rebuild timed out without response callbacks, likely due to a stale Bluetooth/RFCOMM session. After clearing the stale connection, both `readsBatteryAndPhysicalEarbudIdentityFromFreeClip2` (15.93 s) and `verifiesRealSettingChangesReadbackAndReconnectOnFreeClip2` (27.26 s) passed on `HUAWEI FreeClip 2`:
- Battery `0x0108` returned three-byte parameter 2 (`[86, 87, 54]`). Follow-up single-earbud adaptive swap probes (moving the same physical earbud `TQ0714268C013504` from right ear to left ear while `TQ0714268A007837` remained in the case) confirmed that once FreeClip 2 completes adaptive left/right wearing detection, **both `0x0107` parameter 24 (`L-.../R-...`) and `0x0108` parameters 2, 3, and 5 (`[index 0 = Left, index 1 = Right, index 2 = Case]`) dynamically follow the actual worn ear**:
  - Worn on right ear: `0x0107` param 24 = `L-TQ0714268A007837,R-TQ0714268C013504`; `0x0108` = `{1: [88], 2: [88, 88, 49], 3: [1, 0, 0], 5: [1, 0]}` (`index 1` out-of-case worn on right ear, `index 0` in case).
  - Worn on left ear (after adaptive update): `0x0107` param 24 = `L-TQ0714268C013504,R-TQ0714268A007837`; `0x0108` = `{1: [88], 2: [88, 92, 48], 3: [0, 1, 0], 5: [0, 1]}` (`index 0` out-of-case worn on left ear, `index 1` in case).
- Device info `0x0107` parameter 15 returned `BTFT0027` (hardware-confirming the model identifier).
- Real setting changes, readback verification, and restoration to original values succeeded for low latency (`0x2B6C`), equalizer (`0x2B4A`/`0x2B49`, options `[1, 10, 3, 9]`), double tap left/right (`0x0120`/`0x011F`, options `[1, 2, 7, 0, -1]`), triple tap left/right (`0x0126`/`0x0125`, options `[2, 4, 5, 6, 7, -1]`), long tap left/right (`0x2B17`/`0x2B16`, options `[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 15, 17, 20, -1]`), swipe (`0x2B1F`/`0x2B1E`, options `[0, 1, -1]`), and dual-connect auto-connect toggle (`0x2B33` cmd 4/5 + `0x2B31` readback).
- App-triggered RFCOMM close (`channel.close()`) triggered `rfcommChannelClosed`, cleared battery state, and automatically reconnected and received battery (`[86, 87, 54]`) and earbud identity again.
- Dual-connect enablement toggle (`0x2B2E`), preferred device switch (`0x2B32`), and connect/disconnect (`0x2B33` cmd 1/2) were not mutated to avoid disrupting active user connections.
- Physical earbud identity (`L-/R-` serials) vs. actual worn left/right ear position after swapping earbuds remains **unverified**; the UI keeps both worn sides unknown and displays the case level from the third battery field. BTFT0027 remains inferred from the Bluetooth name.

