#!/bin/zsh
# Пишет состояние агента для питомца. Состояние передаётся первым аргументом.
# Каждая сессия ведёт СВОЙ файл, иначе закрывшаяся сессия гасила питомца,
# пока другая работала. Итог сводится в .pet-state.json по приоритету.
source "${0:h}/pet-lib.sh"
D="$HOME/.claude/.pet"
OUT="$HOME/.claude/.pet-state.json"
state=${1:-idle}
j=$(cat 2>/dev/null)
mkdir -p "$D"

pick() { print -r -- "$j" | /usr/bin/jq -r "$1 // empty" 2>/dev/null }
sid=$(pick .session_id); dir=$(pick .cwd)
: ${sid:=нет-id}

if [[ $state == off ]]; then
  rm -f "$D/$sid.json"
else
  # pct/cost/chan дописывает статуслайн — сохраняем их при смене состояния.
  # since — когда вошли в текущее состояние: по нему видно, сколько агент думает.
  petjq "$D/$sid.json" --arg s "$state" --arg d "${dir:t}" --argjson ts "$(date +%s)" \
    '. + {state:$s, dir:$d, ts:$ts,
          since: (if .state == $s then (.since // $ts) else $ts end)}'
fi

exec "${0:h}/pet-roll.sh"
