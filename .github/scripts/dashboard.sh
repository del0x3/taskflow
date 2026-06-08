#!/usr/bin/env bash
# Генерирует дашборд: секции Сегодня/Запланировано + привычки -> DASHBOARD.md и закреплённый issue «Доска».
set -uo pipefail

REPO="${REPO:-del0x3/taskflow}"
TZL="${TZL:-Europe/Kiev}"
OWNER="${OWNER:-del0x3}"
SITE="https://del0x3.github.io/taskflow/"
OUT="DASHBOARD.md"
now_e=$(date +%s)
today=$(TZ="$TZL" date +%F)

pr_rank(){ case "$1" in *Критично*)echo 1;; *Высокий*)echo 2;; *Средний*)echo 3;; *Низкий*)echo 4;; *)echo 9;; esac; }
pr_name(){ case "$1" in *Критично*)echo "🔴 Критично";; *Высокий*)echo "🟠 Высокий";; *Средний*)echo "🟡 Средний";; *Низкий*)echo "🟢 Низкий";; *)echo "—";; esac; }
cat_name(){ local r=""; for c in Работа Личное Учёба Здоровье Быт; do case "$1" in *"$c"*) r="$r $c";; esac; done; echo "${r# }"; }

declare -A BST
while IFS=$'\t' read -r num st; do [ -n "$num" ] && BST[$num]="$st"; done < <(
  gh project item-list 2 --owner "$OWNER" --format json \
    -q '.items[] | select(.content.number) | [.content.number, (.status // "")] | @tsv' 2>/dev/null || true)
st_name(){ local b="${BST[$1]:-}"
  case "$b" in "In Progress") echo "🔄 В работе"; return;; "Done") echo "✅ Готово"; return;; esac
  case "$2" in *"В работе"*)echo "🔄 В работе";; *Заблокировано*)echo "⛔ Блок";; *Ожидание*)echo "⏳ Ожидание";; *Бэклог*)echo "📋 Бэклог";; *Сегодня*)echo "🎯 Сегодня";; *)echo "·";; esac; }

TMP=$(mktemp); ROWS=$(mktemp)
gh issue list -R "$REPO" --state open --limit 300 \
  --json number,title,labels,milestone,body,author \
  -q '.[] | select(.author.login=="del0x3" or .author.login=="github-actions[bot]") | select([.labels[].name] | (index("Доска") or index("Привычка")) | not) | [.number, .title, ([.labels[].name]|join("|")), (.milestone.title // "—"), (.body|@base64)] | @tsv' > "$TMP"

today_n=0; over_n=0; hot_n=0
while IFS=$'\t' read -r num title labels ms b64; do
  [ -z "$num" ] && continue
  body=$(printf '%s' "$b64" | base64 -d)
  dl=$(printf '%s' "$body" | grep -oP 'Дедлайн:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' | head -1 || true)
  when="${dl:-$ms}"; sortkey="$when"
  if [ -n "$dl" ]; then
    de=$(TZ="$TZL" date -d "${dl/T/ }" +%s 2>/dev/null || echo "")
    if [ -n "$de" ]; then
      if [ "$de" -lt "$now_e" ]; then when="$when ⚠️"; over_n=$((over_n+1));
      elif [ $(( de - now_e )) -le 7200 ]; then when="$when 🔥"; hot_n=$((hot_n+1)); fi
    fi
  fi
  mark=""; case "$labels" in *Залежалось*) mark=" 🐌";; esac
  proj=$(printf '%s' "$body" | grep -oP 'github\.com/\K[^/ )]+/[^/ )]+' | head -1 || true)
  sect="plan"; case "$labels" in *Сегодня*) sect="today"; today_n=$((today_n+1));; esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$sect" "$(pr_rank "$labels")" "$sortkey" "$num" "${title}${mark}" "$(pr_name "$labels")" "$(st_name "$num" "$labels")" "$when" "${proj:-—}" "$(cat_name "$labels")" >> "$ROWS"
done < "$TMP"

emit_table(){ # $1=фильтр-секция $2=ключ-сортировки(rank|date)
  echo "| # | Задача | Приоритет | Статус | Срок | Проект | Категория |"
  echo "|--:|--------|-----------|--------|------|--------|-----------|"
  if [ "$2" = "rank" ]; then srt="-k2,2n -k3,3"; else srt="-k3,3 -k2,2n"; fi
  grep "^$1	" "$ROWS" | sort -t$'\t' $srt | while IFS=$'\t' read -r s rank sk num title prio st when proj cat; do
    echo "| #$num | $title | $prio | $st | $when | $proj | ${cat:-—} |"
  done
}

# привычки на сегодня
hab=$(gh issue list -R "$REPO" --label Привычка --state all --search "created:$today" --json title,state \
  -q '[.[] | (if .state=="CLOSED" then "✅ " else "⬜ " end) + .title] | join(" · ")' 2>/dev/null || true)
hdone=$(gh issue list -R "$REPO" --label Привычка --state closed --search "created:$today" --json number -q 'length' 2>/dev/null || echo 0)
htot=$(gh issue list -R "$REPO" --label Привычка --state all --search "created:$today" --json number -q 'length' 2>/dev/null || echo 0)

total=$(grep -c . "$ROWS" || echo 0)
closed_today=$(gh issue list -R "$REPO" --state closed --search "closed:>=$today" --json number,title -q '.[] | "- #\(.number) \(.title)"' 2>/dev/null || true)
{
  echo "# 📋 Доска задач"
  echo
  echo "📊 **[Аналитика и диаграммы]($SITE)** · обновлено $(TZ="$TZL" date '+%Y-%m-%d %H:%M')"
  echo
  echo "🧘 _Начать работу — напиши_ \`/старт\` _в комментах ниже._"
  echo
  echo "**Открыто:** $total · **сегодня:** $today_n · **🔥 горит:** $hot_n · **⚠️ просрочено:** $over_n"
  echo
  echo "## 🎯 Сегодня"
  emit_table today rank
  echo
  echo "## 📅 Запланировано (не на сегодня)"
  emit_table plan date
  echo
  echo "## 🔁 Привычки сегодня ($hdone/$htot)"
  echo "${hab:-—}"
  echo
  echo "## ✅ Закрыто сегодня"
  echo "${closed_today:-—}"
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
