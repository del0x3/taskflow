#!/usr/bin/env bash
# Приёмка задач из issue-формы: проставляет метки, milestone, исполнителя, дедлайн.
set -euo pipefail
REPO="${REPO:-del0x3/taskflow}"
NUM="${NUM:?нужен NUM}"
TZL="${TZL:-Europe/Kiev}"

# Публичный репо: обрабатываем только issue от владельца
[ "${AUTHOR:-}" = "del0x3" ] || { echo "issue не от владельца (${AUTHOR:-?}) — пропуск"; exit 0; }

body=$(gh issue view "$NUM" -R "$REPO" --json body -q '.body')
printf '%s' "$body" | grep -q '### Приоритет' || { echo "не из формы — пропуск"; exit 0; }

# Значение секции формы (первая непустая строка после "### Заголовок")
sect(){ printf '%s\n' "$body" | awk -v h="### $1" 'f && /^### /{exit} f && NF{print; exit} $0==h{f=1}'; }

prio=$(sect "Приоритет"); cat=$(sect "Категория"); dl=$(sect "Дедлайн (ГГГГ-ММ-ДД ЧЧ:ММ)")

labels=""
case "$prio" in Критично|Высокий|Средний|Низкий) labels="$labels,$prio";; esac
case "$cat"  in Работа|Личное|Учёба|Здоровье|Быт) labels="$labels,$cat";;  esac
labels="${labels#,}"
[ -n "$labels" ] && gh issue edit "$NUM" -R "$REPO" --add-label "$labels" >/dev/null && echo "метки: $labels"

gh issue edit "$NUM" -R "$REPO" --add-assignee del0x3 >/dev/null 2>&1 || true
today=$(TZ="$TZL" date +%F)
gh issue edit "$NUM" -R "$REPO" --milestone "$today" >/dev/null 2>&1 || true

if printf '%s' "$dl" | grep -qP '^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}'; then
  gh issue edit "$NUM" -R "$REPO" --body "$body

Дедлайн: ${dl/T/ }" >/dev/null && echo "дедлайн: $dl"
fi
echo "форма #$NUM обработана"
