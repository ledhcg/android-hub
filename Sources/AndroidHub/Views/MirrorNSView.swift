import AVFoundation
import AdbKit
import AppKit
import CoreMedia
import ScrcpyKit

/// The device canvas: draws the decoded stream and turns Mac input into Android input.
///
/// Video arrives on the scrcpy reader thread; `AVSampleBufferDisplayLayer` is safe to feed from there,
/// so frames never touch the main thread (important for latency).
final class MirrorNSView: NSView, NSTextInputClient {
    // MARK: Wiring

    /// Sends a control message to the device (set by the owning controller).
    var sendControl: ((ControlMessage) -> Void)?
    /// Called on the main thread when the decoded frame size changes (rotation, `wm size`, first frame).
    var onFrameSizeChange: ((FrameSize) -> Void)?
    /// IME composition text, so the UI can show what is being typed.
    var onMarkedTextChange: ((String) -> Void)?
    /// Device clipboard text arriving after Cmd+C / Cmd+X.
    var showsInputHint = true

    // MARK: Video

    private let displayLayer = AVSampleBufferDisplayLayer()
    private var factory = H264SampleFactory()
    private let factoryLock = NSLock()
    private(set) var frameSize: FrameSize?
    private var mapper = PointerMapper(frameSize: FrameSize(width: 1, height: 1))
    private var markedText = ""
    /// Keys currently down on the device, with the exact Android key/meta sent for the press, so the matching
    /// release is always replayed from this record rather than recomputed from today's modifier state.
    private var heldKeys: [UInt16: (keycode: Int32, meta: MetaState)] = [:]
    private var pendingText = ""
    private var pendingFlush: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }

    /// Feed one packet. Called from the video thread.
    func handle(packet: VideoPacket) {
        let outputs = factoryLock.withLock { factory.process(packet) }
        for output in outputs {
            switch output {
            case .formatChanged(let size):
                DispatchQueue.main.async { [weak self] in self?.applyFrameSize(size) }
            case .sample(let sample):
                if displayLayer.status == .failed { displayLayer.flush() }
                displayLayer.enqueue(sample)
            }
        }
    }

    private func applyFrameSize(_ size: FrameSize) {
        let wasTouching = mapper.isTouching
        frameSize = size
        // Update first: the server drops events whose screen size differs from its current video size,
        // so lifting the finger must be stamped with the NEW size to be accepted.
        mapper.updateFrameSize(size)
        if wasTouching { sendAll(mapper.cancelTouches()) }
        onFrameSizeChange?(size)
    }

    func resetVideo() {
        factoryLock.withLock { factory = H264SampleFactory() }
        displayLayer.flushAndRemoveImage()
        frameSize = nil
    }

    // MARK: Geometry

    /// Where the video actually sits inside the view (aspect fit).
    private func videoRect() -> CGRect? {
        guard let frameSize, frameSize.width > 0, frameSize.height > 0 else { return nil }
        return AVMakeRect(aspectRatio: CGSize(width: frameSize.width, height: frameSize.height), insideRect: bounds)
    }

    /// Mouse location as 0…1 inside the video, or `nil` when outside it.
    private func normalized(_ event: NSEvent, clamping: Bool = false) -> CGPoint? {
        guard let rect = videoRect() else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let x = (point.x - rect.minX) / rect.width
        let y = (point.y - rect.minY) / rect.height
        if !clamping, !(0...1).contains(x) || !(0...1).contains(y) { return nil }
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private func sendAll(_ messages: [ControlMessage]) { messages.forEach { sendControl?($0) } }

    // MARK: Mouse / trackpad

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        flushPendingText()
        guard let point = normalized(event) else { return }
        sendAll(mapper.mouseDown(at: point, pinch: event.modifierFlags.contains(.option)))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = normalized(event, clamping: true) else { return }
        sendAll(mapper.mouseDragged(to: point))
    }

    override func mouseUp(with event: NSEvent) {
        guard let point = normalized(event, clamping: true) else { return }
        sendAll(mapper.mouseUp(at: point))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard normalized(event) != nil else { return }
        sendAll(mapper.back())
    }

    override func otherMouseDown(with event: NSEvent) {
        guard normalized(event) != nil else { return }
        sendAll(mapper.home())
    }

    override func scrollWheel(with event: NSEvent) {
        guard let point = normalized(event) else { return }
        // Trackpads report points; SDL (and so scrcpy) scales precise deltas by 0.1 to get "lines".
        let scale: Float = event.hasPreciseScrollingDeltas ? 0.1 : 1
        sendAll(
            mapper.scroll(
                at: point, horizontal: Float(event.scrollingDeltaX) * scale, vertical: Float(event.scrollingDeltaY) * scale))
    }

    override func resignFirstResponder() -> Bool {
        flushPendingText()
        sendAll(mapper.cancelTouches())
        releaseHeldKeys()
        return super.resignFirstResponder()
    }

    // MARK: Keyboard

    private func modifiers(of event: NSEvent) -> KeyModifiers {
        var result: KeyModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }

    override func keyDown(with event: NSEvent) {
        // While an input method is composing (Telex/VNI), it owns Backspace, Return, arrows… — they edit or
        // commit the marked text instead of being sent to the device.
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        let flags = modifiers(of: event)
        let mapping = KeyMapper.map(
            keyCode: event.keyCode, characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers, modifiers: flags)
        switch mapping {
        case .key(let keycode, let meta):
            flushPendingText()
            if flags.contains(.command) {
                // A shortcut (Cmd+A → Ctrl+A): AppKit may never deliver its key-up while Cmd is held,
                // so press and release in one go instead of risking a key stuck down on the device.
                sendControl?(.injectKeycode(action: .down, keycode: keycode, meta: meta))
                sendControl?(.injectKeycode(action: .up, keycode: keycode, meta: meta))
            } else {
                heldKeys[event.keyCode] = (keycode, meta)
                sendControl?(.injectKeycode(action: .down, keycode: keycode, repeatCount: event.isARepeat ? 1 : 0, meta: meta))
            }
        case .paste: paste(nil)
        case .copy: copy(nil)
        case .cut: cut(nil)
        case .text, .ignored:
            // Route through the input method so Telex/VNI composition works.
            interpretKeyEvents([event])
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let held = heldKeys.removeValue(forKey: event.keyCode) else { return }
        sendControl?(.injectKeycode(action: .up, keycode: held.keycode, meta: held.meta))
    }

    /// Releases every key still down (focus lost, window closed) so the device never sees a stuck key.
    private func releaseHeldKeys() {
        for held in heldKeys.values { sendControl?(.injectKeycode(action: .up, keycode: held.keycode, meta: held.meta)) }
        heldKeys.removeAll()
    }

    // Standard Edit-menu actions arrive here through the responder chain.
    private var clipboardSequence: UInt64 = 1

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        clipboardSequence += 1
        sendControl?(.setClipboard(sequence: clipboardSequence, text: text, paste: true))
    }

    @objc func copy(_ sender: Any?) { sendControl?(.getClipboard(.copy)) }
    @objc func cut(_ sender: Any?) { sendControl?(.getClipboard(.cut)) }

    override func selectAll(_ sender: Any?) {
        sendControl?(.injectKeycode(action: .down, keycode: 29, meta: .ctrl))
        sendControl?(.injectKeycode(action: .up, keycode: 29, meta: .ctrl))
    }

    // MARK: NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = ""
        onMarkedTextChange?("")
        guard !text.isEmpty else { return }
        // Plain ASCII typed while nothing is pending goes straight through (lowest latency).
        if pendingText.isEmpty, text.unicodeScalars.allSatisfy({ $0.isASCII }) {
            sendControl?(.injectText(text))
            return
        }
        // Anything else is batched for a moment: fast input (and decomposed accents) arrives as several
        // calls, and pasting each separately races with the device's clipboard.
        pendingText += text
        pendingFlush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushPendingText() }
        pendingFlush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
    }

    /// Sends batched text now. Must run before any key or pointer event so ordering is preserved.
    func flushPendingText() {
        pendingFlush?.cancel()
        pendingFlush = nil
        guard !pendingText.isEmpty else { return }
        let text = pendingText.precomposedStringWithCanonicalMapping
        pendingText = ""
        if text.unicodeScalars.allSatisfy({ $0.isASCII }) {
            sendControl?(.injectText(text))
        } else {
            // scrcpy's text injection only produces what the virtual keyboard layout can type (ASCII).
            // Vietnamese and other Unicode text goes through the device clipboard + paste instead.
            clipboardSequence += 1
            sendControl?(.setClipboard(sequence: clipboardSequence, text: text, paste: true))
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        onMarkedTextChange?(markedText)
    }

    func unmarkText() {
        markedText = ""
        onMarkedTextChange?("")
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count) }
    func hasMarkedText() -> Bool { !markedText.isEmpty }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributedString() -> [NSAttributedString.Key] { [] }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { 0 }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(NSRect(x: bounds.midX, y: bounds.maxY - 40, width: 1, height: 20), to: nil))
    }

    override func doCommand(by selector: Selector) {
        // Keys that are neither text nor mapped (e.g. Option-arrows) are ignored rather than beeping.
    }
}
