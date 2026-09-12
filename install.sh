#!/bin/zsh
# Установка питомца: собирает приложение, кладёт хуки и прописывает их
# в ~/.claude/settings.json, ничего чужого не затирая.
set -e
cd "${0:A:h}"
H="$HOME/.claude"
S="$H/settings.json"

command -v /usr/bin/xcrun >/dev/null || { print -u2 "нужны Command Line Tools: xcode-select --install"; exit 1 }
command -v /usr/bin/jq   >/dev/null || { print -u2 "нужен jq: brew install jq"; exit 1 }

print "1/4 собираю приложение"
zsh ./build.sh >/dev/null

print "2/4 кладу хуки в $H/hooks"
mkdir -p "$H/hooks"
for f in hooks/*.sh; do
  t="$H/${f}"
  [[ -f $t ]] && cp "$t" "$t.bak-pet-$(date +%Y%m%d-%H%M%S)"
  cp "$f" "$t"; chmod +x "$t"
done

print "3/4 прописываю хуки в settings.json"
[[ -f $S ]] || print -r -- '{}' > "$S"
cp "$S" "$S.bak-pet-$(date +%Y%m%d-%H%M%S)"

# Свои группы добавляем к существующим, а не заменяем массив: в тех же событиях
# у людей висят свои хуки (звук, линтеры), и перезапись их бы снесла.
# Повторный запуск ничего не дублирует — группы с pet-*.sh сначала вычищаются.
/usr/bin/jq '
  def strip(ev): (.hooks[ev] // []) | map(select((.hooks // []) | map(.command // "") | join(" ") | test("pet-[a-z]*\\.sh") | not));
  def add(ev; cmd; m):
    .hooks[ev] = (strip(ev) + [ (if m == null then {} else {matcher: m} end)
      + {hooks: [{type: "command", command: cmd, timeout: 5}]} ]);
  .hooks = (.hooks // {})
  | add("SessionStart";       "~/.claude/hooks/pet-state.sh idle"; null)
  | add("UserPromptSubmit";   "~/.claude/hooks/pet-state.sh work"; null)
  | add("Stop";               "~/.claude/hooks/pet-state.sh idle"; null)
  | add("SessionEnd";         "~/.claude/hooks/pet-state.sh off";  null)
  | add("PreCompact";         "~/.claude/hooks/pet-state.sh compact"; null)
  | add("PreToolUse";         "~/.claude/hooks/pet-tool.sh auto";  null)
  | add("PostToolUseFailure"; "~/.claude/hooks/pet-fail.sh";       null)
  | add("Notification";       "~/.claude/hooks/pet-state.sh ask";
        "permission_prompt|idle_prompt|agent_needs_input|elicitation_dialog")
  | add("StopFailure";        "~/.claude/hooks/pet-state.sh limit";
        "rate_limit|overloaded|billing_error")
  # PostToolUse: три хука подряд, поэтому чистим один раз и добавляем все три
  | .hooks["PostToolUse"] = (strip("PostToolUse")
      + (["~/.claude/hooks/pet-tool.sh",
          "~/.claude/hooks/pet-day.sh tool",
          "~/.claude/hooks/pet-fail.sh clear"]
         | map({hooks: [{type: "command", command: ., timeout: 5}]})))
' "$S" > "$S.new" && mv "$S.new" "$S"

print "4/4 запускаю"
pkill -f 'Питомец.app' 2>/dev/null || true
rm -f "$H/.pet.lock"
sleep 1
open ./Питомец.app

print ""
print "готово. Питомец появится на столе, когда запустишь Claude Code."
print "меню — ромб «◆» в строке состояния; выход оттуда же."
print ""
print "статусная строка (контекст, расход, лимиты) — отдельно, по желанию:"
print "  cp statusline.sh ~/.claude/ && добавь в settings.json:"
print '  "statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}'
