import AppKit

// Питомец Claude Code: окно поверх всех окон, без рамки, тянется мышью.
// Состояние читает из ~/.claude/.pet-state.json, куда пишут хуки.

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = PetDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // без иконки в Dock и без меню
        app.run()
    }
}

struct Day {
    var prompts = 0, sessions = 0, tools = 0
    var cost = 0.0, lines = 0
    var first = 0.0, last = 0.0

    static func load() -> Day {
        var d = Day()
        let p = NSHomeDirectory() + "/.claude/.pet-day.json"
        guard let f = FileManager.default.contents(atPath: p),
              let o = try? JSONSerialization.jsonObject(with: f) as? [String: Any]
        else { return d }
        d.prompts = o["prompts"] as? Int ?? 0
        d.tools = o["tools"] as? Int ?? 0
        d.sessions = (o["sessions"] as? [String])?.count ?? 0
        d.first = o["first"] as? Double ?? 0
        d.last = o["last"] as? Double ?? 0
        // расход и правки лежат по сессиям — складываем
        if let c = o["costs"] as? [String: Double] { d.cost = c.values.reduce(0, +) }
        if let l = o["lines"] as? [String: Int] { d.lines = l.values.reduce(0, +) }
        return d
    }

    // Сколько подряд без перерыва: питомец разок потягивается через два часа.
    var hoursStraight: Double {
        guard first > 0, last > 0 else { return 0 }
        return (last - first) / 3600
    }
}

struct PetState {
    var state = "off"
    var dir = ""
    var live = 0
    var ts = 0.0
    var pct = 0          // сколько контекста съедено
    var cost = 0.0       // расход по сессии, $
    var chan = ""        // какой роутер
    var tool = ""        // чем занят прямо сейчас
    var since = 0.0      // когда вошёл в это состояние — для таймера
    var fail = ""        // какой инструмент упал последним
    var lim5 = 0         // пятичасовое окно лимита, %
    var lim7 = 0         // недельное окно, %

    // Все живые сессии: питомец показывает ряд, если их больше одной.
    static func loadAll() -> [PetState] {
        let p = NSHomeDirectory() + "/.claude/.pet-state.json"
        guard let d = FileManager.default.contents(atPath: p),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = o["all"] as? [[String: Any]], !arr.isEmpty
        else { return [load()] }

        var out: [PetState] = []
        for e in arr.prefix(4) {
            var s = PetState()
            s.state = e["state"] as? String ?? "off"
            s.dir = e["dir"] as? String ?? ""
            s.pct = e["pct"] as? Int ?? 0
            s.cost = e["cost"] as? Double ?? 0
            s.chan = e["chan"] as? String ?? ""
            s.tool = e["tool"] as? String ?? ""
            s.ts = e["ts"] as? Double ?? 0
            s.since = e["since"] as? Double ?? 0
            s.fail = e["fail"] as? String ?? ""
            s.lim5 = e["lim5"] as? Int ?? 0
            s.live = arr.count
            let age = Date().timeIntervalSince1970 - s.ts
            if s.state == "idle" && age > 300 { s.state = "sleep" }
            out.append(s)
        }
        return out.isEmpty ? [load()] : out
    }

    static func load() -> PetState {
        var s = PetState()
        let p = NSHomeDirectory() + "/.claude/.pet-state.json"
        guard let d = FileManager.default.contents(atPath: p),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return s }
        s.state = o["state"] as? String ?? "off"
        s.dir = o["dir"] as? String ?? ""
        s.live = o["live"] as? Int ?? 0
        s.ts = o["ts"] as? Double ?? 0
        s.pct = o["pct"] as? Int ?? 0
        s.cost = o["cost"] as? Double ?? 0
        s.chan = o["chan"] as? String ?? ""
        s.tool = o["tool"] as? String ?? ""
        s.since = o["since"] as? Double ?? 0
        s.fail = o["fail"] as? String ?? ""
        s.lim5 = o["lim5"] as? Int ?? 0
        s.lim7 = o["lim7"] as? Int ?? 0

        // состояние протухло — не врём, что агент работает
        let age = Date().timeIntervalSince1970 - s.ts
        if s.state != "off" && age > 1800 { s.state = s.live > 0 ? "sleep" : "off" }
        if s.state == "idle" && age > 300 { s.state = "sleep" }
        return s
    }

    // Что за инструмент крутится: короткий значок и подпись.
    var toolMark: (String, String)? {
        guard state == "work", !tool.isEmpty else { return nil }
        switch tool {
        case "Bash":                     return ("\u{203A}_", "команда")
        case "Edit", "Write", "NotebookEdit": return ("\u{270E}", "правит файл")
        case "Read":                     return ("\u{2016}", "читает")
        case "Grep", "Glob":             return ("\u{2315}", "ищет")
        case "WebFetch", "WebSearch":    return ("\u{2601}", "смотрит в сеть")
        case "Agent", "Task":            return ("\u{2687}", "агенты")
        case "Skill":                    return ("\u{2726}", "скилл")
        default:                          return ("\u{2699}", tool.lowercased())
        }
    }

    // Сколько уже длится текущее состояние — показываем от минуты.
    var elapsed: String? {
        guard since > 0, state == "work" || state == "compact" else { return nil }
        let sec = Int(Date().timeIntervalSince1970 - since)
        guard sec >= 60 else { return nil }
        let m = sec / 60
        return m < 60 ? "\(m) мин" : "\(m / 60) ч \(m % 60) мин"
    }

    var say: String {
        switch state {
        case "compact": return "сжимаю контекст"
        case "work":  return "работаю"
        case "ask":   return "жду ответа"
        case "idle":  return "готов"
        case "sleep": return "сплю"
        case "limit": return "лимит"
        default:      return "не запущен"
        }
    }

    // Цвет тела: оранжевый как в шапке CLI, либо синий. Переключается в меню.
    static var orange: Bool {
        get { UserDefaults.standard.object(forKey: "petOrange") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petOrange") }
    }

    var body: NSColor {
        switch state {
        case "ask":   return NSColor(srgbRed: 0.976, green: 0.886, blue: 0.686, alpha: 1) // #f9e2af
        case "compact": return NSColor(srgbRed: 0.796, green: 0.651, blue: 0.969, alpha: 1) // #cba6f7
        case "limit": return NSColor(srgbRed: 0.953, green: 0.545, blue: 0.659, alpha: 1) // #f38ba8
        case "sleep": return PetState.orange
            ? NSColor(srgbRed: 0.588, green: 0.435, blue: 0.373, alpha: 1)
            : NSColor(srgbRed: 0.404, green: 0.443, blue: 0.588, alpha: 1)
        case "off":   return PetState.orange
            ? NSColor(srgbRed: 0.435, green: 0.333, blue: 0.290, alpha: 1)
            : NSColor(srgbRed: 0.310, green: 0.341, blue: 0.463, alpha: 1)
        default:      return PetState.orange
            ? NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)   // #d97757
            : NSColor(srgbRed: 0.537, green: 0.671, blue: 0.937, alpha: 1)   // #89abef
        }
    }

    var edge: NSColor {
        body.blended(withFraction: 0.30, of: .black) ?? body
    }

    // светлый блик сверху — облако выглядит объёмным
    var light: NSColor {
        body.blended(withFraction: 0.22, of: .white) ?? body
    }

    // мятный цвет символов на экране-морде
    var glyph: NSColor {
        state == "ask" || state == "limit"
            ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.180, alpha: 1)
            : (PetState.orange
                ? NSColor(srgbRed: 0.988, green: 0.890, blue: 0.855, alpha: 1)
                : NSColor(srgbRed: 0.580, green: 0.886, blue: 0.835, alpha: 1))  // #94e2d5
    }
}
