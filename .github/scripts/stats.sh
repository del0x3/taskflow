#!/usr/bin/env bash
# Считает аналитику из истории issue -> docs/data.json (для сайта на Pages).
set -uo pipefail
REPO="${REPO:-del0x3/taskflow}"
TZL="${TZL:-Europe/Kiev}"
OWNER="${OWNER:-del0x3}"
mkdir -p docs
today=$(TZ="$TZL" date +%F)
now_e=$(date +%s)

ISS=$(mktemp)
gh issue list -R "$REPO" --state all --limit 500 \
  --json number,title,state,createdAt,closedAt,labels,body,author > "$ISS"

# ---------- KPI ----------
# учитываем только задачи от владельца и бота (публичный репо: чужие issue игнорируем)
jqf='[.[] | select(.author.login=="del0x3" or .author.login=="github-actions[bot]") | select([.labels[].name] | (index("Доска") or index("Привычка")) | not)]'
open=$(jq "$jqf | map(select(.state==\"OPEN\")) | length" "$ISS")
todayN=$(jq "$jqf | map(select(.state==\"OPEN\") | select([.labels[].name]|index(\"Сегодня\"))) | length" "$ISS")
overdueN=$(jq "$jqf | map(select(.state==\"OPEN\") | select([.labels[].name]|index(\"Просрочено\"))) | length" "$ISS")
closedAll=$(jq "$jqf | map(select(.state==\"CLOSED\")) | length" "$ISS")
closedToday=$(jq --arg d "$today" "$jqf | map(select(.closedAt!=null and (.closedAt[0:10]==\$d))) | length" "$ISS")
wfrom=$(TZ="$TZL" date -d "$today -6 days" +%F)
mfrom=$(TZ="$TZL" date -d "$today -29 days" +%F)
closedWeek=$(jq --arg d "$wfrom" "$jqf | map(select(.closedAt!=null and (.closedAt[0:10]>=\$d))) | length" "$ISS")
closedMonth=$(jq --arg d "$mfrom" "$jqf | map(select(.closedAt!=null and (.closedAt[0:10]>=\$d))) | length" "$ISS")
denom=$(( open + closedAll )); rate=0; [ "$denom" -gt 0 ] && rate=$(( closedAll * 100 / denom ))

# среднее затраченное (tf-spent в теле закрытых)
spent_vals=$(jq -r "$jqf | .[] | select(.state==\"CLOSED\") | .body" "$ISS" | grep -oP 'tf-spent:\s*\K[0-9]+' || true)
sp_sum=0; sp_cnt=0
for v in $spent_vals; do sp_sum=$((sp_sum+v)); sp_cnt=$((sp_cnt+1)); done
avgSpent=0; [ "$sp_cnt" -gt 0 ] && avgSpent=$(( sp_sum / sp_cnt ))

# ---------- Недельные тренды (8 недель) ----------
declare -A CRE CLO
while IFS=$'\t' read -r cre clo; do
  cwk=$(date -d "${cre:0:10}" +%G-W%V 2>/dev/null || echo "")
  [ -n "$cwk" ] && CRE[$cwk]=$(( ${CRE[$cwk]:-0} + 1 ))
  if [ -n "$clo" ] && [ "$clo" != "null" ] && [ "$clo" != "" ]; then
    xwk=$(date -d "${clo:0:10}" +%G-W%V 2>/dev/null || echo "")
    [ -n "$xwk" ] && CLO[$xwk]=$(( ${CLO[$xwk]:-0} + 1 ))
  fi
done < <(jq -r "$jqf | .[] | [.createdAt, (.closedAt // \"\")] | @tsv" "$ISS")
weeks="["
for i in 7 6 5 4 3 2 1 0; do
  wl=$(date -d "$today -$((i*7)) days" +%G-W%V 2>/dev/null)
  weeks="$weeks{\"week\":\"$wl\",\"created\":${CRE[$wl]:-0},\"closed\":${CLO[$wl]:-0}},"
done
weeks="${weeks%,}]"

# ---------- Категории / Статусы (открытые) ----------
cats=$(jq -c "$jqf | map(select(.state==\"OPEN\")) | [.[].labels[].name] | map(select(. as \$x | [\"Работа\",\"Личное\",\"Учёба\",\"Здоровье\",\"Быт\"]|index(\$x))) | group_by(.) | map({key:.[0], value:length}) | from_entries" "$ISS")
stats=$(jq -c "$jqf | map(select(.state==\"OPEN\")) | [.[].labels[].name] | map(select(. as \$x | [\"Сегодня\",\"В работе\",\"Заблокировано\",\"Ожидание\",\"Бэклог\"]|index(\$x))) | group_by(.) | map({key:.[0], value:length}) | from_entries" "$ISS")

# ---------- Время по категориям (закрытые с tf-spent) ----------
spentcat=$(jq -c "$jqf | map(select(.state==\"CLOSED\")) | map({c:([.labels[].name]|map(select([\"Работа\",\"Личное\",\"Учёба\",\"Здоровье\",\"Быт\"]|index(.)))|.[0]//\"Прочее\"), m:((.body|capture(\"tf-spent: (?<n>[0-9]+)\").n)//\"0\"|tonumber)}) | group_by(.c) | map({key:.[0].c, value:(map(.m)|add)}) | from_entries" "$ISS" 2>/dev/null || echo '{}')

# ---------- Привычки (стрики) ----------
habits="[]"
if [ -f habits.json ]; then
  habits="["
  hc=$(jq '.habits | length' habits.json)
  j=0
  while [ "$j" -lt "$hc" ]; do
    hname=$(jq -r ".habits[$j].name" habits.json)
    hemoji=$(jq -r ".habits[$j].emoji // \"🔁\"" habits.json)
    htitle="$hemoji $hname"
    # даты закрытий этой привычки
    dates=$(jq -r --arg t "$htitle" '.[] | select(.title==$t) | select(.state=="CLOSED") | select([.labels[].name]|index("Пропущено")|not) | (.createdAt[0:10])' "$ISS" | sort -u)
    doneToday=false; printf '%s\n' "$dates" | grep -q "^$today$" && doneToday=true
    # стрик: считаем подряд дни назад (сегодня если closed, иначе со вчера)
    streak=0; d="$today"
    [ "$doneToday" = false ] && d=$(date -d "$today -1 day" +%F)
    while printf '%s\n' "$dates" | grep -q "^$d$"; do streak=$((streak+1)); d=$(date -d "$d -1 day" +%F); done
    last7="["
    for k in 6 5 4 3 2 1 0; do
      dd=$(date -d "$today -$k days" +%F)
      v=0; printf '%s\n' "$dates" | grep -q "^$dd$" && v=1
      last7="$last7$v,"
    done; last7="${last7%,}]"
    habits="$habits{\"name\":$(jq -Rn --arg s "$htitle" '$s'),\"streak\":$streak,\"doneToday\":$doneToday,\"last7\":$last7},"
    j=$((j+1))
  done
  habits="${habits%,}]"
  [ "$habits" = "]" ] && habits="[]"
fi

# ---------- Просрочки с причинами (объективные/субъективные) ----------
overdue="["; oc_obj=0; oc_subj=0; oc_un=0
while read -r num; do
  [ -z "$num" ] && continue
  ob=$(jq -r --argjson n "$num" '.[] | select(.number==$n) | .body' "$ISS")
  ot=$(jq -r --argjson n "$num" '.[] | select(.number==$n) | .title' "$ISS")
  oc=$(jq -r --argjson n "$num" '.[] | select(.number==$n) | [.labels[].name] | map(select(["Работа","Личное","Учёба","Здоровье","Быт"]|index(.)))|.[0]//"—"' "$ISS")
  dl=$(printf '%s' "$ob" | grep -oP 'Дедлайн:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' | head -1 || true)
  late=0; [ -n "$dl" ] && { de=$(TZ="$TZL" date -d "${dl/T/ }" +%s 2>/dev/null||echo "$now_e"); late=$(( (now_e - de)/3600 )); }
  reason=$(gh api "repos/$REPO/issues/$num/comments" -q '[.[] | select(.user.login=="del0x3") | select((.body|startswith("/"))|not)] | last | .body // ""' 2>/dev/null | tr '\n' ' ' || echo "")
  rtype="не указано"
  case "$reason" in
    *объектив*|*Объектив*|*"был занят"*|*важн*|*блокер*|*блок*) rtype="объективная";;
    *лень*|*Лень*|*прокраст*|*Прокраст*|*забил*|*субъектив*) rtype="субъективная";;
  esac
  case "$rtype" in объективная) oc_obj=$((oc_obj+1));; субъективная) oc_subj=$((oc_subj+1));; *) oc_un=$((oc_un+1));; esac
  overdue="$overdue$(jq -nc --argjson n "$num" --arg t "$ot" --arg c "$oc" --argjson l "$late" --arg r "$reason" --arg rt "$rtype" '{num:$n,title:$t,category:$c,lateHours:$l,reason:$r,type:$rt}'),"
done < <(jq -r "$jqf | .[] | select(.state==\"OPEN\") | select([.labels[].name]|index(\"Просрочено\")) | .number" "$ISS")
overdue="${overdue%,}]"; [ "$overdue" = "]" ] && overdue="[]"
reasons="{\"объективные\":$oc_obj,\"субъективные\":$oc_subj,\"неуказано\":$oc_un}"

# ---------- Сборка ----------
[ -z "$cats" ] && cats='{}'
[ -z "$stats" ] && stats='{}'
[ -z "$spentcat" ] && spentcat='{}'
[ -z "$reasons" ] && reasons='{}'
[ -z "$weeks" ] && weeks='[]'
[ -z "$habits" ] && habits='[]'
[ -z "$overdue" ] && overdue='[]'
jq -n \
  --arg gen "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson open "$open" --argjson today "$todayN" --argjson overdue "$overdueN" \
  --argjson closedToday "$closedToday" --argjson closedWeek "$closedWeek" --argjson closedMonth "$closedMonth" \
  --argjson rate "$rate" --argjson avgSpent "$avgSpent" \
  --argjson weeks "$weeks" --argjson cats "$cats" --argjson statuses "$stats" \
  --argjson spentcat "$spentcat" --argjson habits "$habits" --argjson overdueList "$overdue" \
  --argjson reasons "$reasons" \
  '{generatedAt:$gen, kpi:{open:$open,today:$today,overdue:$overdue,closedToday:$closedToday,closedWeek:$closedWeek,closedMonth:$closedMonth,completionRate:$rate,avgSpentMin:$avgSpent}, weeks:$weeks, categories:$cats, statuses:$statuses, spentByCategory:$spentcat, habits:$habits, overdueReasons:$reasons, overdueList:$overdueList}' \
  > docs/data.json
rm -f "$ISS"
echo "docs/data.json готов: open=$open closed=$closedAll rate=${rate}% avgSpent=${avgSpent}м"
