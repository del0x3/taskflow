#!/usr/bin/env bash
# Утренний прогон: milestone, роллновер, повторяющиеся, дайджесты, сворачивания.
# Файловые изменения (digests/) коммитит workflow после скрипта.
set -euo pipefail

REPO="${REPO:-del0x3/taskflow}"
TZL="${TZL:-Europe/Kiev}"

today=$(TZ="$TZL" date +%F)
yest=$(TZ="$TZL" date -d 'yesterday' +%F)
dow=$(TZ="$TZL" date +%u)    # 1=Пн .. 7=Вс
dom=$(TZ="$TZL" date +%d)
mon=$(TZ="$TZL" date +%m)

echo "::group::1. Milestone $today"
ms=$(gh api "repos/$REPO/milestones?state=open" -q ".[] | select(.title==\"$today\") | .number" | head -1 || true)
if [ -z "$ms" ]; then
  gh api -X POST "repos/$REPO/milestones" -f title="$today" -f state=open -f description="Задачи на $today" >/dev/null
  echo "создан milestone $today"
else
  echo "milestone уже есть (#$ms)"
fi
echo "::endgroup::"

echo "::group::2. Роллновер незакрытых today"
gh issue list -R "$REPO" --label Сегодня --state open --json number -q '.[].number' | while read -r n; do
  [ -z "$n" ] && continue
  gh issue edit "$n" -R "$REPO" --milestone "$today" >/dev/null 2>&1 || true
  echo "перенесён #$n -> $today"
done
echo "::endgroup::"

echo "::group::3. Повторяющиеся задачи"
if [ -f recurring.json ]; then
  cnt=$(jq '.tasks | length' recurring.json)
  i=0
  while [ "$i" -lt "$cnt" ]; do
    title=$(jq -r ".tasks[$i].title" recurring.json)
    labels=$(jq -r ".tasks[$i].labels | join(\",\")" recurring.json)
    gh issue create -R "$REPO" --title "$title" \
      --body "Повторяющаяся задача (создана автоматически на $today)." \
      --label "$labels" --milestone "$today" >/dev/null
    echo "создана повторяющаяся: $title"
    i=$((i+1))
  done
  [ "$cnt" -eq 0 ] && echo "список пуст"
fi
echo "::endgroup::"

echo "::group::3.5. Просрочка"
OD=$(mktemp)
now_e=$(date +%s)
gh issue list -R "$REPO" --state open --limit 200 --json number,title,body,labels \
  -q '.[] | [.number, .title, ([.labels[].name]|join(",")), (.body|@base64)] | @tsv' \
| while IFS=$'\t' read -r n t labs b64; do
    bd=$(printf '%s' "$b64" | base64 -d)
    dl=$(printf '%s' "$bd" | grep -oP 'Дедлайн:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' | head -1 || true)
    [ -z "$dl" ] && continue
    dl_e=$(TZ="$TZL" date -d "${dl/T/ }" +%s 2>/dev/null || echo "")
    [ -z "$dl_e" ] && continue
    if [ "$dl_e" -lt "$now_e" ]; then
      echo "- #$n $t (дедлайн $dl)" >> "$OD"
      case ",$labs," in *,Просрочено,*) : ;; *) gh issue edit "$n" -R "$REPO" --add-label Просрочено >/dev/null 2>&1 && echo "помечен Просрочено #$n" ;; esac
    fi
  done
overdue_list=$(cat "$OD"); rm -f "$OD"
echo "::endgroup::"

echo "::group::4. Дневной дайджест за $yest"
mkdir -p digests/daily
closed=$(gh issue list -R "$REPO" --state closed --search "closed:$yest" --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
opened=$(gh issue list -R "$REPO" --state all --search "created:$yest" --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
still=$(gh issue list -R "$REPO" --label Сегодня --state open --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
cat > "digests/daily/$yest.md" <<EOF
# Дайджест за $yest

## Закрыто
${closed:-—}

## Создано
${opened:-—}

## Ещё в работе (today)
${still:-—}

## ⚠️ Просрочено
${overdue_list:-—}
EOF
echo "записан digests/daily/$yest.md"

# Постоянный issue «Текущий дайджест» (один, перезаписывается -> пуш)
board=$(gh issue list -R "$REPO" --label Дайджест-доска --state open --json number -q '.[0].number' || true)
dbody=$(cat "digests/daily/$yest.md")
if [ -z "$board" ]; then
  gh issue create -R "$REPO" --title "📊 Текущий дайджест" --body "$dbody" --label Дайджест-доска >/dev/null
  echo "создан issue «Текущий дайджест»"
else
  gh issue edit "$board" -R "$REPO" --body "$dbody" >/dev/null
  echo "обновлён issue «Текущий дайджест» (#$board)"
fi
echo "::endgroup::"

echo "::group::4.5. Еженедельное ревью (воскресенье)"
if [ "$dow" = "7" ]; then
  wkr=$(TZ="$TZL" date +%G-W%V)
  wfrom=$(TZ="$TZL" date -d '6 days ago' +%F)
  mkdir -p digests/reviews
  rev_done=$(gh issue list -R "$REPO" --state closed --search "closed:>=$wfrom" --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
  rev_open=$(gh issue list -R "$REPO" --state open --json number,title,labels -q '.[] | select([.labels[].name] | index("Дайджест-доска") | not) | "- #\(.number) \(.title)"' || true)
  cat > "digests/reviews/$wkr.md" <<EOF
# 🗓 Ревью недели $wkr

## Сделано за неделю
${rev_done:-—}

## Ещё открыто (план на следующую неделю)
${rev_open:-—}
EOF
  echo "записан digests/reviews/$wkr.md"
  brd=$(gh issue list -R "$REPO" --label Дайджест-доска --state open --json number -q '.[0].number' || true)
  if [ -n "$brd" ]; then
    gh issue edit "$brd" -R "$REPO" --body "$(cat "digests/reviews/$wkr.md")" >/dev/null
    echo "ревью отправлено в «Текущий дайджест» (#$brd) — придёт пуш"
  fi
else
  echo "не воскресенье — пропуск"
fi
echo "::endgroup::"

# Хелпер сворачивания: $1=заголовок $2=выходной файл $3=папка-источник
rollup() {
  local title="$1" out="$2" src="$3"
  mkdir -p "$(dirname "$out")"
  {
    echo "# $title"
    for f in "$src"/*.md; do
      [ -e "$f" ] || continue
      echo
      echo "## $(basename "$f" .md)"
      cat "$f"
    done
  } > "$out"
  rm -f "$src"/*.md
  echo "свёрнут -> $out"
}

echo "::group::5. Сворачивания"
# Недельный: в понедельник сворачиваем дневные прошедшей недели
if [ "$dow" = "1" ]; then
  wk=$(TZ="$TZL" date -d 'yesterday' +%G-W%V)
  rollup "Недельный дайджест $wk" "digests/weekly/$wk.md" "digests/daily"
fi
# Месячный: 1-го числа сворачиваем недельные прошлого месяца
if [ "$dom" = "01" ]; then
  pm=$(TZ="$TZL" date -d 'yesterday' +%Y-%m)
  rollup "Месячный дайджест $pm" "digests/monthly/$pm.md" "digests/weekly"
fi
# Квартальный: 1 янв/апр/июл/окт сворачиваем месячные прошлого квартала
if [ "$dom" = "01" ] && printf '%s' "$mon" | grep -qE '^(01|04|07|10)$'; then
  py=$(TZ="$TZL" date -d 'yesterday' +%Y)
  qm=$(TZ="$TZL" date -d 'yesterday' +%m)
  case "$qm" in 10|11|12) q=Q4;; 07|08|09) q=Q3;; 04|05|06) q=Q2;; *) q=Q1;; esac
  rollup "Квартальный дайджест $py-$q" "digests/quarterly/$py-$q.md" "digests/monthly"
fi
# Годовой: 1 января сворачиваем квартальные прошлого года
if [ "$dom" = "01" ] && [ "$mon" = "01" ]; then
  py=$(TZ="$TZL" date -d 'yesterday' +%Y)
  rollup "Годовой дайджест $py" "digests/yearly/$py.md" "digests/quarterly"
fi
echo "::endgroup::"

echo "Готово."
