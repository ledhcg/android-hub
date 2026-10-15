import AdbKit
import SwiftUI

/// Device Hub's Settings inspector: every control writes to the device immediately.
struct SettingsPanel: View {
    @StateObject private var model: SettingsModel
    @State private var latitude = "10.7769"
    @State private var longitude = "106.7009"
    @State private var localePackage = ""
    @State private var localeTag = "vi-VN"
    @State private var fontScale = 1.0
    @State private var brightness = 128.0
    @State private var volume = 0.0
    @State private var batteryLevel = 100.0
    @State private var density = ""

    init(serial: String, client: AdbClient) {
        _model = StateObject(wrappedValue: SettingsModel(serial: serial, client: client))
    }

    private let places: [(String, Double, Double)] = [
        ("TP. Hồ Chí Minh", 10.7769, 106.7009), ("Hà Nội", 21.0285, 105.8542), ("Đà Nẵng", 16.0544, 108.2022),
        ("Tokyo", 35.6762, 139.6503), ("London", 51.5074, -0.1278), ("San Francisco", 37.7749, -122.4194), ("Sydney", -33.8688, 151.2093),
    ]
    private let timeZones = ["Asia/Ho_Chi_Minh", "Asia/Tokyo", "Asia/Singapore", "Europe/London", "America/New_York", "America/Los_Angeles", "Australia/Sydney", "UTC"]

    var body: some View {
        VStack(spacing: 0) {
            ErrorBanner(message: model.error)
            Form {
                Section("Giao diện") {
                    Picker("Chủ đề", selection: model.binding(\.appearance, default: .auto) { .appearance($0) }) {
                        Text("Sáng").tag(AppearanceMode.light)
                        Text("Tối").tag(AppearanceMode.dark)
                        Text("Tự động").tag(AppearanceMode.auto)
                    }.pickerStyle(.segmented)
                    LabeledSlider(title: "Cỡ chữ", value: $fontScale, range: 0.85...2.0, format: "%.2f×") { model.apply(.fontScale($0)) }
                    Toggle("Làm chậm animation (10×)", isOn: Binding(
                        get: { (model.snapshot.animationScale ?? 1) >= 5 },
                        set: { on in model.apply(.animationScale(on ? 10 : 1)) { $0.animationScale = on ? 10 : 1 } }))
                    Toggle("Chữ tương phản cao", isOn: model.binding(\.highContrastText, default: false) { .highContrastText($0) })
                    Toggle("Đảo màu", isOn: model.binding(\.colorInversion, default: false) { .colorInversion($0) })
                    Picker("Hiệu chỉnh màu", selection: Binding(
                        get: { model.snapshot.colorCorrection },
                        set: { value in model.apply(.colorCorrection(value)) { $0.colorCorrection = value } })) {
                        Text("Tắt").tag(ColorCorrection?.none)
                        Text("Đơn sắc").tag(ColorCorrection?.some(.monochromacy))
                        Text("Mù màu đỏ (protan)").tag(ColorCorrection?.some(.protanomaly))
                        Text("Mù màu lục (deutan)").tag(ColorCorrection?.some(.deuteranomaly))
                        Text("Mù màu lam (tritan)").tag(ColorCorrection?.some(.tritanomaly))
                    }
                }

                Section("Màn hình & hướng") {
                    Toggle("Tự xoay", isOn: model.binding(\.autoRotate, default: true) { .autoRotate($0) })
                    Picker("Hướng", selection: Binding(
                        get: { model.snapshot.rotation ?? .portrait },
                        set: { value in model.apply(.rotation(value)) { $0.rotation = value; $0.autoRotate = false } })) {
                        Text("Dọc").tag(DeviceRotation.portrait)
                        Text("Ngang trái").tag(DeviceRotation.landscapeLeft)
                        Text("Dọc ngược").tag(DeviceRotation.portraitUpsideDown)
                        Text("Ngang phải").tag(DeviceRotation.landscapeRight)
                    }
                    if let info = model.info {
                        LabeledContent("Kích thước", value: "\(info.overrideSize?.width ?? info.physicalSize?.width ?? 0)×\(info.overrideSize?.height ?? info.physicalSize?.height ?? 0)")
                        HStack {
                            TextField("Density (dpi)", text: $density).frame(width: 110)
                            Button("Áp dụng") { if let dpi = Int(density) { model.apply(.displayDensity(dpi)) } }.disabled(Int(density) == nil)
                            Button("Gốc") { model.apply(.resetDisplayDensity) }
                        }
                        .onAppear { density = "\(info.overrideDensity ?? info.physicalDensity ?? 0)" }
                    }
                    LabeledSlider(title: "Độ sáng", value: $brightness, range: 0...255, format: "%.0f") { model.apply(.brightness(Int($0))) }
                    Toggle("Tự động chỉnh độ sáng", isOn: model.binding(\.autoBrightness, default: false) { .autoBrightness($0) })
                    Toggle("Luôn sáng khi cắm sạc", isOn: model.binding(\.stayAwake, default: false) { .stayAwake($0) })
                }

                Section("Âm thanh") {
                    if let max = model.snapshot.mediaVolumeMax {
                        LabeledSlider(title: "Âm lượng", value: $volume, range: 0...Double(max), format: "%.0f", step: 1) { model.apply(.mediaVolume(Int($0))) }
                    } else {
                        Text("Thiết bị không báo mức âm lượng").foregroundStyle(.secondary)
                    }
                }

                Section("Mạng") {
                    Toggle("Wi-Fi", isOn: model.binding(\.wifi, default: true) { .wifi($0) })
                    Toggle("Dữ liệu di động", isOn: model.binding(\.mobileData, default: true) { .mobileData($0) })
                    Toggle("Chế độ máy bay", isOn: model.binding(\.airplaneMode, default: false) { .airplaneMode($0) })
                    Toggle("Bluetooth", isOn: model.binding(\.bluetooth, default: false) { .bluetooth($0) })
                    if model.isEmulator {
                        Picker("Tốc độ mạng", selection: Binding(get: { "full" }, set: { model.apply(.emulatorNetworkSpeed($0)) })) {
                            ForEach(["full", "lte", "hsdpa", "umts", "edge", "gprs", "gsm"], id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Độ trễ mạng", selection: Binding(get: { "none" }, set: { model.apply(.emulatorNetworkDelay($0)) })) {
                            ForEach(["none", "umts", "edge", "gprs"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section("Vị trí & ngôn ngữ") {
                    Picker("Địa điểm mẫu", selection: Binding(get: { "" }, set: { name in
                        if let place = places.first(where: { $0.0 == name }) {
                            latitude = "\(place.1)"; longitude = "\(place.2)"
                            model.apply(.location(latitude: place.1, longitude: place.2))
                        }
                    })) {
                        Text("Chọn…").tag("")
                        ForEach(places, id: \.0) { Text($0.0).tag($0.0) }
                    }
                    HStack {
                        TextField("Vĩ độ", text: $latitude).frame(width: 90)
                        TextField("Kinh độ", text: $longitude).frame(width: 90)
                        Button("Đặt") { if let lat = Double(latitude), let lon = Double(longitude) { model.apply(.location(latitude: lat, longitude: lon)) } }
                    }
                    if !model.isEmulator { Text("Trên máy thật dùng mock location của shell; có thể bị ROM chặn.").font(.caption).foregroundStyle(.secondary) }
                    Picker("Múi giờ", selection: Binding(get: { model.snapshot.timeZone ?? "" }, set: { zone in model.apply(.timeZone(zone)) { $0.timeZone = zone } })) {
                        if let zone = model.snapshot.timeZone, !timeZones.contains(zone) { Text(zone).tag(zone) }
                        ForEach(timeZones, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Mở cài đặt ngôn ngữ hệ thống") { model.apply(.openLocaleSettings) }
                    HStack {
                        TextField("package", text: $localePackage)
                        TextField("vi-VN", text: $localeTag).frame(width: 70)
                        Button("Đặt") { model.apply(.appLocale(package: localePackage, languageTag: localeTag)) }.disabled(localePackage.isEmpty)
                    }
                    Text("Ngôn ngữ riêng cho từng app (Android 13+).").font(.caption).foregroundStyle(.secondary)
                }

                Section("Pin (giả lập)") {
                    LabeledSlider(title: "Mức pin", value: $batteryLevel, range: 0...100, format: "%.0f%%", step: 1) { model.apply(.batteryLevel(Int($0))) }
                    Picker("Trạng thái", selection: Binding(get: { BatteryStatus.discharging }, set: { model.apply(.batteryStatus($0)) })) {
                        Text("Đang sạc").tag(BatteryStatus.charging)
                        Text("Đang xả").tag(BatteryStatus.discharging)
                        Text("Không sạc").tag(BatteryStatus.notCharging)
                        Text("Đầy").tag(BatteryStatus.full)
                    }
                    HStack {
                        Button("Rút sạc") { model.apply(.batteryPower(ac: false, usb: false, wireless: false)) }
                        Button("Cắm sạc") { model.apply(.batteryPower(ac: true, usb: false, wireless: false)) }
                        Button("Khôi phục") { model.apply(.resetBattery); model.load() }
                    }
                }

                Section("Nhà phát triển") {
                    Toggle("Hiện điểm chạm", isOn: model.binding(\.showTouches, default: false) { .showTouches($0) })
                    Toggle("Vị trí con trỏ", isOn: model.binding(\.pointerLocation, default: false) { .pointerLocation($0) })
                    Toggle("Không giữ activity", isOn: model.binding(\.doNotKeepActivities, default: false) { .doNotKeepActivities($0) })
                }
            }
            .formStyle(.grouped)
        }
        .task {
            model.load()
        }
        .onChange(of: model.snapshot) { snap in
            fontScale = snap.fontScale ?? fontScale
            brightness = Double(snap.brightness ?? Int(brightness))
            volume = Double(snap.mediaVolume ?? Int(volume))
        }
    }
}

/// A slider that only touches the device when released, so dragging does not flood adb.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var step: Double? = nil
    let commit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value)).monospacedDigit().foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step) { editing in if !editing { commit(value) } }
            } else {
                Slider(value: $value, in: range) { editing in if !editing { commit(value) } }
            }
        }
    }
}
