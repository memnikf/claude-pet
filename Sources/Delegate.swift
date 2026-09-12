import AppKit

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { false }   // не крадём фокус у терминала
    override var canBecomeMain: Bool { false }
}

// Подпись под питомцем: состояние и текущий проект.
final class PlateView: NSView {
    var st = PetState()

    // Шрифты создаём один раз. Через monospacedSystemFont на каждом кадре
    // CoreText иногда получал пустой шрифт и всё падало в SIGABRT
    // (ApplyFont → initWithObjects:forKeys: с nil).
    private static let big = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let mid = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular)
    private static let small = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)

    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        guard !st.say.isEmpty, bounds.width > 1 else { return }

        var line2 = st.dir
        if st.live > 1 { line2 += " · \(st.live) сессии" }
        if let (_, what) = st.toolMark { line2 = what + " · " + st.dir }
        if let e = st.elapsed { line2 += " · " + e }
        if !st.fail.isEmpty { line2 = "упало: " + st.fail + " · " + st.dir }

        // третья строка: контекст и деньги — то, за чем следишь по ходу работы
        var line3 = ""
        if st.pct > 0 { line3 = "\(st.pct)% контекста" }
        // Расход прячется ключом petHideCost (меню «Показывать расход»): в записи
        // экрана и на чужом мониторе сумма по сессии — лишнее.
        if st.cost > 0, st.cost.isFinite, !UserDefaults.standard.bool(forKey: "petHideCost") {
            line3 += (line3.isEmpty ? "" : "  ") + String(format: "$%.2f", st.cost)
        }

        let f1 = PlateView.big, f2 = PlateView.mid, f3 = PlateView.small
        let dim = NSColor(white: 0.68, alpha: 0.75)
        // Строки усекаем: плашка шире своей ячейки залезала на плашку соседней
        // сессии в ряду (ячейка 150 px, а подпись «команда · проект · 40 мин» шире).
        let clip = NSMutableParagraphStyle()
        clip.lineBreakMode = .byTruncatingTail

        let red = NSColor(srgbRed: 0.95, green: 0.55, blue: 0.66, alpha: 1)
        let s1 = NSAttributedString(string: st.say, attributes: [
            .font: f1, .foregroundColor: st.fail.isEmpty ? st.body : red,
            .paragraphStyle: clip])
        let s2 = NSAttributedString(string: line2, attributes: [
            .font: f2, .foregroundColor: dim, .paragraphStyle: clip])
        let s3 = NSAttributedString(string: line3, attributes: [
            .font: f3, .foregroundColor: NSColor(white: 0.60, alpha: 0.7),
            .paragraphStyle: clip])

        let maxW = bounds.width - 6
        let w = min(max(s1.size().width, max(s2.size().width, s3.size().width)) + 24, maxW)
        var h: CGFloat = 24
        if !line2.isEmpty { h += 14 }
        if !line3.isEmpty { h += 13 }
        let box = CGRect(x: (bounds.width - w) / 2, y: 0, width: w, height: h)

        // Фон почти глухой: на 0.72 сквозь плашку читался текст окон под ней и
        // подписи сливались. Тень отделяет её от светлого фона, где рамки не видно.
        let bg = NSBezierPath(roundedRect: box, xRadius: 13, yRadius: 13)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor(white: 0, alpha: 0.35)
        sh.shadowBlurRadius = 6
        sh.shadowOffset = NSSize(width: 0, height: -1)
        sh.set()
        NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 0.97).setFill()
        bg.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.12).setStroke()
        bg.lineWidth = 1
        bg.stroke()

        // draw(in:) — не draw(at:): усечение по краю работает только в прямоугольнике.
        let inner = box.insetBy(dx: 8, dy: 0)
        func line(_ a: NSAttributedString, _ y: CGFloat, _ h: CGFloat) {
            let wd = min(a.size().width, inner.width)
            a.draw(in: CGRect(x: inner.midX - wd / 2, y: y, width: wd, height: h))
        }
        var y = box.minY + 4
        line(s1, y, 15); y += 16
        if !line2.isEmpty { line(s2, y, 13); y += 13 }
        if !line3.isEmpty { line(s3, y, 12) }

        // полоска лимита пятичасового окна — тоньше и выше контекстной
        if st.lim5 > 0 {
            let inset: CGFloat = 12
            let full = box.width - inset * 2
            let y = box.maxY - 6.5
            NSColor(white: 1, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: CGRect(x: box.minX + inset, y: y, width: full, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
            let part = full * CGFloat(min(st.lim5, 100)) / 100
            let c: NSColor = st.lim5 < 60 ? NSColor(white: 0.75, alpha: 0.45)
                : st.lim5 < 85 ? NSColor(srgbRed: 0.98, green: 0.71, blue: 0.53, alpha: 0.85)
                               : NSColor(srgbRed: 0.95, green: 0.55, blue: 0.66, alpha: 0.95)
            c.setFill()
            NSBezierPath(roundedRect: CGRect(x: box.minX + inset, y: y, width: part, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
        }

        // полоска контекста по низу плашки: краснеет к концу
        if st.pct > 0 {
            let inset: CGFloat = 12
            let full = box.width - inset * 2
            let bar = CGRect(x: box.minX + inset, y: box.maxY - 3.5, width: full, height: 2)
            NSColor(white: 1, alpha: 0.10).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()

            let part = full * CGFloat(min(st.pct, 100)) / 100
            let c: NSColor = st.pct < 50 ? NSColor(srgbRed: 0.65, green: 0.89, blue: 0.63, alpha: 0.9)
                : st.pct < 75 ? NSColor(srgbRed: 0.98, green: 0.89, blue: 0.69, alpha: 0.9)
                : st.pct < 90 ? NSColor(srgbRed: 0.98, green: 0.71, blue: 0.53, alpha: 0.9)
                              : NSColor(srgbRed: 0.95, green: 0.55, blue: 0.66, alpha: 0.95)
            c.setFill()
            NSBezierPath(roundedRect: CGRect(x: bar.minX, y: bar.minY, width: part, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
    }
}

final class PetDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var win: PetWindow!
    private var pet: PetView!
    private var plate: PlateView!
    private var timer: Timer?
    private var dragOffset: CGPoint?

    private let W: CGFloat = 186
    private let PET: CGFloat = 96
    private let KEY = "petOrigin"

    func applicationDidFinishLaunching(_ n: Notification) {
        // Один экземпляр: launchd и запуск из Finder легко дают две копии,
        // и на столе появляются два питомца. Держим лок на файле.
        guard claimLock() else { NSApp.terminate(nil); return }

        let H = PET + PetView.pad + 62
        win = PetWindow(contentRect: CGRect(x: 0, y: 0, width: W, height: H),
                        styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        // .floating перебивается полноэкранными окнами и Ghostty;
        // statusBar держит питомца выше, но ниже системного меню-бара
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) - 1)
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.ignoresMouseEvents = false
        win.isMovableByWindowBackground = false      // тянем сами, точнее

        let root = DragRoot(frame: CGRect(x: 0, y: 0, width: W, height: H))
        root.onDrag = { [weak self] p in self?.moveWindow(by: p) }
        root.onDrop = { [weak self] in self?.savePosition() }
        root.columnWidth = W
        root.onClick = { [weak self] i in self?.openSession(at: i) }
        root.onFiles = { [weak self] paths in self?.tookFiles(paths) }
        root.registerForDraggedTypes([.fileURL])

        pet = PetView(frame: CGRect(x: (W - PET) / 2, y: 0, width: PET, height: PET + PetView.pad))
        plate = PlateView(frame: CGRect(x: 0, y: PET + PetView.pad + 2, width: W, height: 58))
        root.addSubview(pet)
        root.addSubview(plate)
        self.root = root
        win.contentView = root

        placeWindow()
        win.orderFrontRegardless()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.frame()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◆"
        item.menu = buildMenu()
        statusItem = item
    }

    // Меню собираем заново при каждом открытии: сессии и расход меняются.
    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.delegate = self
        return m
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()

        let head = NSMenuItem(title: "Продолжить сессию", action: nil, keyEquivalent: "")
        head.isEnabled = false
        m.addItem(head)

        let list = Pult.recent(limit: 8)
        if list.isEmpty {
            let none = NSMenuItem(title: "  сессий не найдено", action: nil, keyEquivalent: "")
            none.isEnabled = false
            m.addItem(none)
        }
        for (i, s) in list.enumerated() {
            let it = NSMenuItem(title: "  \(s.title)", action: #selector(pickSession(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.toolTip = s.dir
            let sub = NSAttributedString(string: "  \(s.title)\n  \(s.dir)", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ])
            it.attributedTitle = sub
            m.addItem(it)
        }
        sessions = list

        m.addItem(.separator())

        let newIn = NSMenuItem(title: "Новая сессия здесь…", action: #selector(newHere), keyEquivalent: "n")
        newIn.target = self
        m.addItem(newIn)

        m.addItem(.separator())

        let cost = NSMenuItem(title: usageText, action: nil, keyEquivalent: "")
        cost.isEnabled = false
        m.addItem(cost)
        Pult.usage { [weak self] t in
            DispatchQueue.main.async { self?.usageText = t }
        }

        let cur = Pult.currentEndpoint()
        let ep = NSMenu()
        for (name, url, note) in Pult.endpoints {
            let it = NSMenuItem(title: "\(name)  ·  \(note)", action: #selector(pickEndpoint(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = url
            it.state = (url == cur) ? .on : .off
            ep.addItem(it)
        }
        let epItem = NSMenuItem(title: "Эндпоинт", action: nil, keyEquivalent: "")
        epItem.submenu = ep
        m.addItem(epItem)

        let d = Day.load()
        if d.prompts > 0 {
            let rub = d.cost * 4.2
            var t = "Сегодня: \(d.prompts) запросов"
            if d.sessions > 1 { t += ", \(d.sessions) сессий" }
            if d.cost > 0 { t += String(format: ", $%.2f", d.cost) }
            if rub >= 1 { t += String(format: " (%.0f₽)", rub) }
            let it = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
            if d.lines > 0 || d.tools > 0 {
                let it2 = NSMenuItem(title: "  \(d.lines) строк, \(d.tools) действий", action: nil, keyEquivalent: "")
                it2.isEnabled = false
                m.addItem(it2)
            }
            if d.hoursStraight >= 2 {
                let it3 = NSMenuItem(title: String(format: "  без перерыва %.1f ч", d.hoursStraight),
                                     action: nil, keyEquivalent: "")
                it3.isEnabled = false
                m.addItem(it3)
            }
            m.addItem(.separator())
        }

        let shot = NSMenuItem(title: "Снимок области → путь в буфер",
                              action: #selector(makeShot), keyEquivalent: "s")
        shot.target = self
        m.addItem(shot)

        m.addItem(.separator())

        let col = NSMenuItem(title: PetState.orange ? "Сделать синим" : "Сделать оранжевым",
                             action: #selector(flipColor), keyEquivalent: "")
        col.target = self
        m.addItem(col)

        let hid = UserDefaults.standard.bool(forKey: "petHideCost")
        let costItem = NSMenuItem(title: hid ? "Показывать расход" : "Скрыть расход",
                                  action: #selector(flipCost), keyEquivalent: "")
        costItem.target = self
        m.addItem(costItem)

        m.addItem(.separator())
        let quit = NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(quit)
    }

    @objc private func pickSession(_ sender: NSMenuItem) {
        guard sender.tag < sessions.count else { return }
        Pult.resume(sessions[sender.tag])
    }

    @objc private func newHere() {
        Pult.newSession(in: NSHomeDirectory() + "/work")
    }

    // Клик по фигурке — продолжить именно её сессию.
    private func openSession(at index: Int) {
        let list = PetState.loadAll()
        guard index < list.count else { return }
        let dir = list[index].dir
        guard !dir.isEmpty else { return }
        // ищем среди последних сессий ту, что в этом каталоге
        if let s = Pult.recent(limit: 20).first(where: { $0.dir.hasSuffix("/" + dir) || $0.dir == dir }) {
            Pult.resume(s)
        } else {
            Pult.newSession(in: NSHomeDirectory() + "/work/" + dir)
        }
    }

    // Брошенные файлы: путь в буфер, чтобы вставить в сессию;
    // если это папка — предлагаем открыть в ней новую сессию.
    private func tookFiles(_ paths: [String]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: " "), forType: .string)

        var isDir: ObjCBool = false
        if paths.count == 1, FileManager.default.fileExists(atPath: paths[0], isDirectory: &isDir),
           isDir.boolValue {
            Pult.newSession(in: paths[0])
        }
    }

    @objc private func makeShot() {
        Pult.run(NSHomeDirectory() + "/.local/bin/shot", [])
    }

    // Расход по сессии на плашке: скрывается для записи экрана и показа другим.
    @objc private func flipCost() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "petHideCost"), forKey: "petHideCost")
        plate.needsDisplay = true
        for (_, pl) in extra { pl.needsDisplay = true }
    }

    @objc private func flipColor() {
        PetState.orange.toggle()
        let s = PetState.load()
        pet.st = s; plate.st = s
        pet.needsDisplay = true; plate.needsDisplay = true
    }

    @objc private func pickEndpoint(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        Pult.setEndpoint(url)
    }

    private var root: DragRoot?
    private var extra: [(PetView, PlateView)] = []
    private var lockFD: Int32 = -1

    // Ряд: на каждую дополнительную сессию — своя фигурка справа от первой.
    private func syncRow(_ list: [PetState]) {
        let want = max(0, min(list.count, 4) - 1)
        guard let root else { return }

        while extra.count < want {
            let i = extra.count + 1
            let x = CGFloat(i) * W
            let p = PetView(frame: CGRect(x: x + (W - PET) / 2, y: 0,
                                          width: PET, height: PET + PetView.pad))
            let pl = PlateView(frame: CGRect(x: x, y: PET + PetView.pad + 2, width: W, height: 58))
            root.addSubview(p); root.addSubview(pl)
            extra.append((p, pl))
        }
        while extra.count > want {
            let (p, pl) = extra.removeLast()
            p.removeFromSuperview(); pl.removeFromSuperview()
        }

        // окно по фактическому числу фигурок
        let cols = CGFloat(want + 1)
        var f = win.frame
        let newW = cols * W
        if abs(f.width - newW) > 1 {
            f.size.width = newW
            win.setFrame(f, display: false)
            root.frame = CGRect(x: 0, y: 0, width: newW, height: f.height)
        }

        for (i, (p, pl)) in extra.enumerated() {
            let s = list[i + 1]
            p.st = s; pl.st = s
            pl.needsDisplay = true
        }
    }

    private func claimLock() -> Bool {
        let path = NSHomeDirectory() + "/.claude/.pet.lock"
        lockFD = open(path, O_CREAT | O_RDWR, 0o644)
        guard lockFD >= 0 else { return true }   // не смогли — лучше запуститься
        return flock(lockFD, LOCK_EX | LOCK_NB) == 0
    }

    private var statusItem: NSStatusItem?
    private var sessions: [Sess] = []
    private var usageText = "расход: считаю…"
    private var lastRead = Date.distantPast
    private var ticks = 0

    private func frame() {
        ticks += 1
        // состояние читаем 4 раза в секунду, анимацию гоним 30
        if ticks % 8 == 0 {
            let list = PetState.loadAll()
            let s = list.first ?? PetState()
            pet.st = s
            plate.st = s
            plate.needsDisplay = true
            syncRow(list)
        }
        // «пора отдохнуть»: раз в час, если сидим больше двух часов подряд
        if ticks % (30 * 60) == 0 {
            let d = Day.load()
            if d.hoursStraight >= 2 { pet.stretch = true }
        }
        pet.tick(1.0 / 30)
        for (p, _) in extra { p.tick(1.0 / 30) }
    }

    private func moveWindow(by delta: CGPoint) {
        var o = win.frame.origin
        o.x += delta.x
        o.y += delta.y
        win.setFrameOrigin(clampToScreen(o))
    }

    // Не пускаем за края: наверху питомец уезжал под меню-бар и обрезался.
    // Экран выбираем тот, над которым сейчас курсор, иначе на втором мониторе
    // окно прижималось бы к границам главного.
    private func clampToScreen(_ p: CGPoint) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let vis = screen?.visibleFrame else { return p }
        let h = win.frame.height
        return CGPoint(
            x: min(max(p.x, vis.minX), vis.maxX - W),
            y: min(max(p.y, vis.minY), vis.maxY - h))
    }

    private func placeWindow() {
        let vis = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if let a = UserDefaults.standard.array(forKey: KEY) as? [Double], a.count == 2 {
            let p = CGPoint(x: a[0], y: a[1])
            // не даём улететь за пределы экрана после смены монитора
            if vis.insetBy(dx: -W, dy: -win.frame.height).contains(p) {
                win.setFrameOrigin(clampToScreen(p)); return
            }
        }
        win.setFrameOrigin(CGPoint(x: vis.maxX - W - 28, y: vis.minY + 24))
    }

    private func savePosition() {
        let o = win.frame.origin
        UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: KEY)
    }
}

// Ловит перетаскивание и клики. Отдельный класс, чтобы окно не двигалось от клика мимо фигурки.
final class DragRoot: NSView {
    var onDrag: ((CGPoint) -> Void)?
    var onDrop: (() -> Void)?
    var onClick: ((Int) -> Void)?        // номер фигурки, по которой щёлкнули
    var onFiles: (([String]) -> Void)?
    var columnWidth: CGFloat = 150

    private var last: NSPoint?
    private var moved = false

    override var isFlipped: Bool { true }

    override func awakeFromNib() { registerForDraggedTypes([.fileURL]) }

    override func mouseDown(with e: NSEvent) {
        last = NSEvent.mouseLocation
        moved = false
    }

    override func mouseDragged(with e: NSEvent) {
        guard let l = last else { return }
        let now = NSEvent.mouseLocation
        if abs(now.x - l.x) > 2 || abs(now.y - l.y) > 2 { moved = true }
        onDrag?(CGPoint(x: now.x - l.x, y: now.y - l.y))
        last = now
    }

    override func mouseUp(with e: NSEvent) {
        last = nil
        if !moved {
            // клик без перетаскивания — открыть сессию той фигурки, по которой попали
            let p = convert(e.locationInWindow, from: nil)
            onClick?(max(0, Int(p.x / max(columnWidth, 1))))
        }
        onDrop?()
    }

    // --- приём файлов ---

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        alphaValue = 0.65
        return .copy
    }

    override func draggingExited(_ s: NSDraggingInfo?) { alphaValue = 1 }

    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        alphaValue = 1
        guard let urls = s.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty
        else { return false }
        onFiles?(urls.map { $0.path })
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
