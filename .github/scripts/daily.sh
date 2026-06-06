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
gh issue list -R "$REPO" --label today --state open --json number -q '.[].number' | while read -r n; do
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

echo "::group::4. Дневной дайджест за $yest"
mkdir -p digests/daily
closed=$(gh issue list -R "$REPO" --state closed --search "closed:$yest" --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
opened=$(gh issue list -R "$REPO" --state all --search "created:$yest" --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
still=$(gh issue list -R "$REPO" --label today --state open --json number,title -q '.[] | "- #\(.number) \(.title)"' || true)
cat > "digests/daily/$yest.md" <<EOF
# Дайджест за $yest

## Закрыто
${closed:-—}

## Создано
${opened:-—}

## Ещё в работе (today)
${still:-—}
EOF
echo "записан digests/daily/$yest.md"

# Постоянный issue «Текущий дайджест» (один, перезаписывается -> пуш)
board=$(gh issue list -R "$REPO" --label digest-board --state open --json number -q '.[0].number' || true)
dbody=$(cat "digests/daily/$yest.md")
if [ -z "$board" ]; then
  gh issue create -R "$REPO" --title "📊 Текущий дайджест" --body "$dbody" --label digest-board >/dev/null
  echo "создан issue «Текущий дайджест»"
else
  gh issue edit "$board" -R "$REPO" --body "$dbody" >/dev/null
  echo "обновлён issue «Текущий дайджест» (#$board)"
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
