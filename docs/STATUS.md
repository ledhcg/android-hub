# Trạng thái dự án — Android Hub

Cập nhật: 2026-10-14. Tài liệu này ghi lại **việc đã làm**, **việc chưa làm / cần làm tiếp**, các **lỗi và hạn chế đã biết**
và **bài học** để người (hoặc AI) tiếp quản không phải khám phá lại từ đầu. Mô tả tính năng và cách dùng: xem [README](../README.md).

Mục tiêu gốc: nghiên cứu **Device Hub** của Xcode 27 (WWDC26, session 260) rồi port chức năng tương tự cho thiết bị Android trên macOS.

---

## 1. Đã làm

### 1.1 Thư viện và công cụ

| Thành phần | Nội dung | Trạng thái |
|---|---|---|
| `AdbKit` | Nói chuyện trực tiếp với adb server: `host:devices-l`, `track-devices`, `shell,v2` (tách stdout/stderr/exit code), `sync:` v1+v2 (push/pull/list/stat, 64-bit), `pair`/`connect`/`mdns`/`tcpip`, console emulator (token + `geo fix`, `network`…), `localabstract:` | xong, có test |
| `AdbKit` (dịch vụ thiết bị) | Cài đặt hệ thống (≈35 loại), ứng dụng (list/info/cài APK + split/gỡ/mở/dừng/xoá dữ liệu/quyền/lấy APK/run-as), tệp (list/push/pull đệ quy/mkdir/rm/mv), screenshot, logcat có lọc, crash/ANR (dropbox), dumpsys, bugreport, gói chẩn đoán | xong, có test |
| `ScrcpyKit` | Client native cho scrcpy-server **3.3.4** (ghim): mã hoá control message (đã đối chiếu byte với `control_msg.c`), parser device message, Annex-B → AVCC → `CMSampleBuffer`, quay MP4 passthrough có duration tường minh, vòng đời phiên qua `localabstract:`, ánh xạ chuột/bàn phím | xong, có test |
| `EmulatorKit` | Liệt kê AVD, tạo/xoá/đổi tên (avdmanager), khởi động (cold boot / headless / wipe), tắt, wipe, phát hiện đang chạy qua lock pid, tải system image | xong, có test |
| `adbctl` | CLI kiểu `devicectl`, ~45 lệnh, `--json-output` có `jsonVersion`, chống ghi đè (`--force`), `--` kết thúc option | xong |
| `AndroidHub.app` | SwiftUI/AppKit: sidebar + canvas (bezel, nút, thanh công cụ) + inspector 6 tab; cửa sổ nhỏ gọn; menu Điều khiển/Thiết bị; sheet ghép đôi Wi-Fi và tạo emulator | xong |
| `scripts/` | `build-app.sh` (đóng gói `.app` ký ad-hoc + `adbctl` + resource bundle), `make-icon.swift` | xong |

### 1.2 Đối chiếu Device Hub

Đã có: sidebar thiết bị+simulator (lọc/sắp xếp/tìm), ghép đôi, canvas trực tiếp, chạm/kéo/cuộn/bàn phím, nút phần cứng, xoay, zoom/kích thước thật,
resize mode, cửa sổ nhỏ gọn, chụp/quay, inspector Settings/Info/Apps/Diagnostics, `devicectl`-style CLI, quản lý simulator (AVD).
Không làm được (không có tương đương): mount DeviceFS trong Finder, Profiles `.mobileconfig`, Siri/Shake/CarPlay/AirPlay/camera-mic.

### 1.3 Đã kiểm chứng (có bằng chứng chạy thật)

- **81 test đơn vị** (AdbKit 49, ScrcpyKit 24, EmulatorKit 8) — `swift test`.
- **13 test tích hợp** trên emulator (opt-in qua `ADBHUB_TEST_SERIAL`): shell v2, sync round-trip >64 KiB, cài đặt, logcat, ảnh chụp, mirror đầu-cuối, điều khiển (HOME → launcher), `stop()` idempotent, huỷ khi đang khởi động, không sót server.
- **GUI** (điều khiển app và chụp màn hình bằng computer-use): chọn thiết bị, View Screen, click/vuốt/cuộn, gõ ASCII và tiếng Việt, nút Home/Back/thông báo, phím tắt menu, đổi dark mode từ inspector, chụp màn hình, quay video, 2 cửa sổ cùng một thiết bị, resize mode (đổi SPS giữa chừng), các tab Info/Apps/Files/Logs/Diagnostics, sheet ghép đôi + mDNS, sheet emulator mới, tạo và xoá AVD, thoát app khi đang quay (MP4 vẫn hợp lệ).
- **Mi 8 thật (Android 13)**: list/info/settings/apps/files (chỉ đọc) và mirror qua CLI.
- **Emulator Android 17 (API 37)** chạy tốt với scrcpy-server 3.3.4.
- **Review độc lập** (agent đọc mã, không biết kết luận của tác giả): ~17 phát hiện, đã sửa hầu hết (xem 3.2).

---

## 2. Chưa làm / việc nên làm tiếp

Sắp theo độ ưu tiên đề xuất.

### P1 — cần kiểm chứng (đã có mã nhưng chưa thử trên thật)

- [ ] **Ghép đôi Wi-Fi hoàn chỉnh** với máy Android 11+ (`adb pair` bằng mã + `connect`). Giao diện, mDNS và parser đã chạy; chưa có phiên ghép nào hoàn tất vì không có máy ở trạng thái "Pair device with pairing code".
- [ ] **Chạm/bàn phím trên Mi 8 thật.** Máy Xiaomi cần bật "USB debugging (Security settings)". Mirror video trên Mi 8 đã đo qua CLI; điều khiển thì mới thử trên emulator.
- [ ] **Mirror trong GUI trên máy thật** (đã từng chạy nhưng cố ý không xem nội dung). Nên thử sau khi bạn sẵn sàng cho app hiển thị màn hình máy.
- [ ] **Pinch (⌥-kéo)**, **Cmd+C/Cmd+X** (device → clipboard Mac) và **Cmd+V** (Mac → device): đã có mã + test mapping, chưa thử trong GUI.
- [ ] **Bộ gõ Telex/VNI thật** (marked text). Mới thử bằng công cụ gõ tự động (tách dấu rời, có thể rơi dấu cuối).
- [ ] **Giả lập vị trí trên máy thật** (`cmd location` test provider) — chỉ emulator (`geo fix`) được kiểm chứng.
- [ ] **Không có UI test tự động.** GUI được kiểm bằng screenshot thủ công; `adbctl` (target executable) chưa có unit test cho `Arguments`/dispatch.

### P2 — tính năng chưa có

- [ ] **Mount DeviceFS trong Finder** (FSKit hoặc File Provider). Hiện thay bằng trình duyệt tệp trong app + `adbctl device files`.
- [ ] **Đẩy file vào data container** của app (run-as): mới duyệt và tải về.
- [ ] **Âm thanh** (scrcpy audio, Android 11+), **đa màn hình** (`display_id`, `new_display`), **camera**, H.265/AV1.
- [ ] **UI cho cấu hình mirror**: `ScrcpyConfiguration` (max size, fps, bitrate, show touches, stay awake) đã có nhưng app dùng mặc định.
- [ ] **Bezel theo từng đời máy** (hiện là khung chung), thanh điều hướng giả theo kiểu thiết bị.
- [ ] **Huỷ `bugreport`** hiện chỉ đóng kết nối; chưa dừng `dumpstate` trên máy.
- [ ] **Ngôn ngữ hệ thống**: chỉ mở màn hình cài đặt; chưa đổi trực tiếp (cần quyền hệ thống).
- [ ] **Layout bounds / GPU overdraw / profile** (tuỳ chọn nhà phát triển nâng cao).
- [ ] **Phân phối**: ký Developer ID + notarize + DMG (hiện ký ad-hoc, chỉ chạy trên máy build).
- [ ] **Quy trình nâng cấp scrcpy-server**: đổi `ScrcpyServer.version` + jar trong `Resources/` + đối chiếu lại `ControlMessage.swift` với `control_msg.c` của bản mới (giao thức không ổn định giữa các bản).

### P3 — dọn dẹp / cải thiện

- [ ] Picker "Trạng thái pin" và "Tốc độ/độ trễ mạng" ở Settings panel **không đọc lại giá trị hiện tại** (luôn hiện giá trị mặc định); cần lưu state cục bộ hoặc đọc từ thiết bị.
- [ ] Logcat panel: `visible` được cắt ở 5000 dòng; chưa có tìm kiếm theo regex, lọc theo PID/package, đánh dấu.
- [ ] Sidebar: chưa nhớ thứ tự/nhóm tuỳ chỉnh; menu AVD chưa ẩn "Xoá/Wipe" khi đang chạy (đã chặn ở tầng logic, báo lỗi).
- [ ] Gõ ký tự Unicode bằng clipboard sẽ **ghi đè clipboard của điện thoại**; cân nhắc khôi phục clipboard cũ hoặc cho tắt tính năng.
- [ ] `adbctl device logs --json-output` gom toàn bộ log vào bộ nhớ trước khi ghi.

---

## 3. Lỗi và hạn chế đã biết

### 3.1 Hạn chế của chính thiết kế

- Màn hình đang **tắt/khoá** thì không có khung hình; app tự đánh thức màn hình trước khi mirror. Cửa sổ `FLAG_SECURE` hiển thị đen.
- **Khởi động chậm lần đầu** trên một số máy: Mi 8 mất ~31 giây ở lần đầu (ART nạp jar), các lần sau dưới 1 giây.
- Gõ **Unicode** đi qua clipboard + paste (scrcpy `injectText` chỉ gõ được ASCII). Dấu rời (NFD) có thể rơi dấu cuối.
- `adb pair` bằng mã chỉ có từ Android 11; máy cũ hơn dùng `adbctl manage tcpip` qua USB.
- File ≥ 4 GiB: đã dùng sync v2 (64-bit) khi adbd hỗ trợ (`stat_v2`/`ls_v2`), v1 chỉ là fallback.

### 3.2 Đã sửa sau review độc lập (để tham khảo, không cần làm lại)

Phím kẹt trên thiết bị · phím đặc biệt phá IME đang soạn · thao tác file dùng đường dẫn đang gõ dở · nút xoá ở chế độ container chạy sai đích · ghi đè/cắt file cục bộ khi tải hỏng · UI đứng khi adb server tắt · menu tác động nhầm thiết bị khi nhiều cửa sổ · `input text` gõ `%` thành `%25` · Huỷ không dừng phiên đang khởi động · mất bản quay khi thoát app · một emulator lỗi làm mất cả danh sách · `hasPrefix("KO")` nhận nhầm AVD tên `KOTLIN…` · xoá/wipe AVD đang chạy · emulator chết lúc khởi động không báo lỗi · CLI hiểu sai số âm đầu tiên · `adbctl` đóng gói crash vì thiếu resource bundle · quyền runtime lấy từ user cuối thay vì user 0 · race khi chọn app / tải thư mục / thả file · log từng dòng làm nghẹt main thread · `UInt32` mtime tràn · tên file từ thiết bị chứa `/`.

---

## 4. Bài học và sự cố cần nhớ

1. **`host:emulator:<port>` là lệnh ĐĂNG KÝ emulator** với adb server, không phải để gửi lệnh console. Dùng nhầm sẽ tạo transport ma `emulator-<port-1>`; chỉ khởi động lại adb server mới dọn được. Đúng: nối thẳng cổng console (số trong `emulator-5554`) + `~/.emulator_console_auth_token` (`EmulatorConsole.swift`).
2. **`ps -A` không in tên lớp Java** (chỉ `app_process64`). Kiểm tra "không sót scrcpy server" phải dùng `ps -A -o ARGS | grep '[s]crcpy.Server'`. Test tích hợp có thêm một bài chứng minh phép đo thấy được server đang chạy.
3. **`adb shell` đọc stdin.** Trong script/heredoc phải thêm `< /dev/null`, nếu không `adb` nuốt phần còn lại của script.
4. **`CleanUp` của scrcpy tự xoá jar** khi server kết thúc; test thủ công cần push lại jar mỗi lần.
5. **Tiến trình scrcpy-server sống đúng bằng kết nối shell**; đóng socket là server dọn (đã kiểm chứng: 0 tiến trình, jar bị xoá).
6. `AVD` do `avdmanager` tạo với system image có minor version ghi `target=android-0`; app lấy API từ `image.sysdir.1`.
7. Xcode 27: SwiftPM dùng thư mục build mới (`.build/out/Products/<Config>`); luôn dùng `swift build --show-bin-path`. Đừng truyền nhiều `--product` cùng lúc (chỉ cái cuối được build).
8. **Mi 8 chạy Android 13** (không phải 10): hỗ trợ `ls_v2`, `stat_v2`, `shell_v2`, ghép đôi bằng mã.

---

## 5. Cách tiếp tục

```bash
swift build && swift test                                   # build + 81 test đơn vị
ADBHUB_TEST_SERIAL=emulator-5554 swift test --filter IntegrationTests   # CHỈ trỏ vào emulator
scripts/build-app.sh release && open build/AndroidHub.app   # đóng gói và chạy
.build/debug/adbctl help
```

Bản đồ mã: `Sources/AdbKit` (giao thức + dịch vụ thiết bị) → `Sources/ScrcpyKit` (mirror/điều khiển) → `Sources/EmulatorKit` (AVD)
→ `Sources/adbctl` (CLI) và `Sources/AndroidHub` (app). Giấy phép scrcpy-server: `Sources/ScrcpyKit/Resources/SCRCPY-LICENSE.txt` (Apache-2.0).
