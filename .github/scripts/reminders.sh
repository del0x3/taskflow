#!/usr/bin/env bash
# Эфемерные пуш-напоминания о дедлайнах.
# Пуш = коммент с @del0x3 (мгновенно уведомляет). Через ~5 мин коммент удаляется.
set -euo pipefail

REPO="${REPO:-del0x3/taskflow}"
TZL="${TZL:-Europe/Kiev}"
MENTION="@del0x3"
MARK="<!-- tf-reminder -->"
now_epoch=$(date +%s)

# --- 1. Очистка: удалить свои reminder-комменты старше 5 минут ---
gh issue list -R "$REPO" --state open --json number -q '.[].number' | while read -r num; do
  [ -z "$num" ] && continue
  gh api "repos/$REPO/issues/$num/comments" --paginate \
    -q ".[] | select(.user.login==\"github-actions[bot]\") | select(.body | contains(\"$MARK\")) | \"\(.id)\t\(.created_at)\"" \
  | while IFS=$'\t' read -r cid created; do
      [ -z "$cid" ] && continue
      c_epoch=$(date -d "$created" +%s)
      if [ $(( now_epoch - c_epoch )) -ge 300 ]; then
        gh api -X DELETE "repos/$REPO/issues/comments/$cid" >/dev/null && echo "удалён коммент $cid (issue #$num)"
      fi
    done
done

# --- 2. Рассылка напоминаний ---
gh issue list -R "$REPO" --state open --limit 200 --json number,body,labels \
  -q '.[] | [.number, ([.labels[].name] | join(",")), (.body|@base64)] | @tsv' \
| while IFS=$'\t' read -r num labels body_b64; do
    [ -z "$num" ] && continue
    body=$(printf '%s' "$body_b64" | base64 -d)
    dl=$(printf '%s' "$body" | grep -oP 'Дедлайн:\s*\K[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' | head -1 || true)
    [ -z "$dl" ] && continue
    dl_norm=${dl/T/ }
    dl_epoch=$(TZ="$TZL" date -d "$dl_norm" +%s 2>/dev/null || echo "")
    [ -z "$dl_epoch" ] && continue
    diff_min=$(( (dl_epoch - now_epoch) / 60 ))
    has_pre=$(printf ',%s,' "$labels" | grep -c ',Уведомление-до,' || true)
    has_due=$(printf ',%s,' "$labels" | grep -c ',Уведомление-в-момент,' || true)

    # Сброс флагов, если дедлайн перенесён в будущее (>25 мин), а флаги остались
    if [ "$diff_min" -gt 25 ]; then
      if [ "$has_pre" -eq 1 ]; then gh issue edit "$num" -R "$REPO" --remove-label Уведомление-до >/dev/null 2>&1 || true; has_pre=0; echo "сброс флага pre #$num (перенос)"; fi
      if [ "$has_due" -eq 1 ]; then gh issue edit "$num" -R "$REPO" --remove-label Уведомление-в-момент >/dev/null 2>&1 || true; has_due=0; echo "сброс флага due #$num (перенос)"; fi
    fi

    # Предупреждение до дедлайна: окно (0; 20] мин (с запасом на задержку cron)
    if [ "$diff_min" -gt 0 ] && [ "$diff_min" -le 20 ] && [ "$has_pre" -eq 0 ]; then
      gh issue comment "$num" -R "$REPO" --body "$MARK
$MENTION ⏰ Через ${diff_min} мин дедлайн: $dl_norm — #$num"
      gh issue edit "$num" -R "$REPO" --add-label Уведомление-до
      echo "pre-напоминание #$num"
    fi

    # В момент дедлайна: окно [-90; 0] мин (догон, если cron задержался/пропустил)
    if [ "$diff_min" -le 0 ] && [ "$diff_min" -ge -90 ] && [ "$has_due" -eq 0 ]; then
      late=$(( -diff_min ))
      msg="Дедлайн наступил"
      [ "$late" -ge 6 ] && msg="Дедлайн был ${late} мин назад"
      gh issue comment "$num" -R "$REPO" --body "$MARK
$MENTION ⏰ $msg: $dl_norm — #$num"
      gh issue edit "$num" -R "$REPO" --add-label Уведомление-в-момент
      echo "due-напоминание #$num"
    fi
  done
