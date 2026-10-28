import AppKit
import ApplicationServices
import Carbon

func sourceProperty(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let value = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue()
}
func inputSourceIsASCII() -> Bool {
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return true }
    return (sourceProperty(current, kTISPropertyInputSourceIsASCIICapable) as? NSNumber)?.boolValue ?? true
}
let letterKeys: [String: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
struct Mapping: Codable {
    var sideButtons: [Int64] = [3, 4]
    var holdMilliseconds: Double = 2000
    var gestureThreshold: Double = 32
    var idleMilliseconds: Double = 220
    var layers: [[String]] = [
        Array("abcdefghijklmnopqrstuvwxyz").map(String.init),
        Array("0123456789.,!?;:'\"-+*/=()[]{}<>_\\|@#$%^&`~").map(String.init),
        ["(",")","[","]","{","}","<",">","=","+","-","*","/","%","!","&","|","^","~","_",":",";",",",".","\"","'","\\","@","#","$","`","?","==","!=","<=",">=","&&","||","->","=>","+=","-=","*=","/=","++","--","::","...","\t"]
    ]
    func valid() -> Bool {
        sideButtons.count == 2 && Set(sideButtons).count == 2 && sideButtons.allSatisfy { (3...31).contains($0) } && holdMilliseconds >= 300 && holdMilliseconds <= 2000 && gestureThreshold >= 8 && gestureThreshold <= 500 && idleMilliseconds >= 100 && idleMilliseconds <= 1500 && !layers.isEmpty && layers.count <= 12 && layers.allSatisfy { !$0.isEmpty && $0.count <= 64 && $0.allSatisfy { !$0.isEmpty && $0.utf16.count <= 128 } }
    }
    func character(layer: Int, group: Int, direction: Int) -> String? {
        let index = group * 8 + direction
        return layers[layer].indices.contains(index) ? layers[layer][index] : nil
    }
}
struct CharacterPage {
    var layer: Int
    var offset: Int
    var values: [String]
}
let letterGroups = ["abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz"]
// Direction indices: E, SE, S, SW, W, NW, N, NE, center.
let keypadSlots = [6, 7, 4, 8, 0, 3, 2, 1] // ABC ... WXYZ
let keypadReadingOrder = [5, 6, 7, 4, 8, 0, 3, 2, 1]
let utilitySlot = 5
func keypadValues(_ groups: [String], utility: String) -> [String] {
    var values = Array(repeating: "", count: 9)
    for (group, slot) in keypadSlots.enumerated() where group < groups.count { values[slot] = groups[group] }
    values[utilitySlot] = utility
    return values
}
let commonWords = "the of and to a in is you that it he was for on are as with his they i at be this have from or one had by word but not what all were we when your can said there use an each which she do how their if will up other about out many then them these so some her would make like him into time has look two more write go see number no way could people my than first water been call who oil its now find long down day did get come made may part hello help here home house good great give going world work want where why while well welcome thank thanks think thing things take tell test text type typing thumb trackball mouse code computer program print public private function file false true swift space small show select selection ring read right left return run result really please page pointer input output open close next new name need know keyboard key keep just jump quick question quite queen zero zip zoom yellow yes year young yesterday easy email each example english even every end enter error enough else enjoy element value view very version variable use user under until update using understand turn try true tree through three today together too tool top track use usual useful test testing those though there their them these then therefore word words work working with without write writer wrong would wheel window wait which world want water walk will was when where whether while white what who whose whole how here have hello handle happy back ball best better between both build button beautiful before because begin big bit box bring browser backspace can cannot case change character choose circle class click clear color command complete completion control could count current cursor day default delete developer direction different display document down drive during event example exit every first focus forward found frame full general gesture global guide hardware hold hour important include index information inside install internal item itself language last later layer learn letter letters light line list little local log long mac main make map mapping mode monitor move movement much must native normal note now number often once only option order other output over panel pass permission physical place point prediction press previous privacy process proper provide quick real recover release repeat request reset restore return same screen scroll second secure send set settings short should side simple since single size slow some source special start state still stop store string support sure system table tap target test text than that their there thing think three threshold through timeout time title today touch trackball typing type unicode unit until update use usual valid value version view visible wait want way well were when where which while white whole why window with within without word world work write xcode you your yourself yellow yes year young zero zoom zebra zone query queue quality question quiet queen quickly quantum".split(separator: " ").map(String.init)
func completions(_ prefix: String) -> [String] {
    guard !prefix.isEmpty else { return [] }
    var seen = Set<String>()
    return commonWords.filter { $0.hasPrefix(prefix) && $0 != prefix && seen.insert($0).inserted }.prefix(9).map { $0 }
}
func pages(for mapping: Mapping) -> [CharacterPage] {
    var result: [CharacterPage] = []
    for (layer, original) in mapping.layers.enumerated() {
        let isAlphabet = layer == 0 && Set(original) == Set(Array("abcdefghijklmnopqrstuvwxyz").map(String.init)) && original.count == 26
        if isAlphabet {
            for column in 0..<4 {
                let values = letterGroups.map { group -> String in
                    let letters = Array(group); return column < letters.count ? String(letters[column]) : ""
                }
                result.append(CharacterPage(layer: 0, offset: column * 9, values: keypadValues(values, utility: "符号")))
            }
            continue
        }
        for offset in stride(from: 0, to: original.count, by: 8) {
            let chunk = Array(original.dropFirst(offset).prefix(8))
            result.append(CharacterPage(layer: layer, offset: (offset / 8) * 9, values: keypadValues(chunk, utility: layer == 0 ? "符号" : "字母")))
        }
    }
    result.append(CharacterPage(layer: -1, offset: 0, values: keypadValues(["⌫ Backspace", "↵ Enter", "⇥ Tab", "←", "↓", "↑", "→", "␣ Space"], utility: "字母")))
    return result
}
final class DirectionHUD: NSView {
    var values: [String] = []
    var selected: Int?
    var heading = ""
    var center = ""
    var footer = ""
    var showLetterGroups = false
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20).fill()
        func text(_ value: String, _ rect: NSRect, _ size: CGFloat, _ color: NSColor = .labelColor, _ weight: NSFont.Weight = .medium) {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
        }
        text(heading, NSRect(x: 6, y: 201, width: 268, height: 16), 11)
        for (position, d) in keypadReadingOrder.enumerated() {
            let rect = NSRect(x: 19 + (position % 3) * 82, y: 142 - (position / 3) * 50, width: 78, height: 46)
            let active = selected == d && values.indices.contains(d) && !values[d].isEmpty
            (active ? NSColor.controlAccentColor : NSColor.controlBackgroundColor).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9); path.fill()
            NSColor.separatorColor.setStroke(); path.lineWidth = 0.6; path.stroke()
            let value = values.indices.contains(d) && !values[d].isEmpty ? values[d] : "—"
            let compact = ["␣ Space": "␣", "⌫ Backspace": "⌫", "↵ Enter": "↵", "⇥ Tab": "⇥"][value] ?? value
            let groupLabel = letterGroups.contains { $0.uppercased() == compact }
            let letterGroup = showLetterGroups ? keypadSlots.firstIndex(of: d) : nil
            if let group = letterGroup {
                text(letterGroups[group].uppercased(), NSRect(x: rect.minX + 3, y: rect.maxY - 13, width: 72, height: 12), 8, active ? .white : .secondaryLabelColor)
            }
            let fontSize: CGFloat = groupLabel ? 15 : compact.count > 3 ? 11 : 18
            text(compact, NSRect(x: rect.minX + 3, y: rect.midY - (letterGroup == nil ? 11 : 16), width: 72, height: 24), fontSize, active ? .white : .labelColor, .semibold)
        }
        text(footer, NSRect(x: 5,y: 1,width: 270,height: 27), 10, .secondaryLabelColor)

    }
}
let support = CommandLine.arguments.contains("--integration-test")
    ? FileManager.default.temporaryDirectory.appendingPathComponent("thumbball-integration-" + UUID().uuidString)
    : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ThumbBall")
let marker: Int64 = 0x5448554D42
let directions = ["→","↘","↓","↙","←","↖","↑","↗","中心"]
func direction(_ x: Double, _ y: Double) -> Int { (Int((atan2(y, x) / (.pi / 4)).rounded()) + 8) % 8 }

final class Controller: NSObject, NSApplicationDelegate {
    var mapping = Mapping()
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var status: NSStatusItem!
    var helpWindow: NSWindow?
    var hud: NSPanel!
    var hudView: DirectionHUD!
    var pageIndex = 0
    var selectedDirection: Int?
    var preview = false
    var feedback = "移动并停顿输入"
    var prefix = ""
    var travel = 0.0
    var testIME = false
    var chinese: ChineseEngine?
    var chineseChoice = 0
    var chineseSymbols = false
    var previousIME = false
    var lastSourceCheck = 0.0
    var chineseActive: Bool { isIME && !chineseSymbols }
    var chineseItems: [String] { chinese?.items ?? [] }
    func clearChinese() { chinese?.clear(); chineseChoice = 0; chineseSymbols = false }
    func chineseCommit() {
        guard let chinese, chinese.ready else { return }
        let text = chinese.takeCommit()
        if !text.isEmpty { emitLiteral(text); chineseChoice = 0 }
    }
    func confirmChinese() {
        resetGesture()
        guard let chinese, chinese.ready, !chineseItems.isEmpty else { return }
        chinese.select(min(chineseChoice, chineseItems.count - 1)); chineseCommit(); chineseChoice = 0; update()
    }
    func scrollChinese(_ step: Int) {
        resetGesture()
        let count = chineseItems.count
        guard count > 0 else { return }
        let next = chineseChoice + step
        if next < 0 {
            if chinese?.page(backward: true) == true { chineseChoice = max(0, chineseItems.count - 1) }
        } else if next >= count {
            if chinese?.page(backward: false) == true { chineseChoice = 0 }
        } else { chineseChoice = next }
        update()
    }
    var isIME: Bool { testing ? testIME : !inputSourceIsASCII() }
    var candidates: [String] { isIME ? [] : completions(prefix) }
    var lastHorizontalScroll = 0.0
    var characterPages: [CharacterPage] {
        if chineseActive {
            return [CharacterPage(layer: -3, offset: 0, values: keypadValues(letterGroups.map { $0.uppercased() }, utility: (chinese?.preedit.isEmpty ?? true) ? "符号" : "清空"))]
        }
        var result = pages(for: mapping)
        if isIME {
            result.removeAll { $0.layer == 0 }
            for index in result.indices { result[index].values[utilitySlot] = "拼音" }
        }
        if !candidates.isEmpty {
            var values = Array(candidates.dropFirst())
            while values.count < 8 { values.append("") }
            values.append(candidates[0])
            result.append(CharacterPage(layer: -2, offset: 0, values: values))
        }
        return result
    }
    var typing = false
    var dx = 0.0, dy = 0.0
    var lastMove = 0.0, lastScroll = 0.0
    var sideHeld = Set<Int64>()
    var physicalHeld = Set<Int64>()
    var swallowed = Set<Int64>()
    var pending: [CGEvent] = []
    var chordStart: Double?
    var chordFired = false
    var combinedPress = false
    var deferredSince: Double?
    var armingMotion = 0.0
    var forwarded = Set<Int64>()
    var testReplay: [CGEventType] = []
    let activationButtons: [Int64] = [0, 1]
    let activationHold = 2.0
    var timer: Timer?
    var logLines: [String] = []
    var testing = false
    var captured: [String] = []
    var integrationPassed = false
    var diagnostic = false
    var anchor = CGPoint.zero
    var lastFlush = 0.0
    let config = support.appendingPathComponent("mapping.json")
    let logURL = support.appendingPathComponent("test.log")
    func log(_ message: String) {
        logLines.append("\(ISO8601DateFormatter().string(from: Date())) \(message)")
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }
    func flush() { try? logLines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: config.path) {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(mapping).write(to: config)
        }
        reload()
        if let resources = Bundle.main.resourceURL {
            chinese = ChineseEngine(shared: resources.appendingPathComponent("Rime"), user: support.appendingPathComponent("Rime"))
        }
        previousIME = isIME
        log("Built-in Chinese engine ready: \(chinese?.ready == true)")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        for (title, action, key) in [("恢复鼠标 / Mouse Mode", #selector(restore), ""), ("开启 Typing Mode", #selector(enterTyping), ""), ("帮助与自检", #selector(help), ""), ("辅助功能权限与重试", #selector(permissions), ""), ("编辑字符映射", #selector(edit), ""), ("重新加载映射", #selector(reload), ""), ("测试日志（切换诊断）", #selector(logs), ""), ("退出 ThumbBall", #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        status.menu = menu
        hud = NSPanel(contentRect: NSRect(x: 0,y: 0,width: 280,height: 224), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.level = .floating; hud.ignoresMouseEvents = true; hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hud.isOpaque = false; hud.backgroundColor = .clear; hud.hasShadow = true
        hudView = DirectionHUD(frame: NSRect(x: 0,y: 0,width: 280,height: 224))
        hud.contentView = hudView
        if let screen = NSScreen.main { hud.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 140,y: screen.visibleFrame.minY + 12)) }
        if !CommandLine.arguments.contains("--integration-test") { startTap() }; update()
        timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(restore), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clearContext), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        log("START Mouse Mode; AX=\(AXIsProcessTrusted()); listen=\(CGPreflightListenEventAccess())")
        flush()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.integrationTest()
            if !CommandLine.arguments.contains("--integration-test") { self.help() }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { help(); return true }
    @objc func help() {
        restore()
        if helpWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 300), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "ThumbBall · 帮助与自检"; w.isReleasedWhenClosed = false
            let t = NSTextField(wrappingLabelWithString: "ThumbBall 1.6 — Mouse Mode\n\n左键和右键同时按住 2 秒切换 Typing。Esc 恢复鼠标。\n标准九宫格：符号 ABC DEF / GHI JKL MNO / PQRS TUV WXYZ。\n左键空格或确认 / 右键退格 / 中键回车。\n滚轮上下：英文翻页、中文选词；左右切换输入法。\n\n中文引擎：\(chinese?.ready == true ? "就绪" : "不可用") · 启动自检：\(integrationPassed ? "通过" : "失败，请查看日志")。\n辅助功能：\(AXIsProcessTrusted()) · 监听：\(tap != nil)\nCGEventTap 会影响所有鼠标和触控板。")
            t.frame = NSRect(x: 24, y: 70, width: 542, height: 206)
            w.contentView?.addSubview(t)
            for (i, pair) in [("权限与重试", #selector(permissions)), ("查看测试日志", #selector(logs)), ("开启打字", #selector(enterTyping)), ("预览提示栏", #selector(previewHUD)), ("退出", #selector(quit))].enumerated() {
                let b = NSButton(title: pair.0, target: self, action: pair.1)
                b.frame = NSRect(x: 10 + i * 116, y: 20, width: 112, height: 32); w.contentView?.addSubview(b)
            }
            helpWindow = w; w.center()
        }
        helpWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func previewHUD() {
        restore(); preview = true; feedback = "仅预览，不输入"; update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.preview else { return }
            self.preview = false; self.update()
        }
    }
    @objc func runTests() { restore(); integrationTest() }
    func integrationTest() {
        testing = true; captured.removeAll()
        var passed = true
        func check(_ value: Bool, _ name: String) { if !value { passed = false; log("FAIL: " + name) } }
        check(!typing, "initial mouse mode")
        var trackingTicks = 0
        let trackingProbe = Timer(timeInterval: 0.005, repeats: true) { _ in trackingTicks += 1 }
        RunLoop.main.add(trackingProbe, forMode: .common)
        let trackingDeadline = Date(timeIntervalSinceNow: 0.05)
        while trackingTicks == 0 && Date() < trackingDeadline {
            RunLoop.main.run(mode: .eventTracking, before: trackingDeadline)
        }
        trackingProbe.invalidate()
        check(trackingTicks > 0, "common-mode timer fires during mouse event tracking")
        let mouse = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: .zero, mouseButton: .left)!
        check(handle(.leftMouseDown, mouse), "mouse down deferred for chord")
        check(handle(.leftMouseUp, mouseUp), "mouse click replayed on release")
        check(testReplay == [.leftMouseDown, .leftMouseUp], "single click down/up replay pair")
        testReplay.removeAll()
        _ = handle(.leftMouseDown, mouse)
        let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: .zero, mouseButton: .left)!
        drag.setIntegerValueField(.mouseEventDeltaX, value: 20)
        check(handle(.leftMouseDragged, drag), "drag replays deferred down before drag")
        check(!handle(.leftMouseUp, mouseUp), "drag release passes through")
        check(testReplay == [.leftMouseDown, .leftMouseDragged], "drag preserves event order")
        testReplay.removeAll()
        // Exercise the real chord state machine without posting any OS input.
        func side(_ button: Int64, _ down: Bool) {
            let type: CGEventType = button == 0 ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: button)
            _ = handle(type, event)
        }
        side(activationButtons[0], true)
        deferredSince = ProcessInfo.processInfo.systemUptime - 0.8
        tick()
        check(forwarded.isEmpty && !pending.isEmpty, "late second finger remains eligible after 800ms")
        let jitter = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: .zero, mouseButton: .left)!
        jitter.setIntegerValueField(.mouseEventDeltaX, value: 2)
        _ = handle(.leftMouseDragged, jitter)
        check(forwarded.isEmpty, "small trackball jitter does not cancel activation")
        side(activationButtons[1], true)
        chordStart = ProcessInfo.processInfo.systemUptime - activationHold + 0.02
        tick(); check(!typing, "chord must wait full duration")
        chordStart = ProcessInfo.processInfo.systemUptime - activationHold - 0.02
        tick(); check(typing, "chord toggles typing")
        tick(); check(typing, "held chord triggers once")
        side(activationButtons[0], false); side(activationButtons[1], false)
        check(testReplay.isEmpty, "activation chord causes no mouse click")
        for expected in [false, true] {
            side(0, true); side(1, true)
            chordStart = ProcessInfo.processInfo.systemUptime - activationHold - 0.02
            tick(); check(typing == expected, "left/right two-second mode toggle")
            side(0, false); side(1, false)
        }
        check(testReplay.isEmpty, "toggle releases produce no click")
        let beforeShortChord = pageIndex
        side(0, true); side(1, true); side(0, false); side(1, false)
        check(typing && pageIndex == beforeShortChord, "short combined press does not toggle or page")
        for b in 0...2 {
            let event = CGEvent(mouseEventSource: nil, mouseType: b == 0 ? .leftMouseDown : b == 1 ? .rightMouseDown : .otherMouseDown, mouseCursorPosition: .zero, mouseButton: CGMouseButton(rawValue: UInt32(b))!)!
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(b))
            check(handle(b == 0 ? .leftMouseDown : b == 1 ? .rightMouseDown : .otherMouseDown, event), "typing click swallowed")
            check(handle(b == 0 ? .leftMouseUp : b == 1 ? .rightMouseUp : .otherMouseUp, event), "typing release swallowed")
        }
        check(captured == ["key:49", "key:51", "key:36"] && pageIndex == 0, "left Space / right Backspace / middle Enter")
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        lastScroll = 0; pageIndex = 0
        check(handle(.scrollWheel, wheel), "wheel swallowed")
        check(pageIndex == characterPages.count - 1, "wheel previous page wraps")
        changePage(1); check(pageIndex == 0, "page next wraps")
        travel = 100; dx = 100; dy = 0; lastMove = ProcessInfo.processInfo.systemUptime - mapping.idleMilliseconds / 1000 - 0.02
        tick(); check(captured.last == pages(for: mapping)[0].values[0], "single direction emits character")
        pageIndex = 1
        travel = 100; dx = 100; dy = 0; lastMove = ProcessInfo.processInfo.systemUptime - mapping.idleMilliseconds / 1000 - 0.02
        tick(); check(captured.last == pages(for: mapping)[1].values[0], "next page has next nine characters")
        travel = 100; dx = 100; dy = 0; lastMove = ProcessInfo.processInfo.systemUptime
        changePage(1); check(dx == 0 && lastMove == 0, "page change cancels pending character")
        pageIndex = 0
        let expectedCenter = characterPages[0].values[8]
        travel = 100; dx = 0; dy = 0; lastMove = ProcessInfo.processInfo.systemUptime - mapping.idleMilliseconds / 1000 - 0.02
        tick(); check(captured.last == (expectedCenter == "␣ Space" ? "key:49" : expectedCenter), "return to center emits ninth entry")
        let countBefore = captured.count
        tick(); check(captured.count == countBefore, "stationary center does not repeat")
        prefix = "hel"; pageIndex = characterPages.count - 1
        let word = candidates[0]
        chooseEntry(word, completing: true)
        check(captured.suffix(2) == [String(word.dropFirst(3)), "key:49"], "whole word completion emits suffix and space")
        check(prefix.isEmpty && pageIndex == 0, "word completion resets context")
        captured.removeAll()
        for entry in ["␣ Space", "⌫ Backspace", "↵ Enter", "⇥ Tab"] { sendEntry(entry) }
        check(captured == ["key:49", "key:51", "key:36", "key:48"], "special keys on character pages")
        resetGesture(); captured.removeAll()
        let horizontal = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 0, wheel2: 1, wheel3: 0)!
        lastHorizontalScroll = 0
        check(handle(.scrollWheel, horizontal), "horizontal tilt swallowed")
        check(captured == ["ime:previous"] && pageIndex == 0, "horizontal tilt switches input source without paging")
        _ = handle(.scrollWheel, horizontal)
        check(captured.count == 1, "horizontal tilt debounce")
        testIME = true; captured.removeAll()
        emit(text: "a"); emit(text: "z")
        check(captured == ["a", "z"], "final Unicode commits bypass system letter composition")
        check(candidates.isEmpty, "English completions disabled in non-ASCII IME")
        testIME = false; captured.removeAll()
        anchor = CGEvent(source: nil)?.location ?? .zero
        typing = true
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!
        move.location = anchor
        move.setIntegerValueField(.mouseEventDeltaX, value: 50)
        check(handle(.mouseMoved, move), "movement swallowed")
        check(dx == 50, "movement delta: \(dx)")
        move.setIntegerValueField(.eventSourceUserData, value: marker)
        check(!handle(.mouseMoved, move), "synthetic isolation")
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        check(handle(.keyDown, escape), "escape swallowed"); check(!typing, "escape restores")
        typing = true; swallowed.insert(0); restore()
        check(handle(.leftMouseUp, mouseUp), "paired release"); check(swallowed.isEmpty, "paired state cleared")
        typing = true
        _ = handle(.tapDisabledByTimeout, move)
        // A marked event bypasses filtering; use an unmarked event for failure test.
        move.setIntegerValueField(.eventSourceUserData, value: 0)
        _ = handle(.tapDisabledByTimeout, move)
        check(!typing, "tap recovery")
        print("\(passed ? "PASS" : "FAIL"): AppKit startup, Mouse Mode passthrough, movement suppression, synthetic-event isolation, Esc recovery, balanced button-up, tap failure recovery")
        print("Permissions: AX=\(AXIsProcessTrusted()), listen=\(CGPreflightListenEventAccess()), tap=\(tap != nil)")
        testing = false; prefix = ""; pageIndex = 0; feedback = "移动并停顿输入"; captured.removeAll()
        integrationPassed = passed
        log("\(passed ? "PASS" : "FAIL"): AppKit event integration tests; common-mode timer during mouse tracking, 2-second left/right chord, delayed second finger and jitter tolerance, held chord debounce, Space/Backspace/Enter click mapping, horizontal input-source switch/debounce, Chinese commit Unicode route, wheel page wrap, nine-slot ring selection, center no-repeat, word completion, page cancellation, Mouse passthrough, movement filter, synthetic isolation, Esc, button pairing, tap failure")
        flush()
        if CommandLine.arguments.contains("--integration-test") { quit() }
    }
    @objc func reload() {
        do {
            let candidate = try JSONDecoder().decode(Mapping.self, from: Data(contentsOf: config))
            guard candidate.valid() else { throw NSError(domain: "Invalid mapping", code: 1) }
            if typing { restore() }
            replayPending(); sideHeld.removeAll(); chordStart = nil
            mapping = candidate; prefix = ""; pageIndex = 0; log("Mapping loaded")
        } catch { log("Mapping rejected: \(error)"); if status != nil { let a = NSAlert(); a.messageText = "映射文件无效，保留原映射"; a.informativeText = String(describing: error); a.runModal() } }
    }
    func startTap() {
        if tap != nil { return }
        let types: [CGEventType] = [.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp,.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.scrollWheel,.keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<Controller>.fromOpaque(pointer).takeUnretainedValue()
            return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap { source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0); CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true); log("Tap active") }
        else { log("Tap unavailable; Mouse Mode"); typing = false }
    }
    @objc func permissions() {
        restore()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startTap(); update()
        let a = NSAlert(); a.messageText = "ThumbBall 权限"; a.informativeText = "在辅助功能中启用 ThumbBall。若监听仍失败，也请检查隐私与安全性 → 输入监控。授权后退出并重开，或再次选择本菜单。当前辅助功能：\(AXIsProcessTrusted())；监听：\(tap != nil)。Logi Options+ 须保留原始横向滚动事件。"; a.runModal()
    }
    func changePage(_ step: Int) {
        resetGesture()
        if chineseActive { scrollChinese(step); return }
        pageIndex = (pageIndex + step + characterPages.count) % characterPages.count
        feedback = "移动并停顿输入"
        log("Page \(pageIndex + 1)/\(characterPages.count)")
        update()
    }
    func update() {
        status?.button?.title = typing ? "TB ⌨ \(pageIndex + 1)/\(characterPages.count)" : "TB 🖱\(tap == nil ? " !" : "")"
        guard typing || preview else { hud?.orderOut(nil); return }
        guard hudView != nil else { return }
        if pageIndex >= characterPages.count { pageIndex = 0 }
        let page = characterPages[pageIndex]
        let title = page.layer == -3 ? "中文九键" : page.layer == -2 ? "联想词" : page.layer == -1 ? "编辑键" : page.layer == 0 ? "字母" : page.layer == 1 ? "数字 / 标点" : "符号 · 层 \(page.layer + 1)"
        let layerPages = characterPages.filter { $0.layer == page.layer }.count
        hudView.values = page.values; hudView.selected = selectedDirection; hudView.showLetterGroups = page.layer == 0
        hudView.heading = "\(preview ? "预览" : "TB")\(isIME ? " · 中文" : " · EN") · \(title) \(page.offset / 9 + 1)/\(layerPages)"
        hudView.center = feedback
        let suggestion = candidates.prefix(3).joined(separator: " · ")
        hudView.footer = suggestion.isEmpty ? "上下翻页 · 左右切输入法 · Esc恢复\n左键空格 · 右键退格 · 中键回车" : "联想：\(suggestion)\n上滚至联想词页选择补全 · Esc恢复"
        if chineseActive {
            let items = chineseItems
            let first = max(0, min(chineseChoice - 1, items.count - 3))
            let shown = items.indices.filter { $0 >= first && $0 < first + 3 }.map { ($0 == chineseChoice ? "【" : "") + items[$0] + ($0 == chineseChoice ? "】" : "") }.joined(separator: " · ")
            hudView.footer = chinese?.ready == true ? "\(chinese?.preedit ?? "")  \(shown)\n上下选词 · 左键确认 · 右键退格 · 中键回车" : "中文引擎不可用，请恢复鼠标查看日志"
        } else if isIME { hudView.footer = "中文符号页 · 左上返回拼音\n上下翻页 · 左键空格 · 右键退格" }
        if preview { hudView.footer = "仅预览，不输入 · 12秒自动隐藏\n标准九宫格 · 中心 JKL" }
        hudView.setAccessibilityElement(true)
        hudView.setAccessibilityLabel(hudView.heading + " " + page.values.enumerated().map { directions[$0.offset] + " " + $0.element }.joined(separator: ", "))
        hudView.needsDisplay = true; hud.orderFrontRegardless()
    }
    func resetGesture() { travel = 0; dx = 0; dy = 0; lastMove = 0; selectedDirection = nil }
    @objc func restore() { if !sideHeld.isEmpty && forwarded.isEmpty { chordFired = true; pending.removeAll() }; clearChinese(); prefix = ""; pageIndex = 0; typing = false; preview = false; resetGesture(); log("Mouse Mode"); update() }
    @objc func enterTyping() {
        guard (testing || (tap != nil && AXIsProcessTrusted())), physicalHeld.isEmpty, (sideHeld.isEmpty || (chordFired && sideHeld.count == 2)) else { log("Typing refused: permission/tap/held button"); return }
        preview = false; feedback = "移动并停顿输入"; anchor = CGEvent(source: nil)?.location ?? .zero; typing = true; resetGesture(); log("Typing Mode"); update()
    }
    @objc func clearContext() { clearChinese(); prefix = ""; pageIndex = 0; resetGesture(); update() }
    @objc func edit() { restore(); NSWorkspace.shared.open(config) }
    @objc func logs() { restore(); diagnostic.toggle(); log("Diagnostics \(diagnostic); button IDs only; character content never logged"); flush(); NSWorkspace.shared.open(logURL) }
    @objc func quit() { restore(); replayPending(); flush(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { if let tap { CGEvent.tapEnable(tap: tap, enable: false) }; chinese = nil; flush() }
    func replayPending() {
        for e in pending {
            if testing { testReplay.append(e.type) }
            else { e.setIntegerValueField(.eventSourceUserData, value: marker); e.post(tap: .cgSessionEventTap) }
        }
        pending.removeAll()
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastFlush > 3 { flush(); lastFlush = now }
        if !testing && now - lastSourceCheck > 0.3 {
            lastSourceCheck = now
            let currentIME = isIME
            if currentIME != previousIME { previousIME = currentIME; clearContext() }
        }
        if typing && !testing && !AXIsProcessTrusted() { restore() }
        if !testing, let tap, !CGEvent.tapIsEnabled(tap: tap) { swallowed.formUnion(sideHeld.subtracting(forwarded)); restore(); pending.removeAll(); sideHeld.removeAll(); chordStart = nil; deferredSince = nil; chordFired = false; combinedPress = false; CGEvent.tapEnable(tap: tap, enable: true); log("Watchdog restored Mouse Mode") }
        if let start = chordStart, !chordFired, forwarded.isEmpty, sideHeld.count == 2, now - start >= activationHold {
            chordFired = true; pending.removeAll()
            if typing { restore() } else { enterTyping() }
        }
        if typing, lastMove > 0, now - lastMove >= mapping.idleMilliseconds / 1000 {
            let x = dx, y = dy
            let armed = travel >= mapping.gestureThreshold
            lastMove = 0
            if armed {
                let d = hypot(x,y) < mapping.gestureThreshold * 0.65 ? 8 : direction(x,y)
                let page = characterPages[pageIndex]
                resetGesture()
                if page.values.indices.contains(d), !page.values[d].isEmpty {
                    if chineseActive {
                        if d == utilitySlot {
                            if chinese?.preedit.isEmpty ?? true { chineseSymbols = true; pageIndex = 0 }
                            else { chinese?.clear(); chineseChoice = 0 }
                        } else if let group = keypadSlots.firstIndex(of: d), chinese?.ready == true {
                            chinese?.key(Int32(50 + group)); chineseChoice = 0; chineseCommit()
                        }
                    } else if d == utilitySlot && page.layer != -2 {
                        if isIME { chineseSymbols = false; pageIndex = 0 }
                        else if page.layer == 0 { pageIndex = characterPages.firstIndex { $0.layer > 0 } ?? 0 }
                        else { pageIndex = 0 }
                    } else { chooseEntry(page.values[d], completing: page.layer == -2) }
                    feedback = "已输入"
                }
                update()
            }
        }
    }
    func chooseEntry(_ text: String, completing: Bool) {
        if completing && text.hasPrefix(prefix) && !prefix.isEmpty {
            emit(text: String(text.dropFirst(prefix.count))); emit(key: 49)
            prefix = ""; pageIndex = 0
        } else {
            let wasLetters = characterPages[pageIndex].layer == 0
            sendEntry(text)
            if wasLetters && pageIndex >= characterPages.count { pageIndex = 0 }
        }
    }
    func sendEntry(_ text: String) {
        if chineseActive {
            switch text {
            case "␣ Space":
                if !(chinese?.preedit.isEmpty ?? true) { confirmChinese() } else { emit(key: 49) }
            case "⌫ Backspace":
                if !(chinese?.preedit.isEmpty ?? true) { chinese?.key(0xff08); chineseChoice = 0; chineseCommit() } else { emit(key: 51) }
            case "↵ Enter":
                if !(chinese?.preedit.isEmpty ?? true) {
                    if chineseItems.isEmpty { chinese?.clear() } else { confirmChinese() }
                }
                emit(key: 36)
            default: emitLiteral(text)
            }
            return
        }
        if isIME { prefix = "" }
        else if text == "⌫ Backspace" { if !prefix.isEmpty { prefix.removeLast() } }
        else if !text.isEmpty && text.allSatisfy({ $0.isASCII && $0.isLetter }) { prefix = String((prefix + text.lowercased()).suffix(32)) }
        else { prefix = "" }
        if pageIndex >= characterPages.count { pageIndex = 0 }
        switch text {
        case "␣ Space": emit(key: 49)
        case "⌫ Backspace": emit(key: 51)
        case "↵ Enter": emit(key: 36)
        case "⇥ Tab": emit(key: 48)
        default: emit(text: text)
        }
    }
    func emitLiteral(_ text: String) { emit(text: text) }
    func emit(text: String? = nil, key: CGKeyCode = 0) {
        let imeKey: CGKeyCode? = nil
        let actualKey = imeKey ?? key
        if testing { captured.append(imeKey == nil ? (text ?? "key:\(key)") : "key:\(actualKey)"); return }
        guard typing, AXIsProcessTrusted() else { restore(); return }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: actualKey, keyDown: down) else { restore(); return }
            e.flags = []; e.setIntegerValueField(.eventSourceUserData, value: marker)
            if let text, imeKey == nil { let utf = Array(text.utf16); utf.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength: utf.count, unicodeString: $0.baseAddress) } }
            e.post(tap: .cgSessionEventTap)
        }
        log("Input emitted (content omitted)")
    }
    func switchInputSource(_ step: Int) {
        resetGesture(); clearChinese(); prefix = ""; pageIndex = 0
        if testing { captured.append(step < 0 ? "ime:previous" : "ime:next"); return }
        guard let all = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource],
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { log("Input source list unavailable"); return }
        let sources = all.filter {
            (sourceProperty($0, kTISPropertyInputSourceIsEnabled) as? NSNumber)?.boolValue == true &&
            (sourceProperty($0, kTISPropertyInputSourceIsSelectCapable) as? NSNumber)?.boolValue == true &&
            (sourceProperty($0, kTISPropertyInputSourceCategory) as? String) == (kTISCategoryKeyboardInputSource as String)
        }
        guard sources.count > 1 else { log("Only one enabled keyboard input source"); return }
        let currentID = sourceProperty(current, kTISPropertyInputSourceID) as? String
        let index = sources.firstIndex { (sourceProperty($0, kTISPropertyInputSourceID) as? String) == currentID } ?? 0
        let target = sources[(index + step + sources.count) % sources.count]
        let result = TISSelectInputSource(target)
        log("Input source switch status \(result)")
        update()
    }
    func handle(_ type: CGEventType, _ e: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { swallowed.formUnion(sideHeld.subtracting(forwarded)); restore(); pending.removeAll(); sideHeld.removeAll(); chordStart = nil; chordFired = false; log("Tap disabled: fail open"); return false }
        if e.getIntegerValueField(.eventSourceUserData) == marker { return false }
        if type == .keyDown {
            if e.getIntegerValueField(.keyboardEventKeycode) == 53 && (typing || preview || !sideHeld.isEmpty) { restore(); return true }
            if !prefix.isEmpty || !(chinese?.preedit.isEmpty ?? true) { clearContext() }
            return false
        }
        let down = [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type)
        let up = [.leftMouseUp,.rightMouseUp,.otherMouseUp].contains(type)
        let button = e.getIntegerValueField(.mouseEventButtonNumber)
        if (down || up) && activationButtons.contains(button) {
            if diagnostic { log("Activation button \(button) \(down ? "down" : "up")") }
            if up && swallowed.remove(button) != nil { return true }
            if down {
                if sideHeld.isEmpty { armingMotion = 0 }
                sideHeld.insert(button)
                if !forwarded.isEmpty { forwarded.insert(button); return false }
                if chordFired { return true }
                if !typing, let copy = e.copy() { pending.append(copy) }
                if sideHeld.count == 2 { combinedPress = true; chordStart = ProcessInfo.processInfo.systemUptime; deferredSince = nil; log("Activation armed: both buttons held; waiting 2 seconds") }
                else { deferredSince = ProcessInfo.processInfo.systemUptime }
                resetGesture()
                return true
            }
            sideHeld.remove(button)
            chordStart = nil; deferredSince = nil
            if forwarded.remove(button) != nil {
                if sideHeld.isEmpty { chordFired = false; combinedPress = false }
                return false
            }
            if !chordFired {
                if typing {
                    if !combinedPress { sendEntry(button == 0 ? "␣ Space" : "⌫ Backspace"); update() }
                } else {
                    if let copy = e.copy() { pending.append(copy) }
                    replayPending(); forwarded.formUnion(sideHeld)
                }
            }
            if sideHeld.isEmpty { chordFired = false; combinedPress = false }
            return true
        }
        if typing && (down || up) && [Int64(5), Int64(6)].contains(button) {
            if down && !swallowed.contains(button) { swallowed.insert(button); switchInputSource(button == 5 ? -1 : 1) }
            if up { swallowed.remove(button) }
            return true
        }
        if down || up {
            if down { physicalHeld.insert(button) } else { physicalHeld.remove(button) }
            if diagnostic { log("Button \(button) \(down ? "down" : "up")") }
            if up && swallowed.remove(button) != nil { return true }
            if typing && down { swallowed.insert(button); resetGesture(); if button == 2 { prefix = ""; pageIndex = 0; sendEntry("↵ Enter") }; update(); return true }
        }
        if !typing && [.leftMouseDragged, .rightMouseDragged].contains(type) && !pending.isEmpty && sideHeld.count == 1 {
            armingMotion += hypot(Double(e.getIntegerValueField(.mouseEventDeltaX)), Double(e.getIntegerValueField(.mouseEventDeltaY)))
            if armingMotion < 12 { return true }
            replayPending(); forwarded.formUnion(sideHeld); deferredSince = nil; chordStart = nil
            if let copy = e.copy() { pending.append(copy); replayPending() }
            return true
        }
        guard typing else { return false }
        if !sideHeld.isEmpty { return true }
        if [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type) {
            let mx = Double(e.getIntegerValueField(.mouseEventDeltaX))
            let my = Double(e.getIntegerValueField(.mouseEventDeltaY))
            if mx != 0 || my != 0 {
                dx += mx; dy += my; travel += hypot(mx,my)
                let limit = mapping.gestureThreshold * 3
                let radius = hypot(dx,dy)
                if radius > limit { dx *= limit / radius; dy *= limit / radius }
                lastMove = ProcessInfo.processInfo.systemUptime
                if travel >= mapping.gestureThreshold {
                    let candidate = hypot(dx,dy) < mapping.gestureThreshold * 0.65 ? 8 : direction(dx,dy)
                    if selectedDirection != candidate { selectedDirection = candidate; feedback = "停顿输入"; update() }
                }
            }
            if !testing && e.location != anchor { CGWarpMouseCursorPosition(anchor) }
            return true
        }
        if type == .scrollWheel {
            let horizontal = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            if horizontal != 0 {
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastHorizontalScroll > 0.4 { lastHorizontalScroll = now; switchInputSource(horizontal > 0 ? -1 : 1) }
                return true
            }
            let delta = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let now = ProcessInfo.processInfo.systemUptime
            if delta != 0 && now - lastScroll > 0.25 { lastScroll = now; changePage(delta > 0 ? -1 : 1) }
            return true
        }
        return false
    }
}

if CommandLine.arguments.contains("--self-test") {
    let m = Mapping()
    precondition(m.valid())
    precondition((0..<8).map { direction(cos(Double($0) * .pi / 4) * 100, sin(Double($0) * .pi / 4) * 100) } == Array(0..<8))
    let letters = (0..<8).flatMap { g in (0..<8).compactMap { m.character(layer: 0, group: g, direction: $0) } }.joined()
    precondition(letters == "abcdefghijklmnopqrstuvwxyz")
    precondition(try! JSONDecoder().decode(Mapping.self, from: JSONEncoder().encode(m)).valid())
    var invalid = m; invalid.sideButtons = [3,3]; precondition(!invalid.valid())
    invalid = m; invalid.layers = [Array(repeating: "x", count: 65)]; precondition(!invalid.valid())
    let alphaPages = pages(for: m).filter { $0.layer == 0 }
    let pagedLetters = alphaPages.flatMap { $0.values.filter { $0.count == 1 } }
    precondition(Set(pagedLetters) == Set(letters.map(String.init)))
    precondition(alphaPages.count == 4 && pagedLetters.count == 26)
    for (column, page) in alphaPages.enumerated() {
        for group in 0..<8 {
            let letters = Array(letterGroups[group])
            precondition(page.values[keypadSlots[group]] == (column < letters.count ? String(letters[column]) : ""))
        }
    }
    precondition(pages(for: m).allSatisfy { $0.values.count == 9 })
    precondition(completions("hel").contains("hello"))
    precondition(completions("").isEmpty && completions("zzzz").isEmpty)
    print("PASS: eight directions + center, 26 unique letters on four fixed-group pages, local word completions, JSON roundtrip, invalid mappings")
} else if CommandLine.arguments.contains("--rime-self-test") {
    let user = FileManager.default.temporaryDirectory.appendingPathComponent("thumbball-rime-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: user) }
    let engine = ChineseEngine(shared: Bundle.main.resourceURL!.appendingPathComponent("Rime"), user: user)
    precondition(engine.ready, "Rime schema initialization")
    for (digits, expected) in [("64426", "你好"), ("94664486", "中国"), ("74878", "输入")] {
        engine.clear()
        for digit in digits.utf8 { engine.key(Int32(digit)) }
        precondition(engine.items.contains(expected), "T9 candidate missing: " + expected)
        let initial = engine.preedit
        engine.key(0xff08)
        precondition(engine.preedit != initial, "Backspace edits composition")
        engine.clear()
        for digit in digits.utf8 { engine.key(Int32(digit)) }
        let index = engine.items.firstIndex(of: expected)!
        engine.select(index)
        precondition(engine.takeCommit() == expected, "Selected candidate commit")
        precondition(engine.preedit.isEmpty, "Composition cleared after commit")
    }
    engine.clear(); for digit in "64426".utf8 { engine.key(Int32(digit)) }
    precondition(!engine.items.isEmpty)
    let firstCandidate = engine.items[0]
    precondition(engine.page(backward: false), "next candidate page exists")
    precondition(engine.items[0] != firstCandidate, "candidate page changed")
    precondition(engine.page(backward: true) && engine.items[0] == firstCandidate, "previous candidate page restored")
    engine.clear(); precondition(engine.preedit.isEmpty && engine.items.isEmpty)
    for digit in "999999999999".utf8 { engine.key(Int32(digit)) }
    precondition(engine.items.isEmpty, "Unknown code should not commit")
    engine.clear(); precondition(engine.takeCommit().isEmpty)
    let controller = Controller()
    controller.testing = true; controller.testIME = true; controller.typing = true; controller.chinese = engine
    controller.lastFlush = ProcessInfo.processInfo.systemUptime + 3600
    for d in [0, 4, 4, 6, 0] {
        controller.travel = 100
        controller.dx = cos(Double(d) * .pi / 4) * 100
        controller.dy = sin(Double(d) * .pi / 4) * 100
        controller.lastMove = ProcessInfo.processInfo.systemUptime - 1
        controller.tick()
    }
    precondition(engine.items.contains("你好"), "gesture directions produce T9 code")
    controller.scrollChinese(1); precondition(controller.chineseChoice == 1, "wheel chooses next candidate")
    controller.scrollChinese(-1); precondition(controller.chineseChoice == 0, "wheel chooses previous candidate")
    controller.sendEntry("⌫ Backspace"); precondition(controller.captured.isEmpty && engine.preedit != "", "composition backspace stays local")
    controller.chinese?.key(54)
    controller.sendEntry("␣ Space")
    precondition(controller.captured == ["你好"], "left click commits selected Chinese without extra space")
    controller.sendEntry("⌫ Backspace"); controller.sendEntry("↵ Enter")
    precondition(controller.captured.suffix(2) == ["key:51", "key:36"], "empty composition editing keys")
    engine.key(54); controller.clearContext()
    precondition(engine.preedit.isEmpty, "focus/mode reset cancels pending Chinese")
    for d in [8, 4] {
        controller.travel = 100
        controller.dx = d == 8 ? 0 : -100; controller.dy = 0
        controller.lastMove = ProcessInfo.processInfo.systemUptime - 1; controller.tick()
    }
    precondition(engine.preedit.filter { $0.isNumber } == "54", "center JKL and left GHI T9 mapping")
    controller.clearContext()
    precondition(keypadReadingOrder.map { keypadValues(letterGroups.map { $0.uppercased() }, utility: "符号")[$0] } == ["符号", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"])
    print("PASS: standard nine-key row order and center JKL gesture mapping")
    print("PASS: ThumbBall gesture-to-T9, wheel selection, local composition backspace, Chinese Unicode commit and editing keys (no OS input posted)")
    print("PASS: real librime T9 decoding, Chinese dictionary, candidate selection/commit, backspace, paging, clear, unknown code; isolated temporary user dictionary")
} else {
    let app = NSApplication.shared
    let delegate = Controller()
    app.setActivationPolicy(.accessory); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
