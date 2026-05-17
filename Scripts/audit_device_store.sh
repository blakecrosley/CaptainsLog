#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="${CAPTAINS_LOG_BUNDLE_ID:-com.blakecrosley.captainslog}"
DEVICE_ID="${CAPTAINS_LOG_DEVICE_ID:-00008150-00166D690EF0401C}"
DESTINATION="${1:-/tmp/captainslog-device-store-audit}"
STORE_NAME="${CAPTAINS_LOG_STORE_NAME:-default.store}"
END_DAY="${CAPTAINS_LOG_AUDIT_END_DAY:-$(date +%F)}"
START_DAY="${CAPTAINS_LOG_AUDIT_START_DAY:-${END_DAY%%-*}-01-01}"

fail() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

sql() {
    sqlite3 -readonly "$SQLITE_STORE" "$1"
}

sql_table() {
    sqlite3 -readonly -header -column "$SQLITE_STORE" "$1"
}

need_command xcrun
need_command sqlite3

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION/source" "$DESTINATION/sqlite"

printf "Captain's Log device store audit\n"
printf 'Device: %s\n' "$DEVICE_ID"
printf 'Bundle: %s\n' "$BUNDLE_ID"
printf 'Destination: %s\n\n' "$DESTINATION"

xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "Library/Application Support" \
    --destination "$DESTINATION/source" \
    --timeout 120 \
    --json-output "$DESTINATION/copy.json" \
    >/dev/null

SOURCE_STORE="$DESTINATION/source/$STORE_NAME"
SOURCE_WAL="$DESTINATION/source/$STORE_NAME-wal"
[[ -f "$SOURCE_STORE" ]] || fail "Store not found after copy: $SOURCE_STORE"
cp "$SOURCE_STORE" "$DESTINATION/sqlite/$STORE_NAME"
if [[ -f "$SOURCE_WAL" ]]; then
    cp "$SOURCE_WAL" "$DESTINATION/sqlite/$STORE_NAME-wal"
fi

SQLITE_STORE="$DESTINATION/sqlite/$STORE_NAME"
integrity="$(sql 'PRAGMA integrity_check;')"
[[ "$integrity" == "ok" ]] || fail "SQLite integrity check failed: $integrity"

printf 'SQLite integrity: ok\n\n'

printf 'Store summary\n'
sql_table "
SELECT
    (SELECT COUNT(*) FROM ZGITHUBACCOUNTRECORD) AS accounts,
    (SELECT COUNT(*) FROM ZGITREPOSITORYRECORD) AS repositories,
    (SELECT COUNT(*) FROM ZGITREPOSITORYRECORD WHERE ZISSELECTED = 1) AS selected_repositories,
    (SELECT COUNT(*) FROM ZGITCOMMITRECORD) AS commits,
    (SELECT COUNT(*) FROM ZDAILYJOURNALSUMMARYRECORD) AS journal_summaries;
"

printf '\nCommit span\n'
sql_table "
SELECT
    MIN(ZDAYKEY) AS first_day,
    MAX(ZDAYKEY) AS last_day,
    COUNT(DISTINCT ZDAYKEY) AS active_days,
    COUNT(*) AS commits
FROM ZGITCOMMITRECORD;
"

printf '\nDiff-stat coverage\n'
sql_table "
SELECT
    COUNT(*) AS commits,
    SUM(CASE WHEN ZDIFFSTATSFETCHEDAT IS NOT NULL THEN 1 ELSE 0 END) AS commits_with_diff_stats,
    SUM(CASE WHEN ZDIFFSTATSFETCHEDAT IS NULL THEN 1 ELSE 0 END) AS missing_diff_stats,
    SUM(CASE WHEN ZDIFFSTATSERROR IS NOT NULL AND length(ZDIFFSTATSERROR) > 0 THEN 1 ELSE 0 END) AS diff_stat_errors,
    COALESCE(SUM(ZTOTALCHANGES), 0) AS known_changed_lines,
    COALESCE(SUM(ZADDITIONS), 0) AS additions,
    COALESCE(SUM(ZDELETIONS), 0) AS deletions
FROM ZGITCOMMITRECORD;
"

printf '\nCurrent-year day coverage (%s through %s)\n' "$START_DAY" "$END_DAY"
sql_table "
WITH RECURSIVE dates(day) AS (
    SELECT date('$START_DAY')
    UNION ALL
    SELECT date(day, '+1 day') FROM dates WHERE day < date('$END_DAY')
),
counts AS (
    SELECT ZDAYKEY, COUNT(*) AS count
    FROM ZGITCOMMITRECORD
    WHERE ZDAYKEY BETWEEN '$START_DAY' AND '$END_DAY'
    GROUP BY ZDAYKEY
)
SELECT
    COUNT(*) AS days,
    SUM(CASE WHEN counts.count IS NOT NULL THEN 1 ELSE 0 END) AS active_days,
    SUM(CASE WHEN counts.count IS NULL THEN 1 ELSE 0 END) AS empty_days,
    COALESCE(MAX(counts.count), 0) AS busiest_day_commits
FROM dates
LEFT JOIN counts ON counts.ZDAYKEY = dates.day;
"

printf '\nCurrent-year month summary\n'
sql_table "
SELECT
    substr(ZDAYKEY, 1, 7) AS month,
    COUNT(DISTINCT ZDAYKEY) AS active_days,
    COUNT(*) AS commits,
    COALESCE(SUM(ZTOTALCHANGES), 0) AS changed_lines
FROM ZGITCOMMITRECORD
WHERE ZDAYKEY BETWEEN '$START_DAY' AND '$END_DAY'
GROUP BY month
ORDER BY month;
"

printf '\nRecent day summary\n'
sql_table "
SELECT
    ZDAYKEY AS day,
    COUNT(*) AS commits,
    COALESCE(SUM(ZTOTALCHANGES), 0) AS changed_lines
FROM ZGITCOMMITRECORD
WHERE ZDAYKEY >= date('$END_DAY', '-16 days')
GROUP BY ZDAYKEY
ORDER BY ZDAYKEY;
"

