# Blocking session runbook

How to work a blocking/locking situation without making it worse. Assumes you
can already see the chain — run `sql/blocking_sessions.sql` first.

## 1. Find the head blocker

The script shows waiter → direct blocker pairs. The head blocker is the session
nobody is waiting on: in the "Distinct blockers" summary it is the one whose
own wait event is idle (for example `SQL*Net message from client`) rather than
`enq: TX - row lock contention`. Everything downstream is a victim.

Kill the head blocker and the chain clears. Kill a victim and you change
nothing — the application reconnects and blocks again on the same lock.

## 2. Look at what the blocker is doing

Before touching it, answer these:

- What program and machine is it? An overnight batch job, an application
  server session, or an ad-hoc SQL*Plus session someone left open?
- What SQL is it running? Check `sql_id` from the script output against
  `v$sql`.
- How long has it been idle? A session holding a lock while idle
  (`SQL*Net message from client` for 40 minutes) is usually a forgotten
  open transaction — the safest kill candidate.
- Is it already rolling back? Check `v$transaction` / `v$session_longops`.
  Killing a session mid-rollback just restarts the wait: SMON has to finish
  the rollback before the lock releases, and you have thrown away the work
  for nothing.

## 3. Decide: kill, wait, or escalate

Kill when:

- The blocker is idle with an open transaction and the owner cannot be
  reached.
- The blocked workload is production-critical and the blocker is clearly
  lower priority.

Wait when:

- The blocker is actively working and nearly done — check
  `v$session_longops` for progress. Killing it discards the work and the
  resulting rollback blocks everyone anyway.

Escalate when:

- The blocker belongs to a critical batch or application process you do not
  own. Page the application team or job owner instead of killing blind.
- Blocking recurs on a schedule. That is an application design issue
  (commit frequency, lock ordering), not an operations problem. Capture the
  SQL and AWR/ASH around the window and hand it to development.

## 4. Killing safely

```sql
ALTER SYSTEM KILL SESSION 'sid,serial#' IMMEDIATE;
```

- Use both sid and serial# — a sid alone can be reused by the time you act.
- `IMMEDIATE` returns control at once; without it the kill can hang behind
  the very lock you are trying to clear.
- Re-run the monitor to confirm the chain is gone, then check that the
  waiter sessions recovered (application reconnect logic, connection pool
  state).
- If the killed session lingers in `KILLED` status, it is rolling back.
  Watch `v$transaction.used_ublk` shrink. Do not kill PMON, and do not
  bounce the instance to "speed it up".

## 5. What not to do

- Do not kill the waiters to "relieve pressure". The lock is still held; the
  application reconnects and blocks again, now with added reconnect storms.
- Do not kill background processes or sessions you cannot identify. When in
  doubt, escalate.
- Do not treat one incident as solved if it repeats. Recurring blocking means
  the fix belongs in the application or the job schedule.

## 6. After the incident

- Note the blocker program, SQL, and time window. Two occurrences is a
  pattern.
- If it was a forgotten open transaction, find the owner and close the loop —
  the cheapest fix is a conversation.
- For recurring cases, pull ASH for the window (`v$active_session_history`)
  to show exactly where time went before asking development for changes.
