#!/usr/bin/env bash
# Ритуал старта: команда /старт в комментах -> мантра + топ-задача в работу + чеклист.
set -uo pipefail
REPO="${REPO:-del0x3/taskflow}"
NUM="${NUM:?нужен NUM}"
BODY="${BODY:-}"
AUTHOR="${AUTHOR:-}"
TZL="${TZL:-Europe/Kiev}"

# только владелец
[ "$AUTHOR" = "del0x3" ] || { echo "не владелец — пропуск"; exit 0; }

# первый токен команды
first=$(printf '%s' "$BODY" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
case "$first" in
  /старт|/start) : ;;
  *) echo "не команда старта ($first)"; exit 0 ;;
esac

# топ-приоритетная задача в фокусе (Сегодня), без привычек/доски
top=$(gh issue list -R "$REPO" --state open --label "Сегодня" --limit 100 \
  --json number,title,labels,author \
  -q '[.[] | select(.author.login=="del0x3" or .author.login=="github-actions[bot]")
        | select([.labels[].name] | (index("Привычка") or index("Доска")) | not)
        | . + {r: (if ([.labels[].name]|index("Критично")) then 1
                   elif ([.labels[].name]|index("Высокий")) then 2
                   elif ([.labels[].name]|index("Средний")) then 3 else 4 end)}]
      | sort_by(.r) | (.[0] // null) | if .==null then "" else "\(.number)\t\(.title)" end' 2>/dev/null || echo "")

tnum=""; ttitle=""
if [ -n "$top" ]; then tnum="${top%%	*}"; ttitle="${top#*	}"; fi

# мантра дня (ротация по дню года, стабильна в течение дня)
cnt=$(jq '.mantras | length' mantras.json 2>/dev/null || echo 1)
idx=$(( $(date +%j) % cnt ))
mantra=$(jq -r ".mantras[$idx]" mantras.json 2>/dev/null || echo "Просто начни.")

if [ -n "$tnum" ]; then
  gh issue edit "$tnum" -R "$REPO" --add-label "В работе" >/dev/null 2>&1 || true
  focus="🎯 **Главное сейчас:** #$tnum — $ttitle
_(взял в работу — таймер пошёл ⏱)_"
else
  focus="🎯 На сегодня нет задач в фокусе. Заведи одну — и вперёд."
fi

gh issue comment "$NUM" -R "$REPO" --body "🧘 **Старт.**

> $mantra

$focus

Перед стартом — 10 секунд:
- 📵 Телефон — экраном вниз / в другую комнату
- 💧 Вода рядом
- 🗂 Лишние вкладки — закрыть
- 🧠 Только эта задача. Остальное подождёт.

Поехали. 🚀" >/dev/null
echo "ритуал запущен (задача #${tnum:-—})"
