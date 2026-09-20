# Roadmap

| Milestone | Objective and deliverables | Depends on | Main risk | Exit criterion |
|---|---|---|---|---|
| M0 Bootstrap | Harness, domain contracts, navigation, tests | Existing repo | iOS validation deferred | Core gates passed; M0_DONE |
| M1 SSH | Authentication, host verification, known hosts, lifecycle | M0 | Key and host security | Real iOS SSH and failure tests |
| M1.5 Secure Persistence | Durable profiles and host trust, OS-backed credentials, app wiring, lab harness | M1 | Storage and device behavior | Core gates; iOS and lab status explicit |
| M1.6 SSH Integration Lab | Real isolated SSH handshake, host trust, auth and failure paths | M1.5 | Local lab availability | Real lab matrix and gates passed |
| M2 Terminal | Interactive terminal and keyboard | M1 | TUI input/selection | iPhone terminal usability tests |
| M3 tmux | Session discovery, detach, reattach | M2 | Stale state | Resume after network loss |
| M4 SFTP | Browse, edit, transfer | M1, M3 | Partial writes | Safe transfer and error tests |
| M5 Agents | Provider contract and observed state | M3 | False state inference | Provider and disconnect tests |
| M6 Git | Remote status/diff/actions | M4 | Destructive Git ops | Policy and parsing tests |
| M7 Server Operations | Selected Docker/PM2/Nginx/logs | M6 | Production impact | Least-privilege review |
| M8 Server Companion | Optional structured service | M5, M7 | New attack surface | Auth and tunnel review |
| M9 Push Notifications | Server-originated alerts via APNs | M8 | Delivery/privacy | Device and failure tests |

Milestones are sequential. Review the current stage's exit criteria before advancing; later entries are planning, not implementation commitments.



