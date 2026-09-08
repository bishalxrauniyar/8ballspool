import AppKit
import AVFoundation
import Carbon.HIToolbox
import QuartzCore

// MARK: - Math helpers

private extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var len: CGFloat { hypot(x, y) }
    var norm: CGPoint { let l = max(len, 0.0001); return CGPoint(x: x / l, y: y / l) }
    func dist(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
}

private extension CGColor {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - Procedural sound (in-memory WAV + AVAudioPlayer; no engine graph, exception-proof)

final class SFX {
    static let shared = SFX()
    private let sr = 44100
    private var cache: [String: Data] = [:]
    private var lastClack: Double = 0
    private var lastCush: Double = 0
    var enabled: Bool { UserDefaults.standard.object(forKey: "pool8.sound") as? Bool ?? true }

    private init() { }

    private func wav(_ key: String, dur: Double, gen: (Double) -> Double) {
        guard cache[key] == nil else { return }
        let frames = Int(dur * Double(sr))
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let v = Int16(max(-1, min(1, gen(Double(i) / Double(sr)))) * 32000)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + pcm.count)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(pcm.count)); d.append(pcm)
        cache[key] = d
    }

    private func play(_ key: String, _ gain: Float) {
        guard enabled, let data = cache[key] else { return }
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.volume = gain
        p.delegate = PlayerPool.shared
        PlayerPool.shared.retain(p)
        p.play()
    }

    private final class PlayerPool: NSObject, AVAudioPlayerDelegate {
        static let shared = PlayerPool()
        private var players: [AVAudioPlayer] = []
        func retain(_ p: AVAudioPlayer) {
            players.append(p)
            if players.count > 24 { players.removeAll { !$0.isPlaying } }
        }
        func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
            players.removeAll { $0 === p }
        }
    }

    func strike(_ power: Double) {
        wav("strike", dur: 0.06) { t in
            Double.random(in: -0.5...0.5) * exp(-t * 150) * 0.8
            + sin(2 * .pi * 1300 * t) * exp(-t * 180) * 0.3
        }
        play("strike", Float(0.3 + 0.5 * power))
    }

    func clack(_ strength: Double) {
        let now = CACurrentMediaTime()
        guard now - lastClack > 0.03 else { return }
        lastClack = now
        wav("clack", dur: 0.05) { t in
            sin(2 * .pi * 2600 * t) * exp(-t * 90) * 0.55
            + Double.random(in: -0.5...0.5) * exp(-t * 220) * 0.45
        }
        play("clack", Float(0.22 + 0.68 * strength))
    }

    func cushion() {
        let now = CACurrentMediaTime()
        guard now - lastCush > 0.05 else { return }
        lastCush = now
        wav("cushion", dur: 0.09) { t in
            sin(2 * .pi * 165 * t) * exp(-t * 38) * 0.75
            + Double.random(in: -0.5...0.5) * exp(-t * 130) * 0.15
        }
        play("cushion", 0.6)
    }

    func pocket() {
        var phase = 0.0
        wav("pocket", dur: 0.3) { t in
            let f = max(680 - 1300 * t, 260)
            phase += 2 * .pi * f / 44100.0
            return sin(phase) * exp(-t * 12) * 0.7
                + Double.random(in: -0.5...0.5) * exp(-t * 26) * 0.25
        }
        play("pocket", 0.7)
    }

    func fanfare(_ notes: [Double], step: Double) {
        let key = "fan\(notes.count)-\(Int(step * 100))"
        wav(key, dur: 1.0) { t in
            var s = 0.0
            for (i, f) in notes.enumerated() {
                let tt = t - Double(i) * step
                if tt >= 0 {
                    s += (sin(2 * .pi * f * tt) + 0.35 * sin(4 * .pi * f * tt)) * exp(-tt * 5) * 0.5
                }
            }
            return s
        }
        play(key, 0.75)
    }
}

// MARK: - Global hotkeys: Ctrl+Option+P show/hide, Ctrl+Option+N new game

enum HotKey {
    static var onToggle: (() -> Void)?
    static var onNewGame: (() -> Void)?
    private static var ref1: EventHotKeyRef?
    private static var ref2: EventHotKeyRef?
    static func register() {
        var et = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { event, _, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if hk.id == 1 { HotKey.onToggle?() }
            else if hk.id == 2 { HotKey.onNewGame?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &et, nil, nil)
        var hk1 = EventHotKeyID(signature: OSType(0x504F4F4C), id: 1) // 'POOL'
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), hk1, GetApplicationEventTarget(), 0, &ref1)
        var hk2 = EventHotKeyID(signature: OSType(0x504F4F4C), id: 2)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), hk2, GetApplicationEventTarget(), 0, &ref2)
    }
}

// MARK: - Game: fullscreen transparent overlay, the table floats over the desktop

final class GameView: NSView {
    private enum Phase { case aim, roll, over }
    private enum Group { case solids, stripes }

    private struct Ball {
        var num: Int   // 0 = cue
        var p: CGPoint
        var v: CGPoint
        var on: Bool = true
    }

    private static let RAIL: CGFloat = 30
    private static let CUSH: CGFloat = 14
    private static let REST_C: CGFloat = 0.72    // cushion restitution
    private static let REST_B: CGFloat = 0.95    // ball-ball restitution
    private static let FRICTION: CGFloat = 0.9
    private static let STOP: CGFloat = 8
    private static let GRAB: CGFloat = 76        // grab radius around the cue ball
    private static let MAXDRAG: CGFloat = 280
    private static let MAXSPEED: CGFloat = 3500

    private var phase: Phase = .aim
    private var turn = 0
    private var groups: [Group?] = [nil, nil]
    private var shotCount = 0
    private var potted: [Int] = []
    private var cueScratch = false
    private var contacted = false
    private var groupLeftAtShotStart = -1
    private var winner: Int?
    private var wins: [Int] = [0, 0]

    private var table = CGRect.zero
    private var play = CGRect.zero
    private var pockets: [(c: CGPoint, r: CGFloat)] = []
    private var cornerMouth: CGFloat = 0
    private var sideMouth: CGFloat = 0

    private var balls: [Ball] = []
    private var sinkAnims: [(num: Int, from: CGPoint, to: CGPoint, t: CGFloat)] = []

    private var drag: CGPoint?
    private var lastT: CFTimeInterval = 0
    private var seqActive = false
    private var monitors: [Any] = []

    private var bannerText = ""
    private var bannerSub = ""
    private var bannerStart: CFTimeInterval = 0
    private var bannerUntil: CFTimeInterval = 0

    private var link: CADisplayLink?

    private var BR: CGFloat { play.width / 82 }

    var cuePoint: CGPoint { balls.first?.p ?? .zero }
    private var headSpot: CGPoint { CGPoint(x: play.minX + play.width * 0.25, y: play.midY) }
    private var footSpot: CGPoint { CGPoint(x: play.maxX - play.width * 0.25, y: play.midY) }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wins = [
            UserDefaults.standard.object(forKey: "pool8.wins0") as? Int ?? 0,
            UserDefaults.standard.object(forKey: "pool8.wins1") as? Int ?? 0,
        ]
        buildGeometry()
        rack()
        let l = makeDisplayLink(selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeDisplayLink(selector: Selector) -> CADisplayLink {
        if #available(macOS 14.0, *) {
            return displayLink(target: self, selector: selector)
        }
        fatalError("8BallsPool requires macOS 14+")
    }

    override func hitTest(_ p: NSPoint) -> NSView? {
        return nil // the overlay window ignores events; a separate handle window near the cue ball handles input
    }

    override func acceptsFirstMouse(for n: NSEvent?) -> Bool { true }

    // MARK: Geometry

    private var courseFrame: NSRect {
        NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
    }

    private func buildGeometry() {
        let f = courseFrame
        let w = max(720, min(f.width * 0.8, (f.height - 170) * 2))
        let h = w / 2
        table = CGRect(x: f.midX - w / 2, y: f.midY - h / 2 - 14, width: w, height: h)
        play = table.insetBy(dx: Self.RAIL + Self.CUSH, dy: Self.RAIL + Self.CUSH)

        let off: CGFloat = 7
        let cornerR = BR * 2.15
        let sideR = BR * 1.9
        pockets = [
            (c: CGPoint(x: play.minX - off, y: play.minY - off), r: cornerR),
            (c: CGPoint(x: play.midX, y: play.minY - off - 2), r: sideR),
            (c: CGPoint(x: play.maxX + off, y: play.minY - off), r: cornerR),
            (c: CGPoint(x: play.minX - off, y: play.maxY + off), r: cornerR),
            (c: CGPoint(x: play.midX, y: play.maxY + off + 2), r: sideR),
            (c: CGPoint(x: play.maxX + off, y: play.maxY + off), r: cornerR),
        ]
        cornerMouth = cornerR + BR * 0.8
        sideMouth = sideR + BR * 0.7
    }

    private func inMouthX(_ x: CGFloat) -> Bool {
        abs(x - (play.minX - 7)) < cornerMouth
            || abs(x - (play.maxX + 7)) < cornerMouth
            || abs(x - play.midX) < sideMouth
    }

    private func inMouthY(_ y: CGFloat) -> Bool {
        abs(y - (play.minY - 7)) < cornerMouth || abs(y - (play.maxY + 7)) < cornerMouth
    }

    private func rack() {
        balls = [Ball(num: 0, p: headSpot, v: .zero)]
        let rows: [[Int]] = [[1], [9, 2], [10, 8, 3], [11, 7, 14, 4], [5, 13, 15, 6, 12]]
        let dx = BR * 2 * 0.868 + 0.6
        let dy = BR * 2 + 0.6
        for (i, row) in rows.enumerated() {
            for (j, num) in row.enumerated() {
                let p = CGPoint(x: footSpot.x + CGFloat(i) * dx,
                                y: footSpot.y + (CGFloat(j) - CGFloat(i) / 2) * dy)
                balls.append(Ball(num: num, p: p, v: .zero))
            }
        }
    }

    private func freeSpot(near: CGPoint) -> CGPoint {
        guard balls.contains(where: { $0.on && $0.p.dist(to: near) < BR * 2.05 }) else { return near }
        var r = BR
        while r < play.width {
            for k in 0..<24 {
                let a = CGFloat(k) / 24 * 2 * .pi
                let p = near + CGPoint(x: cos(a) * r, y: sin(a) * r)
                if play.insetBy(dx: BR, dy: BR).contains(p),
                   !balls.contains(where: { $0.on && $0.p.dist(to: p) < BR * 2.05 }) {
                    return p
                }
            }
            r += BR
        }
        return near
    }

    private func respotCue() {
        balls[0].on = true
        balls[0].v = .zero
        balls[0].p = freeSpot(near: headSpot)
    }

    private func respotEight() {
        guard let i = balls.firstIndex(where: { $0.num == 8 }) else { return }
        balls[i].on = true
        balls[i].v = .zero
        balls[i].p = freeSpot(near: footSpot)
    }

    private func remaining(_ g: Group) -> Int {
        balls.filter { $0.on && $0.num != 0 && $0.num != 8 && group(of: $0.num) == g }.count
    }

    private func group(of num: Int) -> Group { num < 8 ? .solids : .stripes }
    private func pname(_ i: Int) -> String { "P\(i + 1)" }

    // MARK: Loop

    @objc private func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        var dt = now - lastT
        lastT = now
        dt = min(dt, 0.05)

        if phase == .roll {
            let sub = 10
            let h = CGFloat(dt / Double(sub))
            for _ in 0..<sub where phase == .roll { integrate(h) }
            if balls.allSatisfy({ !$0.on || $0.v.len < Self.STOP }) {
                for i in balls.indices where balls[i].on { balls[i].v = .zero }
                if sinkAnims.isEmpty { resolveShot() }
            }
        }

        var idx = sinkAnims.count - 1
        while idx >= 0 {
            sinkAnims[idx].t += CGFloat(dt / 0.32)
            if sinkAnims[idx].t >= 1 { sinkAnims.remove(at: idx) }
            idx -= 1
        }

        if now >= bannerUntil { bannerText = ""; bannerSub = "" }

        onMoveHandle?(cuePoint)
        onInteractiveChange?(phase == .aim && sinkAnims.isEmpty)

        needsDisplay = true
        l.isPaused = phase == .aim && drag == nil && sinkAnims.isEmpty && now >= bannerUntil
    }

    private func integrate(_ h: CGFloat) {
        for i in balls.indices where balls[i].on {
            balls[i].p = balls[i].p + balls[i].v * h
            balls[i].v = balls[i].v * CGFloat(exp(-Double(Self.FRICTION * h)))
        }

        for i in balls.indices where balls[i].on {
            var b = balls[i]
            if b.p.x - BR < play.minX, !inMouthY(b.p.y) {
                b.p.x = play.minX + BR
                if b.v.x < 0 { if abs(b.v.x) > 70 { SFX.shared.cushion() }; b.v.x = -b.v.x * Self.REST_C }
            }
            if b.p.x + BR > play.maxX, !inMouthY(b.p.y) {
                b.p.x = play.maxX - BR
                if b.v.x > 0 { if abs(b.v.x) > 70 { SFX.shared.cushion() }; b.v.x = -b.v.x * Self.REST_C }
            }
            if b.p.y - BR < play.minY, !inMouthX(b.p.x) {
                b.p.y = play.minY + BR
                if b.v.y < 0 { if abs(b.v.y) > 70 { SFX.shared.cushion() }; b.v.y = -b.v.y * Self.REST_C }
            }
            if b.p.y + BR > play.maxY, !inMouthX(b.p.x) {
                b.p.y = play.maxY - BR
                if b.v.y > 0 { if abs(b.v.y) > 70 { SFX.shared.cushion() }; b.v.y = -b.v.y * Self.REST_C }
            }
            // pocket jaws: deadened bounce behind the rails so nothing escapes
            if b.p.x < table.minX + BR { b.p.x = table.minX + BR; b.v.x = abs(b.v.x) * 0.4 }
            if b.p.x > table.maxX - BR { b.p.x = table.maxX - BR; b.v.x = -abs(b.v.x) * 0.4 }
            if b.p.y < table.minY + BR { b.p.y = table.minY + BR; b.v.y = abs(b.v.y) * 0.4 }
            if b.p.y > table.maxY - BR { b.p.y = table.maxY - BR; b.v.y = -abs(b.v.y) * 0.4 }
            for pk in pockets where b.p.dist(to: pk.c) < pk.r + 4 {
                pot(i, into: pk.c)
                break
            }
        }

        let n = balls.count
        for i in 0..<n where balls[i].on {
            for j in (i + 1)..<n where balls[j].on {
                let a = balls[i]
                let c = balls[j]
                let d = c.p - a.p
                let dist = d.len
                if dist < BR * 2, dist > 0.0001 {
                    let nrm = CGPoint(x: d.x / dist, y: d.y / dist)
                    let overlap = BR * 2 - dist
                    var a2 = a
                    var c2 = c
                    a2.p = a2.p - nrm * (overlap / 2 + 0.02)
                    c2.p = c2.p + nrm * (overlap / 2 + 0.02)
                    let rvx = a2.v.x - c2.v.x
                    let rvy = a2.v.y - c2.v.y
                    let vn = rvx * nrm.x + rvy * nrm.y
                    if vn > 0 {
                        let jimp = (1 + Self.REST_B) * vn / 2
                        a2.v = a2.v - nrm * jimp
                        c2.v = c2.v + nrm * jimp
                        if vn > 60 { SFX.shared.clack(min(1, Double(vn / 2200))) }
                        if a2.num == 0 || c2.num == 0 { contacted = true }
                    }
                    balls[i] = a2
                    balls[j] = c2
                }
            }
        }
    }

    private func pot(_ i: Int, into c: CGPoint) {
        let b = balls[i]
        sinkAnims.append((num: b.num, from: b.p, to: c, t: 0))
        balls[i].on = false
        balls[i].v = .zero
        if b.num == 0 { cueScratch = true } else { potted.append(b.num) }
        SFX.shared.pocket()
    }

    // MARK: Rules

    private func resolveShot() {
        let shooter = turn
        let isBreak = shotCount == 1

        // 8 on the break: re-spot and carry on
        if isBreak, let ei = potted.firstIndex(of: 8) {
            potted.remove(at: ei)
            respotEight()
        }

        if potted.contains(8) {
            let legal = groups[shooter] != nil && groupLeftAtShotStart == 0 && !cueScratch && contacted
            if legal {
                endGame(winner: shooter, why: "\(pname(shooter)) WINS!")
            } else {
                endGame(winner: 1 - shooter, why: "\(pname(shooter)) sank the 8 early — \(pname(1 - shooter)) WINS!")
            }
            return
        }

        // first legal pot closes the open table
        if groups[shooter] == nil, let first = potted.first, !cueScratch {
            let g = group(of: first)
            groups[shooter] = g
            groups[1 - shooter] = g == .solids ? .stripes : .solids
            banner("\(pname(shooter)) → \(g == .solids ? "SOLIDS" : "STRIPES")", "open table is closed")
        }

        let foul = cueScratch || !contacted
        let own = groups[shooter].map { g in potted.contains { group(of: $0) == g } } ?? false

        if cueScratch {
            respotCue()
            banner("SCRATCH!", "\(pname(shooter)) fouls — \(pname(1 - shooter)) shoots")
        } else if !contacted {
            banner("FOUL!", "no contact — \(pname(1 - shooter)) shoots")
        }

        if foul {
            turn = 1 - shooter
        } else if own {
            // shooter keeps the table
        } else {
            turn = 1 - shooter
        }

        phase = .aim
        needsDisplay = true
    }

    private func endGame(winner: Int, why: String) {
        self.winner = winner
        wins[winner] += 1
        UserDefaults.standard.set(wins[0], forKey: "pool8.wins0")
        UserDefaults.standard.set(wins[1], forKey: "pool8.wins1")
        phase = .over
        banner(why, "\(pname(winner)) takes the rack · ⌃⌥N for a new game", 4.0)
        SFX.shared.fanfare([523.25, 659.25, 783.99, 1046.5], step: 0.12)
        needsDisplay = true
    }

    func newGame() {
        phase = .aim
        turn = 0
        groups = [nil, nil]
        shotCount = 0
        potted = []
        cueScratch = false
        contacted = false
        groupLeftAtShotStart = -1
        winner = nil
        sinkAnims = []
        drag = nil
        bannerText = ""
        bannerSub = ""
        bannerUntil = 0
        buildGeometry()
        rack()
        needsDisplay = true
    }

    func resetScore() {
        wins = [0, 0]
        UserDefaults.standard.set(0, forKey: "pool8.wins0")
        UserDefaults.standard.set(0, forKey: "pool8.wins1")
        needsDisplay = true
    }

    func rebuildForScreens() {
        let old = play
        buildGeometry()
        sinkAnims = []
        if old.width > 0, shotCount > 0 {
            for i in balls.indices {
                let nx = play.minX + (balls[i].p.x - old.minX) / old.width * play.width
                let ny = play.minY + (balls[i].p.y - old.minY) / old.height * play.height
                balls[i].p = CGPoint(x: nx, y: ny)
            }
        } else {
            rack()
        }
        needsDisplay = true
    }

    private func banner(_ text: String, _ sub: String, _ dur: Double = 2.0) {
        bannerText = text
        bannerSub = sub
        bannerStart = CACurrentMediaTime()
        bannerUntil = bannerStart + dur
    }

    // MARK: Input — driven by the HandleView (small window that follows the cue ball)

    var onMoveHandle: ((NSPoint) -> Void)?
    var onInteractiveChange: ((Bool) -> Void)?

    func installGlobalMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]

        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            guard let self else { return e }
            DispatchQueue.main.async {
                let near = self.screenToLocal(NSEvent.mouseLocation).dist(to: self.cuePoint) < Self.GRAB
                switch e.type {
                case .leftMouseDown, .rightMouseDown:
                    if self.phase == .aim, near, !self.seqActive { self.handleGrab() }
                case .leftMouseDragged, .rightMouseDragged:
                    if self.seqActive { self.handleDrag(NSEvent.mouseLocation) }
                case .leftMouseUp, .rightMouseUp:
                    if self.seqActive { self.seqActive = false; self.handleRelease(NSEvent.mouseLocation) }
                default: break
                }
            }
            return e
        }

        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            DispatchQueue.main.async {
                guard let self else { return }
                let near = self.screenToLocal(NSEvent.mouseLocation).dist(to: self.cuePoint) < Self.GRAB
                switch e.type {
                case .leftMouseDown, .rightMouseDown:
                    if self.phase == .aim, near, !self.seqActive { self.handleGrab() }
                case .leftMouseDragged, .rightMouseDragged:
                    if self.phase == .aim, near, !self.seqActive {
                        self.handleGrab()
                        self.handleDrag(NSEvent.mouseLocation)
                    } else if self.seqActive {
                        self.handleDrag(NSEvent.mouseLocation)
                    }
                case .leftMouseUp, .rightMouseUp:
                    if self.seqActive { self.seqActive = false; self.handleRelease(NSEvent.mouseLocation) }
                default: break
                }
            }
        }
        monitors = [local, global].compactMap { $0 }
    }

    func screenToLocal(_ sp: NSPoint) -> NSPoint {
        guard let w = window else { return sp }
        return w.convertFromScreen(NSRect(origin: sp, size: .zero)).origin
    }

    func handleGrab() {
        lastT = CACurrentMediaTime()
        link?.isPaused = false
        seqActive = true
        NSCursor.closedHand.push()
    }

    func handleDrag(_ screenPoint: NSPoint) {
        guard phase == .aim, seqActive else { return }
        drag = screenToLocal(screenPoint)
        needsDisplay = true
    }

    func handleRelease(_ screenPoint: NSPoint) {
        NSCursor.pop()
        guard phase == .aim, seqActive else { return }
        seqActive = false
        let d = screenToLocal(screenPoint)
        drag = nil
        let pull = cuePoint - d
        let dist = min(pull.len, Self.MAXDRAG)
        guard dist > 10 else { needsDisplay = true; return }
        balls[0].v = pull.norm * (Self.MAXSPEED * (dist / Self.MAXDRAG))
        potted = []
        cueScratch = false
        contacted = false
        groupLeftAtShotStart = groups[turn].map { remaining($0) } ?? -1
        shotCount += 1
        phase = .roll
        SFX.shared.strike(Double(dist / Self.MAXDRAG))
        needsDisplay = true
    }

    // MARK: Drawing — transparent, only the pool table

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = CACurrentMediaTime()
        ctx.clear(bounds)

        drawTable(ctx)
        for a in sinkAnims {
            let p = a.from + (a.to - a.from) * min(a.t, 1)
            drawBall(ctx, a.num, p, max(0.05, 1 - a.t * 1.1))
        }
        for b in balls where b.on {
            drawBall(ctx, b.num, b.p, 1)
        }
        drawAim(ctx)
        drawChip(ctx)
        drawHint(ctx, t)
        drawBanner(ctx)
    }

    private func drawTable(_ ctx: CGContext) {
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(CGColor.rgb(0.34, 0.21, 0.11, 0.98))
        ctx.addPath(CGPath(roundedRect: table, cornerWidth: 22, cornerHeight: 22, transform: nil))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        let felt = play.insetBy(dx: -Self.CUSH, dy: -Self.CUSH)
        ctx.setFillColor(CGColor.rgb(0.04, 0.35, 0.2, 0.99))
        ctx.addPath(CGPath(roundedRect: felt, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()

        // cushion ring
        ctx.setStrokeColor(CGColor.rgb(0.02, 0.26, 0.14, 1))
        ctx.setLineWidth(Self.CUSH)
        ctx.stroke(play.insetBy(dx: -Self.CUSH / 2, dy: -Self.CUSH / 2))

        // head string + spots
        ctx.setStrokeColor(CGColor.rgb(1, 1, 1, 0.1))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: headSpot.x, y: play.minY))
        ctx.addLine(to: CGPoint(x: headSpot.x, y: play.maxY))
        ctx.strokePath()
        ctx.setFillColor(CGColor.rgb(1, 1, 1, 0.18))
        for sp in [headSpot, footSpot] {
            ctx.fillEllipse(in: CGRect(x: sp.x - 2.5, y: sp.y - 2.5, width: 5, height: 5))
        }

        // pockets
        for pk in pockets {
            ctx.setFillColor(CGColor.rgb(0, 0, 0, 0.92))
            ctx.fillEllipse(in: CGRect(x: pk.c.x - pk.r, y: pk.c.y - pk.r, width: pk.r * 2, height: pk.r * 2))
            ctx.setStrokeColor(CGColor.rgb(1, 1, 1, 0.14))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: CGRect(x: pk.c.x - pk.r, y: pk.c.y - pk.r, width: pk.r * 2, height: pk.r * 2))
        }

        // rail diamonds
        ctx.setFillColor(CGColor.rgb(1, 1, 1, 0.5))
        for i in 1...7 where i != 4 {
            let x = play.minX + play.width * CGFloat(i) / 8
            diamond(ctx, CGPoint(x: x, y: table.minY + Self.RAIL / 2), 3)
            diamond(ctx, CGPoint(x: x, y: table.maxY - Self.RAIL / 2), 3)
        }
        for j in 1...3 {
            let y = play.minY + play.height * CGFloat(j) / 4
            diamond(ctx, CGPoint(x: table.minX + Self.RAIL / 2, y: y), 3)
            diamond(ctx, CGPoint(x: table.maxX - Self.RAIL / 2, y: y), 3)
        }
    }

    private func diamond(_ ctx: CGContext, _ c: CGPoint, _ s: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + s))
        p.addLine(to: CGPoint(x: c.x + s, y: c.y))
        p.addLine(to: CGPoint(x: c.x, y: c.y - s))
        p.addLine(to: CGPoint(x: c.x - s, y: c.y))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.fillPath()
    }

    private static func color(of num: Int) -> CGColor {
        switch num {
        case 1, 9: return CGColor.rgb(0.93, 0.72, 0.1)
        case 2, 10: return CGColor.rgb(0.1, 0.35, 0.8)
        case 3, 11: return CGColor.rgb(0.85, 0.15, 0.15)
        case 4, 12: return CGColor.rgb(0.45, 0.2, 0.7)
        case 5, 13: return CGColor.rgb(0.95, 0.5, 0.1)
        case 6, 14: return CGColor.rgb(0.1, 0.62, 0.3)
        case 7, 15: return CGColor.rgb(0.55, 0.28, 0.2)
        case 8: return CGColor.rgb(0.09, 0.09, 0.11)
        default: return CGColor.rgb(0.96, 0.96, 0.93)
        }
    }

    private func drawBall(_ ctx: CGContext, _ num: Int, _ p: CGPoint, _ scale: CGFloat) {
        let r = BR * scale
        guard r > 0.5 else { return }
        let base = Self.color(of: num)
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        let circle = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if num >= 9 {
            ctx.setFillColor(CGColor.rgb(0.95, 0.95, 0.92))
            ctx.fillEllipse(in: circle)
            ctx.saveGState()
            ctx.addPath(CGPath(ellipseIn: circle, transform: nil))
            ctx.clip()
            ctx.setFillColor(base)
            ctx.fill(CGRect(x: p.x - r, y: p.y - r * 0.55, width: r * 2, height: r * 1.1))
            ctx.restoreGState()
        } else {
            ctx.setFillColor(base)
            ctx.fillEllipse(in: circle)
        }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        if num > 0 {
            let nr = r * 0.44
            ctx.setFillColor(CGColor.rgb(0.97, 0.96, 0.93))
            ctx.fillEllipse(in: CGRect(x: p.x - nr, y: p.y - nr, width: nr * 2, height: nr * 2))
            let s = "\(num)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: max(6, r * 0.62), weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let sz = s.size(withAttributes: attrs)
            s.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2), withAttributes: attrs)
        }

        ctx.setFillColor(CGColor.rgb(1, 1, 1, 0.75))
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.55, y: p.y + r * 0.12, width: r * 0.42, height: r * 0.42))
    }

    private func rayCircle(_ o: CGPoint, _ d: CGPoint, _ c: CGPoint, _ radius: CGFloat) -> CGFloat? {
        let ox = o.x - c.x
        let oy = o.y - c.y
        let b = ox * d.x + oy * d.y
        let cc = ox * ox + oy * oy - radius * radius
        let disc = b * b - cc
        guard disc > 0 else { return nil }
        let t = -b - sqrt(disc)
        return t > 1 ? t : nil
    }

    private func rayToCushion(_ o: CGPoint, _ d: CGPoint) -> CGFloat {
        var best: CGFloat = 4000
        let lo = play.insetBy(dx: BR, dy: BR)
        if d.x < 0 { let t = (lo.minX - o.x) / d.x; if t > 0 { best = min(best, t) } }
        if d.x > 0 { let t = (lo.maxX - o.x) / d.x; if t > 0 { best = min(best, t) } }
        if d.y < 0 { let t = (lo.minY - o.y) / d.y; if t > 0 { best = min(best, t) } }
        if d.y > 0 { let t = (lo.maxY - o.y) / d.y; if t > 0 { best = min(best, t) } }
        return best
    }

    private func drawAim(_ ctx: CGContext) {
        guard phase == .aim, let d = drag else { return }
        let pull = cuePoint - d
        let dist = min(pull.len, Self.MAXDRAG)
        guard dist > 4 else { return }
        let power = dist / Self.MAXDRAG
        let col = NSColor(hue: CGFloat(0.33 - 0.33 * power), saturation: 0.85, brightness: 1, alpha: 1)
        let dir = pull.norm

        var hitT = rayToCushion(cuePoint, dir)
        var hitBallIdx: Int?
        for (i, b) in balls.enumerated() where b.on && b.num != 0 {
            if let t = rayCircle(cuePoint, dir, b.p, BR * 2), t < hitT {
                hitT = t
                hitBallIdx = i
            }
        }
        let ghost = cuePoint + dir * hitT

        ctx.setShadow(offset: .zero, blur: 6, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setStrokeColor(col.cgColor)
        ctx.setLineWidth(2.5)
        ctx.setLineCap(.round)
        ctx.setLineDash(phase: 0, lengths: [7, 7])
        ctx.move(to: cuePoint + dir * (BR + 3))
        ctx.addLine(to: ghost)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(col.cgColor.copy(alpha: 0.7)!)
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: ghost.x - BR, y: ghost.y - BR, width: BR * 2, height: BR * 2))

        if let i = hitBallIdx {
            let n = (balls[i].p - ghost).norm
            ctx.setStrokeColor(col.cgColor.copy(alpha: 0.9)!)
            ctx.setLineWidth(3)
            ctx.move(to: balls[i].p)
            ctx.addLine(to: balls[i].p + n * (BR * 3.2))
            ctx.strokePath()
            let dot = dir.x * n.x + dir.y * n.y
            let tang = dir - n * dot
            if tang.len > 0.15 {
                ctx.setStrokeColor(col.cgColor.copy(alpha: 0.45)!)
                ctx.setLineWidth(2)
                ctx.move(to: ghost)
                ctx.addLine(to: ghost + tang.norm * 60)
                ctx.strokePath()
            }
        }

        let rr = BR + 8 + power * 7
        ctx.setStrokeColor(col.cgColor.copy(alpha: 0.6)!)
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: CGRect(x: cuePoint.x - rr, y: cuePoint.y - rr, width: rr * 2, height: rr * 2))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }

    private func chipText() -> String {
        if phase == .over, let w = winner {
            return "\(pname(w)) wins this rack · \(wins[0])–\(wins[1]) · ⌃⌥N for a new game"
        }
        func desc(_ i: Int) -> String {
            let name = pname(i)
            guard let g = groups[i] else { return "\(name) —" }
            let left = remaining(g)
            let sym = g == .solids ? "●" : "◎"
            return left == 0 ? "\(name) \(sym) 8-ball!" : "\(name) \(sym) \(left) left"
        }
        return "\(desc(0))   ·   \(desc(1))   ·   \(pname(turn)) to shoot   ·   \(wins[0])–\(wins[1])"
    }

    private func drawChip(_ ctx: CGContext) {
        let text = chipText()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            .shadow: shadow(),
        ]
        let sz = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: table.midX - sz.width / 2, y: table.maxY + 14), withAttributes: attrs)
    }

    private func drawHint(_ ctx: CGContext, _ t: Double) {
        guard shotCount == 0, phase == .aim, drag == nil else { return }
        let hint = "grab the cue ball · pull back · release to break" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.5 + 0.2 * CGFloat(sin(t * 2))),
            .shadow: shadow(),
        ]
        let w = hint.size(withAttributes: attrs).width
        hint.draw(at: CGPoint(x: cuePoint.x - w / 2, y: cuePoint.y - BR - 26), withAttributes: attrs)
    }

    private func drawBanner(_ ctx: CGContext) {
        let now = CACurrentMediaTime()
        guard now < bannerUntil else { return }
        let g = bounds
        let age = now - bannerStart
        let a = CGFloat(min(1, age * 6))
        let big: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .heavy),
            .foregroundColor: NSColor.white.withAlphaComponent(a),
            .shadow: shadow(),
        ]
        let sm: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(a * 0.85),
            .shadow: shadow(),
        ]
        let bs = (bannerText as NSString).size(withAttributes: big)
        (bannerText as NSString).draw(at: CGPoint(x: (g.width - bs.width) / 2, y: g.midY + 6), withAttributes: big)
        let ss = (bannerSub as NSString).size(withAttributes: sm)
        (bannerSub as NSString).draw(at: CGPoint(x: (g.width - ss.width) / 2, y: g.midY - 22), withAttributes: sm)
    }

    private func shadow() -> NSShadow {
        let s = NSShadow()
        s.shadowBlurRadius = 4
        s.shadowOffset = CGSize(width: 0, height: -2)
        s.shadowColor = NSColor.black.withAlphaComponent(0.6)
        return s
    }
}

// MARK: - Panel + App

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Tiny always-on-top window that follows the cue ball and is the only interactive spot.
final class HandleView: NSView {
    var onDown: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onUp: ((NSPoint) -> Void)?
    var interactive = true
    private var seqActive = false

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for n: NSEvent?) -> Bool { true }

    override func hitTest(_ p: NSPoint) -> NSView? {
        interactive ? self : nil
    }

    required init?(coder: NSCoder) { fatalError() }
    override init(frame: NSRect) { super.init(frame: frame) }

    override func mouseDown(with e: NSEvent) {
        window?.makeKey()
        guard !seqActive else { return }
        seqActive = true
        onDown?()
    }
    override func mouseDragged(with e: NSEvent) { onDrag?(NSEvent.mouseLocation) }
    override func mouseUp(with e: NSEvent) {
        guard seqActive else { return }
        seqActive = false
        onUp?(NSEvent.mouseLocation)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: Panel!
    private var game: GameView!
    private var handlePanel: Panel!
    private var handleView: HandleView!
    private var statusItem: NSStatusItem!
    private static let HANDLE: CGFloat = 170

    private var courseFrame: NSRect {
        NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let f = courseFrame

        panel = Panel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true // overlay never eats clicks

        game = GameView(frame: NSRect(x: 0, y: 0, width: f.width, height: f.height))
        game.wantsLayer = true
        game.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = game
        panel.orderFrontRegardless()
        game.installGlobalMonitors()

        let h = Self.HANDLE
        handlePanel = Panel(contentRect: NSRect(x: 0, y: 0, width: h, height: h),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handlePanel.level = .statusBar + 1
        handlePanel.isOpaque = false
        handlePanel.backgroundColor = .clear
        handlePanel.hasShadow = false
        handlePanel.hidesOnDeactivate = false
        handlePanel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        handlePanel.ignoresMouseEvents = false

        handleView = HandleView(frame: NSRect(x: 0, y: 0, width: h, height: h))
        handleView.onDown = { [weak self] in self?.game.handleGrab() }
        handleView.onDrag = { [weak self] pt in self?.game.handleDrag(pt) }
        handleView.onUp = { [weak self] pt in self?.game.handleRelease(pt) }
        handlePanel.contentView = handleView
        handlePanel.orderFrontRegardless()
        moveHandle()

        game.onMoveHandle = { [weak self] _ in self?.moveHandle() }
        game.onInteractiveChange = { [weak self] on in self?.handleView.interactive = on }

        HotKey.register()
        HotKey.onToggle = { [weak self] in self?.toggle() }
        HotKey.onNewGame = { [weak self] in self?.game.newGame() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎱"
        let menu = NSMenu()
        let toggleItem = NSMenuItem(title: "Show / Hide (⌃⌥P)", action: #selector(toggleMenu), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let newGameItem = NSMenuItem(title: "New Game (⌃⌥N)", action: #selector(newGameMenu), keyEquivalent: "")
        newGameItem.target = self
        menu.addItem(newGameItem)
        let snd = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        snd.target = self
        snd.state = (UserDefaults.standard.object(forKey: "pool8.sound") as? Bool ?? true) ? .on : .off
        menu.addItem(snd)
        let resetScore = NSMenuItem(title: "Reset Score", action: #selector(resetScoreMenu), keyEquivalent: "")
        resetScore.target = self
        menu.addItem(resetScore)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit 8BallsPool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.position() }
    }

    private func position() {
        let f = courseFrame
        panel.setFrame(f, display: true)
        game.frame = NSRect(x: 0, y: 0, width: f.width, height: f.height)
        game.rebuildForScreens()
        moveHandle()
    }

    private func moveHandle() {
        guard let w = game.window else { return }
        let local = game.cuePoint
        let screenPt = w.convertToScreen(NSRect(origin: local, size: .zero)).origin
        let h = Self.HANDLE
        handlePanel.setFrameOrigin(NSPoint(x: screenPt.x - h / 2, y: screenPt.y - h / 2))
    }

    @objc private func toggleMenu() { toggle() }
    @objc private func newGameMenu() { game.newGame() }
    @objc private func resetScoreMenu() { game.resetScore() }
    @objc private func toggleSound() {
        let v = !(UserDefaults.standard.object(forKey: "pool8.sound") as? Bool ?? true)
        UserDefaults.standard.set(v, forKey: "pool8.sound")
        statusItem.menu?.items.first(where: { $0.title == "Sound" })?.state = v ? .on : .off
    }

    private func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { position(); panel.orderFrontRegardless() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
