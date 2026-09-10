-- ============================================================================
-- blocking_sessions.sql
--
-- Purpose:
--   Reports current blocking chains: which sessions are waiting on locks,
--   who holds the locks, and how long each waiter has been blocked.
--   The blocker shown is the *direct* blocker; the head of the chain is
--   the blocker that is not itself waiting (its blocker_event will show
--   it idle or working on something else).
--
-- Usage:
--   sqlplus / as sysdba @blocking_sessions.sql
--
--   To change the threshold, edit the DEFINE below
--   (default: only show sessions blocked for 30 seconds or more).
--
-- Exit code:
--   0 - no blocking at or above the threshold
--   2 - at least one session blocked at or above the threshold
--
-- Notes:
--   Read-only. Short-lived locks are normal; a blocked session is usually
--   a symptom, not the problem. See docs/blocking-session-runbook.md
--   before killing anything.
-- ============================================================================

SET ECHO OFF
SET FEEDBACK OFF
SET VERIFY OFF
SET PAGESIZE 100
SET LINESIZE 160
SET TRIMSPOOL ON
SET TAB OFF

-- ----------------------------------------------------------------------------
-- Threshold (seconds blocked) before a waiter is reported. Edit to match
-- local standards; brief locks are normal and not worth alerting on.
-- ----------------------------------------------------------------------------
DEFINE min_blocked_sec = 30

TTITLE LEFT 'Blocking sessions - blocked >= &min_blocked_sec seconds' SKIP 1

COLUMN waiter_sid      FORMAT 99999  HEADING 'WAITER|SID'
COLUMN waiter_serial   FORMAT 999999 HEADING 'WAITER|SERIAL#'
COLUMN waiter_user     FORMAT A12    HEADING 'WAITER|USER'
COLUMN waiter_machine  FORMAT A16    HEADING 'WAITER|MACHINE'
COLUMN waiter_program  FORMAT A20    HEADING 'WAITER|PROGRAM'
COLUMN wait_event      FORMAT A28    HEADING 'WAIT|EVENT'
COLUMN blocked_sec     FORMAT 999999 HEADING 'BLOCKED|SEC'
COLUMN waiter_sql      FORMAT A13    HEADING 'WAITER|SQL_ID'
COLUMN blocker_sid     FORMAT 99999  HEADING 'BLOCKER|SID'
COLUMN blocker_serial  FORMAT 999999 HEADING 'BLOCKER|SERIAL#'
COLUMN blocker_user    FORMAT A12    HEADING 'BLOCKER|USER'
COLUMN blocker_machine FORMAT A16    HEADING 'BLOCKER|MACHINE'
COLUMN blocker_program FORMAT A20    HEADING 'BLOCKER|PROGRAM'
COLUMN blocker_event   FORMAT A28    HEADING 'BLOCKER|EVENT'

SELECT w.sid                        AS waiter_sid,
       w.serial#                    AS waiter_serial,
       w.username                   AS waiter_user,
       SUBSTR(w.machine, 1, 16)     AS waiter_machine,
       SUBSTR(w.program, 1, 20)     AS waiter_program,
       w.event                      AS wait_event,
       w.seconds_in_wait             AS blocked_sec,
       w.sql_id                      AS waiter_sql,
       b.sid                         AS blocker_sid,
       b.serial#                     AS blocker_serial,
       b.username                    AS blocker_user,
       SUBSTR(b.machine, 1, 16)      AS blocker_machine,
       SUBSTR(b.program, 1, 20)      AS blocker_program,
       b.event                       AS blocker_event
  FROM v$session w
  JOIN v$session b
    ON b.sid     = w.blocking_session
   AND b.inst_id = NVL(w.blocking_instance, 1)
 WHERE w.blocking_session IS NOT NULL
   AND w.seconds_in_wait >= &min_blocked_sec
 ORDER BY w.seconds_in_wait DESC;

TTITLE OFF

PROMPT
PROMPT --- Distinct blockers and how many sessions each is holding up ---
COLUMN blocker_sid  FORMAT 99999 HEADING 'BLOCKER|SID'
COLUMN blocker_user FORMAT A16   HEADING 'USER'
COLUMN victims      FORMAT 999   HEADING 'SESSIONS|WAITING'

SELECT b.sid      AS blocker_sid,
       b.username AS blocker_user,
       COUNT(*)   AS victims
  FROM v$session w
  JOIN v$session b
    ON b.sid     = w.blocking_session
   AND b.inst_id = NVL(w.blocking_instance, 1)
 WHERE w.blocking_session IS NOT NULL
   AND w.seconds_in_wait >= &min_blocked_sec
 GROUP BY b.sid, b.username
 ORDER BY victims DESC;

-- ----------------------------------------------------------------------------
-- Set the process exit code for scheduler / monitoring integration.
-- ----------------------------------------------------------------------------
COLUMN exit_code NOPRINT NEW_VALUE v_exit_code
SELECT CASE WHEN COUNT(*) > 0 THEN 2 ELSE 0 END AS exit_code
  FROM v$session
 WHERE blocking_session IS NOT NULL
   AND seconds_in_wait >= &min_blocked_sec;

PROMPT
PROMPT Done. Exit code: &v_exit_code (0 = no blocking, 2 = blocking found)
EXIT &v_exit_code
