#!/bin/zsh
# Сводит файлы сессий в ~/.claude/.pet-state.json.
# Вынесено из pet-state.sh: пересчёт нужен и там, где состояние не меняется
# (PostToolUse), иначе сводка застывает на времени последнего промпта и
# питомец засыпает посреди работы.
D="$HOME/.claude/.pet"
OUT="$HOME/.claude/.pet-state.json"

# чистим следы сессий, которые закрылись молча
find "$D" -name '*.json' -mmin +180 -delete 2>/dev/null
# следы прежней схемы записи: недописанные .tmp и нулевые файлы сессий
find "$D" \( -name '*.json.tmp' -o -name '*.lock' \) -mmin +5 -delete 2>/dev/null
find "$D" -name '*.json' -empty -delete 2>/dev/null

live=$(ps ax -o command | grep -cE '^(/[^ ]*/)?claude( |$)' 2>/dev/null || echo 0)

# В сводку берём только непустые файлы: битый или нулевой вход валит весь jq -s,
# и питомец разом терял все сессии.
files=(); for f in "$D"/*.json(N); do [[ -s $f ]] && files+=("$f"); done
(( ${#files} )) || files=(/dev/null)

# приоритет: кто просит внимания — важнее того, кто просто работает
/usr/bin/jq -s --argjson live "${live:-0}" --argjson now "$(date +%s)" '
  def rank: {ask:5, limit:4, compact:4, work:3, idle:2, sleep:1}[.state] // 0;
  # ask/limit живут 10 минут: сессия могла закрыться молча, а «жду ответа»
  # с приоритетом висело бы вечно и врало. work/idle живут дольше.
  # Запись без ts и state — это файл, который успел завести только статуслайн
  # (он пишет pct/cost, а состояние ставит хук). Без страховки `$now - null`
  # валил ВЕСЬ jq -s, и питомец разом терял все сессии и «спал» во время работы.
  def alive: (.ts // 0) > 0 and (.state // "") != ""
             and ($now - .ts) < (if (.state == "ask" or .state == "limit") then 600 else 1800 end);
  map(select(type == "object" and alive))
  | if length == 0 then
      {state: (if $live > 0 then "sleep" else "off" end), dir: "", live: $live, ts: $now}
    else
      (sort_by(rank, .ts) | last) as $top
      | {state: $top.state, dir: $top.dir, live: $live, ts: $top.ts,
         pct: ($top.pct // 0), cost: ($top.cost // 0), chan: ($top.chan // ""),
         tool: ($top.tool // ""), since: ($top.since // $top.ts), fail: ($top.fail // ""), lim5: ($top.lim5 // 0), lim7: ($top.lim7 // 0),
         # все живые сессии — питомец может показать ряд вместо одной фигурки
         # Поля с // : у сессии, которую статуслайн ещё не трогал, их нет вовсе,
         # а null в Swift-разборе давал пустую подпись вместо цифр.
         all: (sort_by(rank, .ts) | reverse | map({state, dir, ts,
                pct: (.pct // 0), cost: (.cost // 0), chan: (.chan // ""),
                tool: (.tool // ""), since: (.since // .ts),
                fail: (.fail // ""), lim5: (.lim5 // 0)}))}
    end
' $files 2>/dev/null > "$OUT.tmp.$$" && mv -f "$OUT.tmp.$$" "$OUT" || \
  /usr/bin/jq -n --argjson live "${live:-0}" --argjson now "$(date +%s)" \
    '{state: (if $live > 0 then "sleep" else "off" end), dir:"", live:$live, ts:$now}' > "$OUT"
exit 0
