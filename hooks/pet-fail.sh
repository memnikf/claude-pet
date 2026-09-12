#!/bin/zsh
# Инструмент упал — питомец вздрагивает и держит метку, пока не пойдёт следующий успех.
source "${0:h}/pet-lib.sh"
D="$HOME/.claude/.pet"
j=$(cat 2>/dev/null)
sid=$(print -r -- "$j" | /usr/bin/jq -r '.session_id // empty' 2>/dev/null)
[[ -n $sid && -f "$D/$sid.json" ]] || exit 0
f="$D/$sid.json"
if [[ ${1:-} == clear ]]; then
  petjq "$f" 'del(.fail)'
else
  t=$(print -r -- "$j" | /usr/bin/jq -r '.tool_name // ""' 2>/dev/null)
  petjq "$f" --arg t "$t" --argjson ts "$(date +%s)" '. + {fail:$t, failAt:$ts}'
fi

# Пересчитываем сводку: во время работы состояние не меняется, а питомец
# читает только .pet-state.json — без этого он засыпал бы на 30-й минуте.
"${0:h}/pet-roll.sh"
exit 0
