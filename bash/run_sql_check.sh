#!/usr/bin/env bash
#
# run_sql_check.sh -- run a toolkit SQL*Plus check with logging and
# scheduler-friendly exit codes.
#
# Usage:
#   run_sql_check.sh -s ORACLE_SID -f check.sql [-c connect_string] [-l log_dir]
#
# Options:
#   -s SID            Oracle SID to check (also sets ORACLE_SID). Required.
#   -f FILE           SQL*Plus script to run. Required.
#   -c CONNECT        Connect string, e.g. "user/pass@tns_alias".
#                     Default: "/ as sysdba".
#   -l DIR            Directory for timestamped log files. Default: ./logs
#   -h                Show this help.
#
# Behavior:
#   Sets ORACLE_SID, runs the script through sqlplus, and writes all output
#   to a timestamped log file. The script's own exit code (0 = clean,
#   2 = problem found) is passed through. If sqlplus itself fails or the
#   log contains ORA- errors, the script exits 2 so the scheduler treats
#   the run as needing attention.
#
# Examples:
#   run_sql_check.sh -s ORCLLAB -f sql/tablespace_utilization.sql
#   run_sql_check.sh -s ORCLLAB -f sql/db_health_check.sql -l /var/log/dbchecks
#
# Exit codes:
#   0 - check ran clean
#   1 - usage / environment error (bad args, missing sqlplus, unreadable script)
#   2 - check reported a problem, or the run itself failed

set -u

PROG="$(basename "$0")"

usage() {
    cat <<'EOF'
Usage: run_sql_check.sh -s ORACLE_SID -f check.sql [-c connect_string] [-l log_dir]

  -s SID       Oracle SID to check (also sets ORACLE_SID). Required.
  -f FILE      SQL*Plus script to run. Required.
  -c CONNECT   Connect string, e.g. "user/pass@tns_alias". Default: "/ as sysdba".
  -l DIR       Directory for timestamped log files. Default: ./logs
  -h           Show this help.

Exit codes: 0 = check ran clean, 1 = usage/environment error,
            2 = check reported a problem or the run itself failed.
EOF
}

SID=""
SQLFILE=""
CONNECT="/ as sysdba"
LOGDIR="./logs"

while getopts ":s:f:c:l:h" opt; do
    case "$opt" in
        s) SID="$OPTARG" ;;
        f) SQLFILE="$OPTARG" ;;
        c) CONNECT="$OPTARG" ;;
        l) LOGDIR="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) echo "$PROG: option -$OPTARG requires an argument" >&2; exit 1 ;;
        \?) echo "$PROG: unknown option -$OPTARG" >&2; exit 1 ;;
    esac
done

# --- Validate inputs ---------------------------------------------------------
if [ -z "$SID" ]; then
    echo "$PROG: -s ORACLE_SID is required" >&2
    exit 1
fi

if [ -z "$SQLFILE" ]; then
    echo "$PROG: -f script.sql is required" >&2
    exit 1
fi

if [ ! -r "$SQLFILE" ]; then
    echo "$PROG: cannot read SQL script: $SQLFILE" >&2
    exit 1
fi

if ! command -v sqlplus >/dev/null 2>&1; then
    echo "$PROG: sqlplus not found on PATH" >&2
    exit 1
fi

if ! mkdir -p "$LOGDIR" 2>/dev/null; then
    echo "$PROG: cannot create log directory: $LOGDIR" >&2
    exit 1
fi

# --- Run the check ------------------------------------------------------------
export ORACLE_SID="$SID"

STAMP="$(date +%Y%m%d_%H%M%S)"
BASE="$(basename "$SQLFILE" .sql)"
LOGFILE="$LOGDIR/${BASE}_${SID}_${STAMP}.log"

if [ "$CONNECT" = "/ as sysdba" ]; then
    CONNECT_DESC="/ as sysdba"
else
    CONNECT_DESC="custom connect string (hidden)"
fi

{
    echo "=== $PROG ==="
    echo "timestamp : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "sid       : $SID"
    echo "script    : $SQLFILE"
    echo "connect   : $CONNECT_DESC"
    echo
    sqlplus -S "$CONNECT" @"$SQLFILE"
    echo "sqlplus_exit=$?"
} >"$LOGFILE" 2>&1

SQLPLUS_RC="$(grep -E '^sqlplus_exit=' "$LOGFILE" | tail -1 | cut -d= -f2)"

# --- Evaluate the result -------------------------------------------------------
if grep -qE 'ORA-[0-9]+' "$LOGFILE"; then
    echo "$PROG: ORA- error detected during run; see $LOGFILE" >&2
    exit 2
fi

if [ "$SQLPLUS_RC" != "0" ] && [ "$SQLPLUS_RC" != "2" ]; then
    echo "$PROG: sqlplus exited with unexpected code $SQLPLUS_RC; see $LOGFILE" >&2
    exit 2
fi

echo "$PROG: done, exit $SQLPLUS_RC (log: $LOGFILE)"
exit "$SQLPLUS_RC"
