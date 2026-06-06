#!/usr/bin/env bash
# Тесты логики дат для сворачивания дайджестов (без обращения к сети).
set -uo pipefail
fail=0
ok(){ if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 — ждали '$3', получили '$2'"; fail=1; fi; }

# Маппинг месяц -> квартал (как в daily.sh)
quarter(){ case "$1" in 10|11|12) echo Q4;; 07|08|09) echo Q3;; 04|05|06) echo Q2;; *) echo Q1;; esac; }
ok "квартал янв" "$(quarter 01)" Q1
ok "квартал мар" "$(quarter 03)" Q1
ok "квартал апр" "$(quarter 04)" Q2
ok "квартал июн" "$(quarter 06)" Q2
ok "квартал июл" "$(quarter 07)" Q3
ok "квартал сен" "$(quarter 09)" Q3
ok "квартал окт" "$(quarter 10)" Q4
ok "квартал дек" "$(quarter 12)" Q4

# ISO-неделя на стыке года (как date +%G-W%V)
ok "ISO 2021-01-01 -> 2020-W53" "$(TZ=Europe/Kiev date -d 2021-01-01 +%G-W%V)" 2020-W53
ok "ISO 2021-01-04 -> 2021-W01" "$(TZ=Europe/Kiev date -d 2021-01-04 +%G-W%V)" 2021-W01

# Предыдущий месяц/год на 1-е число
ok "пред. месяц 2026-01-01" "$(TZ=Europe/Kiev date -d '2026-01-01 - 1 day' +%Y-%m)" 2025-12
ok "пред. год 2026-01-01"   "$(TZ=Europe/Kiev date -d '2026-01-01 - 1 day' +%Y)" 2025

[ "$fail" -eq 0 ] && echo "=== ВСЕ ТЕСТЫ ПРОШЛИ ===" || echo "=== ЕСТЬ ПАДЕНИЯ ==="
exit $fail
