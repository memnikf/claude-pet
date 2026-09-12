#!/bin/zsh
# Строка состояния Claude Code. Гамма — Catppuccin Mocha.
export DEVELOPER_DIR=/Library/Developer/CommandLineTools

j=$(cat)
q() { print -r -- "$j" | /usr/bin/jq -r "$1 // empty" 2>/dev/null }

c() { print -n "\033[38;2;$1m" }
r=$'\033[0m'
mauve='203;166;247'
blue='137;180;250'
green='166;227;161'
yellow='249;226;175'
peach='250;180;135'
red='243;139;168'
teal='148;226;213'
grey='108;112;134'
text='205;214;244'

model=$(q .model.display_name)
dir=$(q .workspace.current_dir)
proj=$(q .workspace.project_dir)
pct=$(q .context_window.used_percentage)
size=$(q .context_window.context_window_size)
cost=$(q .cost.total_cost_usd)
ms=$(q .cost.total_duration_ms)
add=$(q .cost.total_lines_added)
del=$(q .cost.total_lines_removed)
eff=$(q .effort.level)
fast=$(q .fast_mode)
lim5=$(q .rate_limits.five_hour.used_percentage)
warm=$(q .prompt_cache.warm)

# --- строка 1: модель, эндпоинт, каталог, ветка ---
out="$(c $mauve)${model:-?}"
[[ $size -ge 1000000 ]] && out+="$(c $grey)·1M"
[[ $fast == true ]] && out+=" $(c $peach)⚡"
[[ -n $eff && $eff != medium ]] && out+=" $(c $grey)$eff"

# какой роутер сейчас (та же настройка, что читает claude-alt)
ep=$(/usr/bin/python3 -c 'import json;print(json.load(open("'"$HOME"'/.config/claude-alt.json")).get("endpoint",""))' 2>/dev/null)
case $ep in
  *api.anthropic.com*|'') label=офиц ;;
  # свой роутер подписывается доменом второго уровня: cc.example.org → example
  *) label=${${${ep#*://}%%/*}%.*}; label=${label##*.} ;;
esac
[[ -n $ANTHROPIC_BASE_URL || $label != офиц ]] && out+=" $(c $grey)│ $(c $teal)$label"

out+=" $(c $grey)│ $(c $blue)${dir:t}"
[[ -n $proj && $proj != $dir ]] && out+="$(c $grey)(${proj:t})"

if br=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null); then
  n=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  out+=" $(c $grey)│ $(c $green)⎇ $br"
  (( n > 0 )) && out+="$(c $yellow)*$n"
fi

# --- строка 2: контекст, деньги, время, правки ---
p=${${pct%%.*}:-0}
if   (( p < 50 )); then bc=$green
elif (( p < 75 )); then bc=$yellow
elif (( p < 90 )); then bc=$peach
else                    bc=$red; fi

w=14; full=$(( p * w / 100 ))
bar=''
for ((i=0;i<w;i++)); do (( i < full )) && bar+='━' || bar+='┈'; done
two="$(c $bc)$bar $(c $text)${p}%"

if [[ -n $cost ]]; then
  d=$(printf '%.2f' "$cost" 2>/dev/null)
  two+=" $(c $grey)│ $(c $text)\$$d"
  # Пересчёт в рубли — по желанию: ставка своя у каждого канала, задаётся
  # переменной PET_RATE (например PET_RATE=85). Не задана — показываем только $.
  if [[ -n $PET_RATE ]]; then
    ru=$(printf '%.0f' "$(( cost * PET_RATE ))" 2>/dev/null)
    [[ -n $ru && $ru != 0 ]] && two+="$(c $grey)/${ru}₽"
  fi
fi

if [[ -n $ms && $ms -gt 0 ]]; then
  s=$(( ms / 1000 )); m=$(( s / 60 ))
  (( m > 0 )) && two+=" $(c $grey)│ ${m}м" || two+=" $(c $grey)│ ${s}с"
fi

if [[ ( -n $add && $add -gt 0 ) || ( -n $del && $del -gt 0 ) ]]; then
  two+=" $(c $grey)│ $(c $green)+${add:-0}$(c $grey)/$(c $red)-${del:-0}"
fi

[[ -n $lim5 && ${lim5%%.*} -ge 60 ]] && two+=" $(c $peach)│ лимит ${lim5%%.*}%"
[[ $warm == false ]] && two+=" $(c $grey)│ кеш остыл"

print -r -- "${out}${r}"
print -r -- "${two}${r}"

# Отдаём питомцу то, что видно только здесь: контекст и расход по сессии.
# Хукам эти поля не приходят, а статуслайн вызывается часто.
sid=$(q .session_id)
if [[ -n $sid ]]; then
  source "$HOME/.claude/hooks/pet-lib.sh"
  D="$HOME/.claude/.pet"
  mkdir -p "$D"
  F="$D/$sid.json"
  # дневной итог: расход и правки. Складываем максимумы по сессиям,
  # потому что cost внутри сессии только растёт.
  DAY="$HOME/.claude/.pet-day.json"
  if [[ -f $DAY && -n $cost ]]; then
    petjq "$DAY" --arg sid "$sid" --arg c "${cost:-0}" \
      --argjson add "${add:-0}" --argjson del "${del:-0}" \
      '.costs = ((.costs // {}) + {($sid): ($c|tonumber)})
       | .lines = ((.lines // {}) + {($sid): ($add + $del)})'
  fi

  # Файл сессии правим, только если он уже есть: заводит его хук состояния,
  # а статуслайн лишь дописывает контекст и расход. Создавать его здесь нельзя —
  # сессия без состояния попала бы в сводку с rank 0 и гасила бы работающую.
  if [[ -f $F ]]; then
    petjq "$F" --argjson pct "${p:-0}" --arg cost "${cost:-0}" --arg lab "$label" \
      --argjson lim "${${lim5%%.*}:-0}" --argjson lim7 "${$(q .rate_limits.seven_day.used_percentage | cut -d. -f1):-0}" \
      '. + {pct:$pct, cost:($cost|tonumber), chan:$lab, lim5:$lim, lim7:$lim7}'
  fi
fi
