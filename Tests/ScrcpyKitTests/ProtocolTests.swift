import Foundation
import Testing

@testable import ScrcpyKit

@Suite("control message wire format (scrcpy v3.3.4)")
struct ControlMessageTests {
    let position = ScreenPosition(x: 100, y: 200, width: 1080, height: 2400)

    @Test("touch down is exactly 32 bytes laid out like sc_control_msg_serialize")
    func touch() {
        let bytes = ControlMessage.injectTouch(
            action: .down, pointerID: PointerID.mouse, position: position, pressure: 1.0, actionButton: .primary,
            buttons: .primary
        ).serialize()
        #expect(bytes.count == 32)
        #expect(bytes[0] == 2)  // type
        #expect(bytes[1] == 0)  // AMOTION_EVENT_ACTION_DOWN
        #expect(Array(bytes[2..<10]) == [UInt8](repeating: 0xFF, count: 8))  // pointer id -1
        #expect(Array(bytes[10..<14]) == [0, 0, 0, 100])  // x
        #expect(Array(bytes[14..<18]) == [0, 0, 0, 200])  // y
        #expect(Array(bytes[18..<22]) == [0x04, 0x38, 0x09, 0x60])  // 1080 x 2400
        #expect(Array(bytes[22..<24]) == [0xFF, 0xFF])  // pressure 1.0 clamps to 0xffff
        #expect(Array(bytes[24..<28]) == [0, 0, 0, 1])  // action button
        #expect(Array(bytes[28..<32]) == [0, 0, 0, 1])  // buttons
    }

    @Test("virtual and generic finger ids are -3 and -2")
    func pointerIds() {
        #expect(PointerID.virtualFinger == UInt64(bitPattern: -3))
        #expect(PointerID.genericFinger == UInt64(bitPattern: -2))
    }

    @Test("keycode message is 14 bytes")
    func keycode() {
        let bytes = ControlMessage.injectKeycode(action: .up, keycode: 4, repeatCount: 0, meta: [.ctrl, .shift]).serialize()
        #expect(bytes == [0, 1, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0x10, 0x01])
    }

    @Test("text is length-prefixed and truncated on a character boundary")
    func text() {
        #expect(ControlMessage.injectText("hi").serialize() == [1, 0, 0, 0, 2, 0x68, 0x69])
        let long = String(repeating: "đ", count: 200)  // 2 bytes each → 400 bytes, limit 300
        let bytes = ControlMessage.injectText(long).serialize()
        let length = Int(bytes[1]) << 24 | Int(bytes[2]) << 16 | Int(bytes[3]) << 8 | Int(bytes[4])
        #expect(length == 300)
        #expect(String(decoding: bytes[5...], as: UTF8.self) == String(repeating: "đ", count: 150))
    }

    @Test("scroll is 21 bytes with ±16 normalised to signed fixed point")
    func scroll() {
        let bytes = ControlMessage.injectScroll(position: position, horizontal: 0, vertical: 16).serialize()
        #expect(bytes.count == 21)
        #expect(Array(bytes[13..<15]) == [0, 0])
        #expect(Array(bytes[15..<17]) == [0x7F, 0xFF])  // +1.0 clamps to 0x7fff
        let negative = ControlMessage.injectScroll(position: position, horizontal: 0, vertical: -16).serialize()
        #expect(Array(negative[15..<17]) == [0x80, 0x00])
    }

    @Test("simple and string messages")
    func simple() {
        #expect(ControlMessage.backOrScreenOn(.down).serialize() == [4, 0])
        #expect(ControlMessage.expandNotificationPanel.serialize() == [5])
        #expect(ControlMessage.collapsePanels.serialize() == [7])
        #expect(ControlMessage.getClipboard(.copy).serialize() == [8, 1])
        #expect(ControlMessage.setDisplayPower(false).serialize() == [10, 0])
        #expect(ControlMessage.rotateDevice.serialize() == [11])
        #expect(ControlMessage.resetVideo.serialize() == [17])
        #expect(ControlMessage.startApp("com.a").serialize() == [16, 5, 0x63, 0x6F, 0x6D, 0x2E, 0x61])
        #expect(
            ControlMessage.setClipboard(sequence: 7, text: "x", paste: true).serialize()
                == [9, 0, 0, 0, 0, 0, 0, 0, 7, 1, 0, 0, 0, 1, 0x78])
    }
}

@Suite("device messages")
struct DeviceMessageTests {
    @Test("clipboard messages arriving in fragments are reassembled")
    func fragments() throws {
        var parser = DeviceMessageParser()
        let full: [UInt8] = [0, 0, 0, 0, 5] + Array("héllo".utf8.prefix(5))
        #expect(try parser.feed(Array(full[0..<3])).isEmpty)
        let messages = try parser.feed(Array(full[3...]))
        #expect(messages == [.clipboard("héll")])
    }

    @Test("ack and back-to-back messages")
    func ack() throws {
        var parser = DeviceMessageParser()
        let bytes: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0, 9, 0, 0, 0, 0, 2, 0x6F, 0x6B]
        #expect(try parser.feed(bytes) == [.clipboardAck(sequence: 9), .clipboard("ok")])
    }

    @Test("unknown type is an error")
    func unknown() {
        var parser = DeviceMessageParser()
        #expect(throws: DeviceMessageParser.ParseError.self) { try parser.feed([99]) }
    }

    @Test("a clipboard message announcing an absurd length is rejected instead of buffered")
    func oversizedClipboardIsRejected() {
        var parser = DeviceMessageParser()
        // type 0, length 0xFFFFFFFF
        #expect(throws: DeviceMessageParser.ParseError.self) { try parser.feed([0, 0xFF, 0xFF, 0xFF, 0xFF]) }
    }

    @Test("a clipboard message at the limit is still accepted")
    func clipboardAtLimitIsAccepted() throws {
        var parser = DeviceMessageParser()
        let limit = DeviceMessageParser.maxClipboardLength
        let header: [UInt8] = [0, UInt8(limit >> 24 & 0xFF), UInt8(limit >> 16 & 0xFF), UInt8(limit >> 8 & 0xFF), UInt8(limit & 0xFF)]
        let messages = try parser.feed(header + [UInt8](repeating: 0x61, count: limit))
        #expect(messages.count == 1)
    }
}

@Suite("video framing")
struct VideoFramingTests {
    @Test("header word splits flags from the PTS")
    func header() {
        let config = VideoPacket(header: 1 << 63, data: Data([1]))
        #expect(config.isConfig && !config.isKeyFrame)
        let key = VideoPacket(header: (1 << 62) | 342_815_239, data: Data([1]))
        #expect(key.isKeyFrame && !key.isConfig && key.ptsMicroseconds == 342_815_239)
    }

    @Test("Annex-B → AVCC drops parameter sets and length-prefixes slices")
    func annexB() {
        // 3-byte and 4-byte start codes mixed: SPS, PPS, IDR slice (0x65 …), non-IDR slice (0x41 …)
        let stream = Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 9, 9, 9, 0, 0, 1, 0x41, 7])
        let units = AnnexB.nalUnits(in: stream)
        #expect(units.map { AnnexB.nalType(stream, $0) } == [7, 8, 5, 1])
        let sets = AnnexB.parameterSets(in: stream)
        #expect(sets?.sps == Data([0x67, 1, 2]))
        #expect(sets?.pps == Data([0x68, 3]))
        #expect(AnnexB.toAVCC(stream) == Data([0, 0, 0, 4, 0x65, 9, 9, 9, 0, 0, 0, 2, 0x41, 7]))
    }

    @Test("the vendored server jar is present and matches the pinned version")
    func jar() throws {
        let url = try ScrcpyServer.jarURL()
        #expect(url.lastPathComponent == "scrcpy-server-3.3.4.jar")
        #expect(try Data(contentsOf: url).count == 90_980)
    }
}

@Suite("pointer mapping")
struct PointerMapperTests {
    @Test("click = down/up of the mouse pointer inside the frame")
    func click() {
        var mapper = PointerMapper(frameSize: FrameSize(width: 1080, height: 2400))
        let down = mapper.mouseDown(at: CGPoint(x: 0.5, y: 0.25), pinch: false)
        #expect(down.count == 1)
        guard case .injectTouch(let action, let id, let position, let pressure, _, let buttons) = down[0] else {
            Issue.record("not a touch")
            return
        }
        #expect(action == .down && id == PointerID.mouse && pressure == 1 && buttons == .primary)
        #expect(position.x == 539 && position.y == 599 && position.width == 1080 && position.height == 2400)
        #expect(mapper.isTouching)

        let up = mapper.mouseUp(at: CGPoint(x: 0.5, y: 0.25))
        #expect(up.count == 1 && !mapper.isTouching)
    }

    @Test("drag without a prior press sends nothing; positions clamp to the frame")
    func clamp() {
        var mapper = PointerMapper(frameSize: FrameSize(width: 100, height: 200))
        #expect(mapper.mouseDragged(to: CGPoint(x: 0.5, y: 0.5)).isEmpty)
        let down = mapper.mouseDown(at: CGPoint(x: -3, y: 9), pinch: false)
        guard case .injectTouch(_, _, let position, _, _, _) = down[0] else { return }
        #expect(position.x == 0 && position.y == 199)
    }

    @Test("Option-press adds a mirrored second finger and lifts both together")
    func pinch() {
        var mapper = PointerMapper(frameSize: FrameSize(width: 1000, height: 2000))
        let down = mapper.mouseDown(at: CGPoint(x: 0.25, y: 0.25), pinch: true)
        #expect(down.count == 2)
        guard case .injectTouch(_, let secondID, let second, _, _, _) = down[1] else { return }
        #expect(secondID == PointerID.virtualFinger)
        #expect(second.x == 1000 - 249 && second.y == 2000 - 499)
        #expect(mapper.mouseDragged(to: CGPoint(x: 0.3, y: 0.3)).count == 2)
        #expect(mapper.mouseUp(at: CGPoint(x: 0.3, y: 0.3)).count == 2)
    }

    @Test("losing focus mid-drag lifts the finger exactly once")
    func cancel() {
        var mapper = PointerMapper(frameSize: FrameSize(width: 100, height: 100))
        _ = mapper.mouseDown(at: CGPoint(x: 0.5, y: 0.5), pinch: false)
        #expect(mapper.cancelTouches().count == 1)
        #expect(mapper.cancelTouches().isEmpty)
    }
}

@Suite("keyboard mapping")
struct KeyMapperTests {
    @Test("navigation keys map to Android keycodes with modifiers")
    func navigation() {
        #expect(KeyMapper.map(keyCode: 0x24, characters: "\r", charactersIgnoringModifiers: "\r", modifiers: []) == .key(keycode: 66, meta: []))
        #expect(KeyMapper.map(keyCode: 0x33, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", modifiers: []) == .key(keycode: 67, meta: []))
        #expect(KeyMapper.map(keyCode: 0x7B, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", modifiers: [.shift]) == .key(keycode: 21, meta: [.shift]))
    }

    @Test("printable text, IME output and accents go through injectText")
    func text() {
        #expect(KeyMapper.map(keyCode: 0, characters: "a", charactersIgnoringModifiers: "a", modifiers: []) == .text("a"))
        #expect(KeyMapper.map(keyCode: 0, characters: "ễ", charactersIgnoringModifiers: "e", modifiers: [.option]) == .text("ễ"))
    }

    @Test("function-key private-use scalars are never typed")
    func privateUse() {
        #expect(KeyMapper.map(keyCode: 0x72, characters: "\u{F746}", charactersIgnoringModifiers: "\u{F746}", modifiers: []) == .ignored)
    }

    @Test("Cmd+V/C/X are clipboard actions; Cmd+A becomes Ctrl+A")
    func command() {
        #expect(KeyMapper.map(keyCode: 9, characters: "v", charactersIgnoringModifiers: "v", modifiers: [.command]) == .paste)
        #expect(KeyMapper.map(keyCode: 8, characters: "c", charactersIgnoringModifiers: "c", modifiers: [.command]) == .copy)
        #expect(KeyMapper.map(keyCode: 7, characters: "x", charactersIgnoringModifiers: "x", modifiers: [.command]) == .cut)
        #expect(KeyMapper.map(keyCode: 0, characters: "a", charactersIgnoringModifiers: "a", modifiers: [.command]) == .key(keycode: 29, meta: [.ctrl]))
    }
}
