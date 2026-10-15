import AdbKit
import Foundation
import ScrcpyKit

private func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}


func recordCommand(_ context: Context) async throws -> CommandOutput {
        let serial = try context.serial()
        let duration = try context.args.intOption("--duration", default: 10) ?? 10
        let url = expandPath(context.args.option("--output", "-o") ?? "recording-\(serial)-\(timestamp()).mp4")
        try ensureWritable(url, context.args)
        let pipeline = PacketRecorder(url: url)
        let configuration = ScrcpyConfiguration(maxSize: try context.args.intOption("--max-size", default: 0) ?? 0)

        let session = try await ScrcpySession.start(
            client: context.client, serial: serial, configuration: configuration,
            handlers: ScrcpyHandlers(onPacket: { pipeline.handle($0) }))
        let startedAt = Date()
        FileHandle.standardError.write(Data("Recording \(session.deviceName) \(session.initialSize.width)x\(session.initialSize.height) for \(duration)s...\n".utf8))

        // Optional scripted input — also the quickest end-to-end check of the control channel.
        let afterSeconds = try context.args.intOption("--after", default: 2) ?? 2
        if let tap = context.args.option("--tap") {
            let parts = tap.split(separator: ",").compactMap { Int32($0) }
            guard parts.count == 2 else { throw CLIError.invalidValue("--tap", tap) }
            try await Task.sleep(nanoseconds: UInt64(afterSeconds) * 1_000_000_000)
            let position = ScreenPosition(x: parts[0], y: parts[1], width: UInt16(session.initialSize.width), height: UInt16(session.initialSize.height))
            session.send(.injectTouch(action: .down, pointerID: PointerID.genericFinger, position: position, pressure: 1, actionButton: .primary, buttons: .primary))
            try await Task.sleep(nanoseconds: 80_000_000)
            session.send(.injectTouch(action: .up, pointerID: PointerID.genericFinger, position: position, pressure: 0, actionButton: .primary, buttons: []))
        }
        if let press = context.args.option("--press") {
            guard let button = DeviceButton(rawValue: press), let code = button.keycode else { throw CLIError.invalidValue("--press", press) }
            try await Task.sleep(nanoseconds: UInt64(afterSeconds) * 1_000_000_000)
            session.send(.injectKeycode(action: .down, keycode: Int32(code)))
            session.send(.injectKeycode(action: .up, keycode: Int32(code)))
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        try await Task.sleep(nanoseconds: UInt64(max(Double(duration) - elapsed, 0.5) * 1_000_000_000))
        session.stop()
        let segments = await pipeline.recorder.finish()
        let frames = pipeline.recorder.frameCount
        let paths: [String] = segments.map { $0.path }
        return CommandOutput(json: obj(("files", paths), ("frames", frames))) {
            segments.forEach { print($0.path) }
            print("\(frames) frames, \(session.initialSize.width)x\(session.initialSize.height)")
        }
    }

func registerMediaCommands() {
    register("device screenshot", "[--output <file.png>] [--force]", "Take a screenshot at the device's full resolution") { context in
        let serial = try context.serial()
        let url = expandPath(context.args.option("--output", "-o") ?? "screenshot-\(serial)-\(timestamp()).png")
        try ensureWritable(url, context.args)
        let png = try context.client.screenshot(serial: serial)
        try png.write(to: url)
        return CommandOutput(json: ["file": url.path, "bytes": "\(png.count)"]) { print(url.path) }
    }

    register(
        "device record", "[--duration 10] [--output <file.mp4>] [--max-size N] [--tap x,y --after s] [--press button] [--force]",
        "Record the screen (H.264 → MP4, no re-encoding) via scrcpy-server", run: recordCommand)

    register("device input tap", "<x> <y>", "Tap at pixel coordinates") { context in
        try context.client.tap(serial: try context.serial(), x: try context.int(0, "x"), y: try context.int(1, "y"))
        return CommandOutput(json: ["ok": true]) {}
    }

    register("device input swipe", "<x1> <y1> <x2> <y2> [ms]", "Swipe") { context in
        let duration = context.rest.count > 4 ? try context.int(4, "ms") : 300
        try context.client.swipe(
            serial: try context.serial(), from: (try context.int(0, "x1"), try context.int(1, "y1")),
            to: (try context.int(2, "x2"), try context.int(3, "y2")), durationMilliseconds: duration)
        return CommandOutput(json: ["ok": true]) {}
    }

    register("device input text", "<text>", "Type text into the focused field") { context in
        try context.client.type(serial: try context.serial(), text: context.rest.joined(separator: " "))
        return CommandOutput(json: ["ok": true]) {}
    }

    register("device button", "<\(DeviceButton.allCases.map(\.rawValue).joined(separator: "|"))>", "Press a hardware / navigation button") { context in
        let name = try context.positional(0, "button name")
        guard let button = DeviceButton(rawValue: name) else { throw CLIError.invalidValue("button", name) }
        try context.client.press(button, serial: try context.serial())
        return CommandOutput(json: ["pressed": name]) { print("Pressed \(name)") }
    }
}
