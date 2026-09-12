import AppKit

// Спрайт талисмана Claude Code: голова с усиками, глаза-пиксели, четыре лапки.
// Рисуем прямоугольниками по сетке 32x32, как в пиксельном оригинале.
final class PetView: NSView {
    var st = PetState()
    var stretch = false        // «пора отдохнуть» — разовое потягивание
    private var phase: CGFloat = 0
    private var blink: CGFloat = 0
    private var stretchT: CGFloat = -1

    override var isFlipped: Bool { true }

    func tick(_ dt: CGFloat) {
        phase += dt
        if stretch && stretchT < 0 { stretchT = 0 }
        if stretchT >= 0 {
            stretchT += dt
            if stretchT > 2.4 { stretchT = -1; stretch = false }
        }
        blink += dt
        if blink > 5.2 { blink = 0 }
        needsDisplay = true
    }

    // смещение и сжатие тела под текущее состояние
    private var motion: (dy: CGFloat, sx: CGFloat, sy: CGFloat, dx: CGFloat) {
        // потягивание перебивает обычную анимацию
        if stretchT >= 0 {
            let t = stretchT / 2.4
            let up = sin(t * .pi)
            return (-4 * up, 1 - 0.06 * up, 1 + 0.10 * up, 0)
        }
        // упал инструмент — короткая дрожь
        if !st.fail.isEmpty {
            return (0, 1, 1, sin(phase * 22) * 1.8)
        }
        switch st.state {
        case "work":                       // подпрыгивает
            let t = fmod(phase, 0.62) / 0.62
            let up = sin(t * .pi)
            return (-7 * up, 1 + 0.05 * (1 - up), 1 - 0.05 * (1 - up), 0)
        case "ask", "limit":               // дёргается
            return (0, 1, 1, sin(phase * 15) * 2.5)
        case "sleep", "off":               // покачивается медленно
            return (sin(phase * 1.35) * 2, 1, 1, 0)
        default:                           // дышит
            return (sin(phase * 1.85) * 3, 1, 1, 0)
        }
    }

    // Запас сверху: на подскоке шапка уезжала за край окна и обрезалась.
    static let pad: CGFloat = 14

    // Один раз на класс: пересоздание шрифта на каждом кадре валило CoreText.
    private static func mono(_ size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(6, size), weight: .bold)
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, bounds.width > 1 else { return }
        let unit = bounds.width / 32.0        // размер «пикселя» сетки
        let m = motion

        ctx.saveGState()
        ctx.translateBy(x: bounds.midX + m.dx, y: bounds.midY + m.dy)
        ctx.scaleBy(x: m.sx, y: m.sy)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        ctx.translateBy(x: 0, y: PetView.pad)   // сдвигаем вниз, освобождая верх


        let body = st.body, edge = st.edge, light = st.light, glyph = st.glyph
        let screen = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1)  // #1e1e2e

        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: NSColor) {
            c.setFill()
            ctx.fill(CGRect(x: x * unit, y: y * unit, width: w * unit, height: h * unit))
        }
        func dot(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c: NSColor) {
            c.setFill()
            ctx.fillEllipse(in: CGRect(x: (cx - r) * unit, y: (cy - r) * unit,
                                       width: 2 * r * unit, height: 2 * r * unit))
        }

        // --- облачная шапка: кругами, светлее сверху ---
        dot(11.0, 7.6, 4.3, light)
        dot(16.0, 6.0, 5.0, light)
        dot(21.0, 7.6, 4.3, light)
        dot(8.0, 10.4, 3.6, body)
        dot(24.0, 10.4, 3.6, body)
        dot(12.5, 10.0, 4.6, body)
        dot(19.5, 10.0, 4.6, body)
        px(5.2, 9.0, 21.6, 4.2, body)

        // --- экран-морда ---
        let sx: CGFloat = 8.4, sy: CGFloat = 11.4, sw: CGFloat = 15.2, sh: CGFloat = 8.4
        let sr = NSBezierPath(roundedRect:
            CGRect(x: sx * unit, y: sy * unit, width: sw * unit, height: sh * unit),
            xRadius: unit * 1.4, yRadius: unit * 1.4)
        screen.setFill(); sr.fill()
        edge.setStroke(); sr.lineWidth = unit * 0.55; sr.stroke()

        // символы на экране: > и _ , либо глаза под состояние
        let shut = (blink > 5.1) || st.state == "sleep" || st.state == "off"
        if shut {
            px(11.0, 15.4, 3.4, 0.9, glyph)
            px(17.6, 15.4, 3.4, 0.9, glyph)
        } else if st.state == "ask" {
            // растерянные глаза-крестики
            px(11.4, 13.4, 0.9, 3.4, glyph); px(11.4, 16.4, 2.6, 0.9, glyph)
            px(19.7, 13.4, 0.9, 3.4, glyph); px(17.4, 16.4, 2.6, 0.9, glyph)
        } else {
            // приглашение >_
            px(10.8, 13.6, 0.9, 0.9, glyph)
            px(11.7, 14.5, 0.9, 0.9, glyph)
            px(12.6, 15.4, 0.9, 0.9, glyph)
            px(11.7, 16.3, 0.9, 0.9, glyph)
            px(10.8, 17.2, 0.9, 0.9, glyph)
            px(17.6, 17.2, 3.4, 0.9, glyph)
        }

        // --- тело ---
        let br = NSBezierPath(roundedRect:
            CGRect(x: 10.2 * unit, y: 19.8 * unit, width: 11.6 * unit, height: 7.4 * unit),
            xRadius: unit * 1.6, yRadius: unit * 1.6)
        body.setFill(); br.fill()

        // экранчик на животе
        let cr = NSBezierPath(roundedRect:
            CGRect(x: 12.2 * unit, y: 21.6 * unit, width: 7.6 * unit, height: 3.4 * unit),
            xRadius: unit * 0.7, yRadius: unit * 0.7)
        screen.setFill(); cr.fill()
        px(13.0, 22.4, 0.8, 0.8, glyph)
        px(13.8, 23.2, 0.8, 0.8, glyph)
        px(13.0, 24.0, 0.8, 0.8, glyph)
        px(15.6, 24.0, 2.6, 0.8, glyph)

        // руки
        dot(9.2, 21.6, 1.7, body)
        dot(22.8, 21.6, 1.7, body)
        px(8.2, 21.8, 2.0, 3.0, body)
        px(21.8, 21.8, 2.0, 3.0, body)

        // ноги
        px(12.2, 27.0, 3.0, 2.2, body)
        px(16.8, 27.0, 3.0, 2.2, body)
        dot(13.7, 29.0, 1.5, edge)
        dot(18.3, 29.0, 1.5, edge)

        ctx.restoreGState()

        // метка проекта: две первые буквы в уголке головы, чтобы различать сессии глазом
        if !st.dir.isEmpty {
            let tag = String(st.dir.replacingOccurrences(of: ".", with: "").prefix(2)).uppercased()
            let at: [NSAttributedString.Key: Any] = [
                .font: PetView.mono(unit * 2.2),
                .foregroundColor: st.edge.withAlphaComponent(0.75),
            ]
            NSAttributedString(string: tag, attributes: at)
                .draw(at: CGPoint(x: unit * 4.6, y: PetView.pad + unit * 12.4))
        }

        // значок инструмента — пузырёк над головой, пока агент им занят
        if let (mark, _) = st.toolMark {
            let fs = unit * 3.6
            let at: [NSAttributedString.Key: Any] = [
                .font: PetView.mono(fs),
                .foregroundColor: st.glyph.withAlphaComponent(0.85),
            ]
            let str = NSAttributedString(string: mark, attributes: at)
            let sz = str.size()
            let cx = bounds.width * 0.80
            let cy = PetView.pad + unit * 1.2 + sin(phase * 2.2) * unit * 0.35
            let pad = unit * 1.1
            let box = CGRect(x: cx - sz.width / 2 - pad, y: cy - pad * 0.5,
                             width: sz.width + pad * 2, height: sz.height + pad)
            let bub = NSBezierPath(roundedRect: box, xRadius: unit * 1.4, yRadius: unit * 1.4)
            NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 0.80).setFill()
            bub.fill()
            st.edge.withAlphaComponent(0.5).setStroke()
            bub.lineWidth = max(1, unit * 0.35)
            bub.stroke()
            str.draw(at: CGPoint(x: box.midX - sz.width / 2, y: box.minY + pad * 0.5))
        }

        // «z z» когда спит, «!» когда нужен ответ
        if st.state == "sleep" || st.state == "off" {
            let a = 0.45 + 0.45 * sin(phase * 1.7)
            draw(text: "z z", at: CGPoint(x: bounds.width * 0.70, y: bounds.height * 0.06),
                 size: unit * 3.4, color: NSColor(white: 0.72, alpha: max(0, a)))
        } else if st.state == "ask" || st.state == "limit" {
            let a = 0.55 + 0.45 * sin(phase * 6)
            draw(text: "!", at: CGPoint(x: bounds.width * 0.80, y: bounds.height * 0.02),
                 size: unit * 5, color: st.body.withAlphaComponent(max(0, a)))
        }
    }

    private func draw(text: String, at p: CGPoint, size: CGFloat, color: NSColor) {
        let at: [NSAttributedString.Key: Any] = [
            .font: PetView.mono(size),
            .foregroundColor: color,
        ]
        NSAttributedString(string: text, attributes: at).draw(at: p)
    }
}
