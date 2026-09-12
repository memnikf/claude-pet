#!/bin/zsh
# Дневная копилка: сколько сессий, денег и правок за сегодня. Питомец
# показывает сводку вечером, плюс по ней считается «пора отдохнуть».
source "${0:h}/pet-lib.sh"
F="$HOME/.claude/.pet-day.json"
j=$(cat 2>/dev/null)
today=$(date +%F)
now=$(date +%s)

pick() { print -r -- "$j" | /usr/bin/jq -r "$1 // empty" 2>/dev/null }
sid=$(pick .session_id)
kind=${1:-prompt}

petjq "$F" --arg day "$today" --arg sid "$sid" --arg kind "$kind" --argjson now "$now" '
  # новый день — начинаем с нуля
  (if .day != $day then {day: $day, prompts: 0, sessions: [], first: $now, last: $now, tools: 0} else . end)
  | .last = $now
  | .first = (.first // $now)
  | if $kind == "prompt" then
      .prompts += 1
      | .sessions = ((.sessions // []) + [$sid] | unique)
    else .tools += 1 end
'
exit 0
