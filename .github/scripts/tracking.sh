#!/usr/bin/env bash
# Авто-трекинг времени: метка «В работе» -> старт; закрытие -> затрачено.
set -euo pipefail
REPO="${REPO:-del0x3/taskflow}"
NUM="${NUM:?нужен NUM}"
ACTION="${ACTION:-}"
LABEL="${LABEL:-}"

body=$(gh issue view "$NUM" -R "$REPO" --json body -q '.body')

case "$ACTION" in
  labeled)
    [ "$LABEL" = "В работе" ] || { echo "не та метка ($LABEL) — пропуск"; exit 0; }
    if printf '%s' "$body" | grep -q 'tf-start:'; then echo "#$NUM уже трекается"; exit 0; fi
    start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh issue edit "$NUM" -R "$REPO" --body "$body

<!-- tf-start: $start -->" >/dev/null
    echo "#$NUM старт зафиксирован: $start"
    ;;
  closed)
    start=$(printf '%s' "$body" | grep -oP 'tf-start:\s*\K\S+' | head -1 || true)
    [ -z "$start" ] && { echo "#$NUM старт не зафиксирован — пропуск"; exit 0; }
    if printf '%s' "$body" | grep -q 'tf-spent:'; then echo "#$NUM уже посчитано"; exit 0; fi
    se=$(date -d "$start" +%s 2>/dev/null || echo "")
    [ -z "$se" ] && { echo "битый старт"; exit 0; }
    mins=$(( ( $(date +%s) - se ) / 60 )); [ "$mins" -lt 0 ] && mins=0
    h=$(( mins / 60 )); m=$(( mins % 60 ))
    gh issue edit "$NUM" -R "$REPO" --body "$body

<!-- tf-spent: $mins -->
⏱ Затрачено: ${h}ч ${m}м" >/dev/null
    echo "#$NUM затрачено: ${h}ч ${m}м ($mins мин)"
    ;;
  reopened)
    # снять подсчёт, перезапустить таймер
    nb=$(printf '%s' "$body" | grep -vE 'tf-spent:|⏱ Затрачено:|tf-start:' || true)
    start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gh issue edit "$NUM" -R "$REPO" --body "$nb

<!-- tf-start: $start -->" >/dev/null
    echo "#$NUM переоткрыт — таймер сброшен"
    ;;
  *) echo "действие $ACTION не трекается" ;;
esac
