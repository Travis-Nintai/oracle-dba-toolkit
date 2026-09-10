-- ============================================================================
-- rman_backup_status.sql
--
-- Purpose:
--   Reviews recent RMAN backup jobs: what ran, what type it was, how long
--   it took, and whether anything failed. Flags any failed job inside the
--   lookback window so a scheduler can alert on the exit code.
--
-- Usage:
--   sqlplus / as sysdba @rman_backup_status.sql
--
--   To change the window, edit the DEFINE below (default: last 7 days).
--
-- Exit code:
--   0 - no failed backup jobs in the lookback window
--   2 - at least one failed backup job in the lookback window
--
-- Notes:
--   Read-only. History depth depends on CONTROL_FILE_RECORD_KEEP_TIME,
--   since this reads the control-file-based V$RMAN_BACKUP_JOB_DETAILS.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Lookback window in days. Edit to match local backup review standards.
-- ----------------------------------------------------------------------------
DEFINE lookback_days = 7

TTITLE LEFT 'RMAN backup jobs - last &lookback_days days' SKIP 1

COLUMN input_type  FORMAT A14     HEADING 'TYPE'
COLUMN job_status  FORMAT A12     HEADING 'STATUS'
COLUMN started     FORMAT A16     HEADING 'STARTED'
COLUMN ended       FORMAT A16     HEADING 'ENDED'
COLUMN mins        FORMAT 999,990 HEADING 'MINUTES'
COLUMN output_size FORMAT A12     HEADING 'OUTPUT'

SELECT input_type,
       status                                        AS job_status,
       TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI')     AS started,
       TO_CHAR(end_time,   'YYYY-MM-DD HH24:MI')     AS ended,
       ROUND((end_time - start_time) * 24 * 60)      AS mins,
       output_bytes_display                          AS output_size
  FROM v$rman_backup_job_details
 WHERE start_time >= SYSDATE - &lookback_days
 ORDER BY start_time DESC;

TTITLE OFF

PROMPT
PROMPT --- Summary by status ---
COLUMN job_status FORMAT A12 HEADING 'STATUS'
COLUMN job_count  FORMAT 9999 HEADING 'COUNT'

SELECT status   AS job_status,
       COUNT(*) AS job_count
  FROM v$rman_backup_job_details
 WHERE start_time >= SYSDATE - &lookback_days
 GROUP BY status
 ORDER BY job_count DESC;

-- ----------------------------------------------------------------------------
-- Set the process exit code for scheduler / monitoring integration.
-- ----------------------------------------------------------------------------
COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE WHEN COUNT(*) > 0 THEN 2 ELSE 0 END AS exit_code
  FROM v$rman_backup_job_details
 WHERE start_time >= SYSDATE - &lookback_days
   AND status = 'FAILED';

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = no failures, 2 = failed backup found)
EXIT &v_exit_code
