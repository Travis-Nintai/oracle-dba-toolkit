# Oracle DBA Toolkit

Day-to-day Oracle monitoring utilities: the checks a DBA runs every morning, packaged as small, focused scripts. Tablespace pressure, instance health, blocking sessions, backup status — configurable thresholds, readable output, nothing hard-coded.

## Who it's for

Oracle DBAs who want a consistent, repeatable health-check routine instead of a pile of one-off ad hoc queries. The scripts assume you already administer Oracle databases and just want the routine checks standardized.

## Contents

```
oracle-dba-toolkit/
├── sql/    -- SQL*Plus scripts; run directly or wrap in cron
├── bash/   -- shell wrappers and scheduling glue (growing)
└── docs/   -- runbooks and script conventions
```

Current scripts:

| Script | What it does |
|---|---|
| `sql/tablespace_utilization.sql` | Tablespace usage with warn/critical flags and a scheduler-friendly exit code |
| `sql/db_health_check.sql` | One-pass daily health summary: instance, sessions, invalid objects, space, FRA, RMAN |
| `sql/blocking_sessions.sql` | Blocking chains: waiters, direct blockers, seconds blocked; exit 2 when found |
| `sql/rman_backup_status.sql` | Recent RMAN jobs with type, duration, and status; exit 2 on any failure |
| `bash/run_sql_check.sh` | Wrapper: runs any check with a timestamped log and 0/2 exit codes for schedulers |

## Usage

Tablespace check (connect as a privileged user, e.g. `/ as sysdba`):

```
sqlplus / as sysdba @sql/tablespace_utilization.sql
```

Thresholds live in the `DEFINE warn_pct` / `DEFINE crit_pct` lines at the top of the script — defaults are 85 and 95. The script exits `0` when everything is below critical and `2` when any tablespace crosses it, so a scheduler can alert on the exit code.

Daily health check:

```
sqlplus / as sysdba @sql/db_health_check.sql
```

Read-only. No DML or DDL, safe to run any time.

Blocking sessions (30-second default threshold — edit the `DEFINE` to change it):

```
sqlplus / as sysdba @sql/blocking_sessions.sql
```

A blocked session is usually a symptom, not the problem. Work through
`docs/blocking-session-runbook.md` before killing anything.

RMAN backup status for the last 7 days:

```
sqlplus / as sysdba @sql/rman_backup_status.sql
```

Running a check on a schedule with logging:

```
bash/run_sql_check.sh -s ORCLLAB -f sql/tablespace_utilization.sql
```

The wrapper sets `ORACLE_SID`, runs the script through sqlplus, writes a
timestamped log to `./logs`, and exits 0 when the check is clean, 2 when the
check reports a problem or the run itself fails. See the script header for
all options.

## Sample output

```
Tablespace utilization - warn >= 85%, critical >= 95%

TABLESPACE                     TOTAL MB     USED MB     FREE MB  PCT USED  STATUS
---------------------------- ---------- ---------- ---------- --------- ----------
SYSAUX                            1,024        880        144      85.9   WARNING
USERS                               512         12        500       2.3   OK
SYSTEM                              910        700        210      76.9   OK
```

## Assumptions

- Oracle 11g or later. The scripts use `DBA_TABLESPACE_USAGE_METRICS`, `V$INSTANCE`, `V$DATABASE`, `V$SESSION`, `V$RECOVERY_FILE_DEST`, and `V$RMAN_BACKUP_JOB_DETAILS`.
- Run with a user that can read the data dictionary (`/ as sysdba` for the health check).
- Database names, hosts, and paths in examples are fictional lab values. Point the scripts at your own environment.

## Safety notes

- Nothing here modifies data. Still, run any new script against a non-production database first and confirm the output looks right.
- Thresholds are defaults, not recommendations — set them to match your SLA and growth patterns.
- Never commit credentials, hostnames, or environment-specific connection details alongside these scripts. See `docs/script-conventions.md`.

## What this demonstrates

Routine Oracle operational monitoring: space management, instance health, session analysis, recovery-area sizing, and backup-job review — the daily discipline behind keeping production databases up. Scripts are written the way they'd be used on the job: configurable, schedulable, and honest about what they assume.

## Background

Recreated from standard DBA practice for a personal lab portfolio — generic examples, not exports from any production environment. That keeps them safe to share and easy to adapt.
