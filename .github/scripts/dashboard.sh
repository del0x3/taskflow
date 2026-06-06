#!/usr/bin/env bash
# Генерирует плотный дашборд всех открытых задач -> DASHBOARD.md + закреплённый issue «Доска».
set -euo pipefail

REPO="${REPO:-del0x3/taskflow}"
TZL="${TZL:-Europe/Kiev}"
OUT="DASHBOARD.md"

pr_rank(){ case "$1" in *Критично*)echo 1;; *Высокий*)echo 2;; *Средний*)echo 3;; *Низкий*)echo 4;; *)echo 9;; esac; }
pr_name(){ case "$1" in *Критично*)echo "🔴 Критично";; *Высокий*)echo "🟠 Высокий";; *Средний*)echo "🟡 Средний";; *Низкий*)echo "🟢 Низкий";; *)echo "—";; esac; }
st_name(){ case "$1" in *"В работе"*)echo "🔄 В работе";; *Заблокировано*)echo "⛔ Блок";; *Ожидание*)echo "⏳ Ожидание";; *Бэклог*)echo "📋 Бэклог";; *Сегодня*)echo "🎯 Сегодня";; *)echo "·";; esac; }
cat_name(){ local r=""; for c in Работа Личное Учёба Здоровье Быт; do case "$1" in *"$c"*) r="$r $c";; esac; done; echo "${r# }"; }

TMP=$(mktemp); ROWS=$(mktemp)
gh issue list -R "$REPO" --state open --limit 300 \
  --json number,title,labels,milestone,body \
  -q '.[] | select([.labels[].name] | index("Доска") | not) | [.number, .title, ([.labels[].name]|join("|")), (.milestone.title // "—"), (.body|@base64)] | @tsv' > "$TMP"

today_n=0; over_n=0; now_e=$(date +%s)
while IFS=$'\t' read -r num title labels ms b64; do
  [ -z "$num" ] && continue
  body=$(printf '%s' "$b64" | base64 -d)
  dl=$(printf '%s' "$body" | grep -oP 'Дедлайн:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' | head -1 || true)
  when="${dl:-$ms}"
  flag=""
  if [ -n "$dl" ]; then
    de=$(TZ="$TZL" date -d "${dl/T/ }" +%s 2>/dev/null || echo "")
    if [ -n "$de" ] && [ "$de" -lt "$now_e" ]; then flag=" ⚠️"; over_n=$((over_n+1)); fi
  fi
  proj=$(printf '%s' "$body" | grep -oP 'github\.com/\K[^/ )]+/[^/ )]+' | head -1 || true)
  case "$labels" in *Сегодня*) today_n=$((today_n+1));; esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(pr_rank "$labels")" "$num" "$title" "$(pr_name "$labels")" "$(st_name "$labels")" "${when}${flag}" "${proj:-—}" "$(cat_name "$labels")" >> "$ROWS"
done < "$TMP"

total=$(grep -c . "$ROWS" || echo 0)
{
  echo "# 📋 Доска задач"
  echo
  echo "**Открыто:** $total · **на сегодня:** $today_n · **просрочено:** $over_n"
  echo
  echo "| # | Задача | Приоритет | Статус | Срок | Проект | Категория |"
  echo "|--:|--------|-----------|--------|------|--------|-----------|"
  sort -t$'\t' -k1,1n -k6,6 "$ROWS" | while IFS=$'\t' read -r rank num title prio st when proj cat; do
    echo "| #$num | $title | $prio | $st | $when | $proj | ${cat:-—} |"
  done
  last=$(ls -1 digests/daily/*.md 2>/dev/null | tail -1 || true)
  if [ -n "$last" ]; then echo; echo "---"; echo; echo "### 📊 Последний дайджест"; echo; cat "$last"; fi
} > "$OUT"

brd=$(gh issue list -R "$REPO" --label "Доска" --state open --json number -q '.[0].number' || true)
if [ -z "$brd" ]; then
  gh issue create -R "$REPO" --title "📋 Доска задач" --body "$(cat "$OUT")" --label "Доска" >/dev/null
  echo "создан issue «Доска задач»"
else
  gh issue edit "$brd" -R "$REPO" --title "📋 Доска задач" --body "$(cat "$OUT")" >/dev/null
  echo "обновлён issue «Доска задач» (#$brd)"
fi
rm -f "$TMP" "$ROWS"
