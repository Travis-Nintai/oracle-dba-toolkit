-- ============================================================================
-- tablespace_utilization.sql
--
-- Purpose:
--   Reports current tablespace utilization and flags any tablespace above
--   the configured warning or critical thresholds. Designed for daily DBA
--   review or scheduled runs (cron / scheduler wrapper).
--
-- Usage:
--   sqlplus / as sysdba @tablespace_utilization.sql
--
--   To change thresholds, edit the DEFINE statements below
--   (defaults: warn at 85%, critical at 95%).
--
-- Exit code:
--   0 - all tablespaces below the critical threshold
--   2 - at least one tablespace at or above the critical threshold
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 60
SET LINESIZE 140
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Thresholds (percent full). Edit to match local standards.
-- ----------------------------------------------------------------------------
DEFINE warn_pct = 85
DEFINE crit_pct = 95

COLUMN tablespace_name FORMAT A28          HEADING 'TABLESPACE'
COLUMN total_mb         FORMAT 999,999,990 HEADING 'TOTAL|MB'
COLUMN used_mb          FORMAT 999,999,990 HEADING 'USED|MB'
COLUMN free_mb          FORMAT 999,999,990 HEADING 'FREE|MB'
COLUMN pct_used         FORMAT 990.0       HEADING 'PCT|USED'
COLUMN alert_level      FORMAT A10         HEADING 'STATUS'

TTITLE LEFT 'Tablespace utilization - warn >= &warn_pct.%, critical >= &crit_pct.%' SKIP 1

SELECT t.tablespace_name,
       ROUND(u.tablespace_size * p.block_size / 1024 / 1024, 1)                    AS total_mb,
       ROUND(u.used_space      * p.block_size / 1024 / 1024, 1)                    AS used_mb,
       ROUND((u.tablespace_size - u.used_space) * p.block_size / 1024 / 1024, 1)    AS free_mb,
       ROUND(u.used_percent, 1)                                                    AS pct_used,
       CASE
         WHEN u.used_percent >= &crit_pct THEN 'CRITICAL'
         WHEN u.used_percent >= &warn_pct THEN 'WARNING'
         ELSE 'OK'
       END                                                                         AS alert_level
  FROM dba_tablespaces t
  JOIN dba_tablespace_usage_metrics u
    ON u.tablespace_name = t.tablespace_name
 CROSS JOIN (SELECT TO_NUMBER(value) AS block_size
               FROM v$parameter
              WHERE name = 'db_block_size') p
 ORDER BY u.used_percent DESC;

TTITLE OFF

-- ----------------------------------------------------------------------------
-- Set the process exit code for scheduler / monitoring integration.
-- ----------------------------------------------------------------------------
COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE WHEN COUNT(*) > 0 THEN 2 ELSE 0 END AS exit_code
  FROM dba_tablespace_usage_metrics
 WHERE used_percent >= &crit_pct;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = OK, 2 = critical tablespace found)
EXIT &v_exit_code
