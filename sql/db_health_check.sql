-- ============================================================================
-- db_health_check.sql
--
-- Purpose:
--   Single-pass database health summary for daily operational review:
--   instance/database status, uptime, sessions, invalid objects,
--   tablespace pressure, flash recovery area usage, and recent RMAN backups.
--
-- Usage:
--   sqlplus / as sysdba @db_health_check.sql
--
-- Notes:
--   Read-only. Issues no DML or DDL and is safe to run any time.
--   Views used are available in Oracle 11g and later.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 140
SET TRIMSPOOL ON
SET TAB OFF

PROMPT
PROMPT ================================================================
PROMPT  DATABASE HEALTH CHECK
PROMPT ================================================================

PROMPT
PROMPT --- Instance and database status ---
COLUMN host_name       FORMAT A18
COLUMN version         FORMAT A12
COLUMN status          FORMAT A12
COLUMN database_status FORMAT A12
COLUMN open_mode       FORMAT A10
COLUMN database_role   FORMAT A16
SELECT i.host_name,
       i.version,
       i.status,
       i.database_status,
       d.open_mode,
       d.database_role
  FROM v$instance i
 CROSS JOIN v$database d;

PROMPT
PROMPT --- Uptime ---
SELECT TO_CHAR(startup_time, 'YYYY-MM-DD HH24:MI:SS') AS startup_time,
       TRUNC(SYSDATE - startup_time) || 'd ' ||
       TRUNC(MOD((SYSDATE - startup_time) * 24, 24)) || 'h' AS uptime
  FROM v$instance;

PROMPT
PROMPT --- Sessions (non-background) ---
SELECT COUNT(*)                                              AS total_sessions,
       COUNT(DISTINCT username)                              AS distinct_users,
       SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END)    AS active_sessions
  FROM v$session
 WHERE type <> 'BACKGROUND';

PROMPT
PROMPT --- Invalid objects by owner (normally zero) ---
COLUMN owner FORMAT A24
SELECT owner,
       COUNT(*) AS invalid_count
  FROM dba_objects
 WHERE status = 'INVALID'
 GROUP BY owner
 ORDER BY invalid_count DESC;

PROMPT
PROMPT --- Tablespaces at or above 85% used ---
COLUMN tablespace_name FORMAT A28
COLUMN pct_used         FORMAT 990.0
SELECT t.tablespace_name,
       ROUND(u.used_percent, 1) AS pct_used
  FROM dba_tablespaces t
  JOIN dba_tablespace_usage_metrics u
    ON u.tablespace_name = t.tablespace_name
 WHERE u.used_percent >= 85
 ORDER BY u.used_percent DESC;

PROMPT
PROMPT --- Flash recovery area ---
COLUMN name FORMAT A40
SELECT name,
       ROUND(space_limit / 1024 / 1024, 1)                  AS limit_mb,
       ROUND(space_used  / 1024 / 1024, 1)                  AS used_mb,
       ROUND(space_used * 100 / NULLIF(space_limit, 0), 1)  AS pct_used
  FROM v$recovery_file_dest;

PROMPT
PROMPT --- Recent RMAN backup jobs (latest 10) ---
COLUMN input_type FORMAT A12
COLUMN job_status FORMAT A12
SELECT input_type,
       status          AS job_status,
       TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI') AS started,
       TO_CHAR(end_time,   'YYYY-MM-DD HH24:MI') AS ended
  FROM (SELECT input_type, status, start_time, end_time
          FROM v$rman_backup_job_details
         ORDER BY start_time DESC)
 WHERE ROWNUM <= 10;

PROMPT
PROMPT --- End of health check ---
