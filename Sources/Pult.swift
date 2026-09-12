import AppKit

// Лёгкая версия того, что умеет «Пульт»: список последних сессий, запуск в Ghostty,
// расход по ключу и переключение эндпоинта. Файлы те же, что правит claude-key.

struct Sess {
    let id: String
    let title: String
    let dir: String
    let date: Date
}

enum Pult {
    static let home = NSHomeDirectory()
    static let wrapper = home + "/.local/bin/claude-alt"
    static let conf = home + "/.config/claude-alt.json"
    static let token = home + "/.config/claude-alt.token"

    // --- сессии ---

    // Служебные строки, которые лезут в заголовок, если у сессии нет ai-title.
    private static func noise(_ s: String) -> Bool {
        s.isEmpty || s.hasPrefix("[Request interrupted") || s.hasPrefix("<command-")
            || s.hasPrefix("Caveat:") || s.hasPrefix("<system-reminder")
    }

    static func recent(limit: Int = 8) -> [Sess] {
        let root = URL(fileURLWithPath: home + "/.claude/projects")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }

        var out: [Sess] = []
        for d in dirs {
            let files = (try? fm.contentsOfDirectory(
                at: d, includingPropertiesForKeys: [.contentModificationDateKey]))?
                .filter { $0.pathExtension == "jsonl" } ?? []
            // читаем только свежие: разбирать все транскрипты дорого
            let fresh = files.compactMap { f -> (URL, Date)? in
                guard let m = try? f.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate else { return nil }
                return (f, m)
            }.sorted { $0.1 > $1.1 }.prefix(3)

            for (f, when) in fresh {
                if let s = read(f, when) { out.append(s) }
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    private static func read(_ file: URL, _ when: Date) -> Sess? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var title = "", first = "", cwd = ""

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let d = line.data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }
            if cwd.isEmpty, let c = o["cwd"] as? String { cwd = c }
            if let t = o["type"] as? String, t == "ai-title",
               let v = o["aiTitle"] as? String, !v.isEmpty { title = v }
            if first.isEmpty, let t = o["type"] as? String, t == "user" {
                if let m = o["message"] as? [String: Any] {
                    if let s = m["content"] as? String { first = s }
                    else if let arr = m["content"] as? [[String: Any]] {
                        first = arr.compactMap { $0["text"] as? String }.first ?? ""
                    }
                }
            }
            if !title.isEmpty && !cwd.isEmpty { break }
        }

        var name = title
        if name.isEmpty {
            let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
            name = noise(t) ? "" : String(t.prefix(52))
        }
        if name.isEmpty { name = "без названия" }

        let id = file.deletingPathExtension().lastPathComponent
        let short = cwd.hasPrefix(home) ? "~" + cwd.dropFirst(home.count) : cwd
        return Sess(id: id, title: name, dir: short.isEmpty ? "~" : String(short), date: when)
    }

    static func resume(_ s: Sess) {
        let folder = s.dir.hasPrefix("~") ? home + s.dir.dropFirst() : s.dir
        run("/usr/bin/open", ["-na", "Ghostty", "--args",
                              "--working-directory=" + folder, "-e", wrapper,
                              "--resume", s.id, "--dangerously-skip-permissions"])
    }

    static func newSession(in folder: String) {
        run("/usr/bin/open", ["-na", "Ghostty", "--args",
                              "--working-directory=" + folder, "-e", wrapper,
                              "--dangerously-skip-permissions"])
    }

    // --- эндпоинты ---

    // Список берётся из ~/.config/claude-alt.json (ключ "endpoints"), чтобы свои
    // роутеры не лежали в коде. Формат: [{"name": "…", "url": "…", "note": "…"}].
    // Нет файла или ключа — остаётся только официальный адрес.
    static var endpoints: [(String, String, String)] {
        var out: [(String, String, String)] = []
        if let d = FileManager.default.contents(atPath: conf),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = o["endpoints"] as? [[String: Any]] {
            for e in arr {
                guard let u = e["url"] as? String, !u.isEmpty else { continue }
                out.append((e["name"] as? String ?? u, u, e["note"] as? String ?? ""))
            }
        }
        if !out.contains(where: { $0.1.contains("api.anthropic.com") }) {
            out.append(("официальный", "https://api.anthropic.com", "подписка"))
        }
        return out
    }

    static func currentEndpoint() -> String {
        guard let d = FileManager.default.contents(atPath: conf),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let e = o["endpoint"] as? String else { return "" }
        return e
    }

    // Правим только endpoint и model, остальные поля файла не трогаем:
    // его же читают claude-alt и «Пульт».
    static func setEndpoint(_ url: String) {
        guard let d = FileManager.default.contents(atPath: conf),
              var o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return }
        o["endpoint"] = url
        if let models = o["models"] as? [String: Any], let m = models[url] as? String {
            o["model"] = m
        }
        if let keys = o["keys"] as? [String: Any], let k = keys[url] as? String,
           k.hasPrefix("sk-") {
            try? k.write(toFile: token, atomically: true, encoding: .utf8)
            chmod(token, 0o600)
        }
        if let out = try? JSONSerialization.data(withJSONObject: o) {
            try? out.write(to: URL(fileURLWithPath: conf))
        }
    }

    // --- расход ---

    static func usage(_ done: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            let key = (try? String(contentsOfFile: token, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // Адрес панели — из конфига ("usageUrl"): у каждого роутера он свой,
            // а у официального API такого счётчика нет вовсе.
            var api = ""
            if let d = FileManager.default.contents(atPath: conf),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                api = o["usageUrl"] as? String ?? ""
            }
            guard !key.isEmpty, !api.isEmpty, let u = URL(string: api)
            else { return done(key.isEmpty ? "расход: нет ключа" : "расход: не настроен") }

            var r = URLRequest(url: u)
            r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            r.timeoutInterval = 15
            URLSession.shared.dataTask(with: r) { data, _, _ in
                guard let data,
                      let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let cents = o["total_usage"] as? Double
                else { return done("расход: не отвечает") }
                // единицы — центы; это не накопительный итог, цифра ходит в обе стороны
                done(String(format: "расход ≈ $%.2f", cents / 100))
            }.resume()
        }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do { try p.run() } catch { return false }
        return true
    }
}
