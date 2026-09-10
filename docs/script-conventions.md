# Script conventions

Every script in this repo follows the same shape so it's predictable to run and safe to schedule:

- Header comment: purpose, usage, and exit codes. Nothing else in the header.
- Thresholds as `DEFINE` variables at the top, with defaults noted in the comment.
- No hard-coded hostnames, SIDs, service names, credentials, or paths. Examples use placeholders like `$ORACLE_SID`, `<SERVICE_NAME>`, and `<DB_HOST>`.
- Read-only by default. Anything that changes state says so in the header and prompts before acting.
- Exit code 0 on success; non-zero on failure or threshold breach, documented per script.
- Output is plain text — readable in a terminal and greppable in logs.

New scripts should add a usage example to the README and a row to the portfolio tracker.
