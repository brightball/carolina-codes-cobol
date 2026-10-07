# Memory

Current-state index for this repository. What is true now, and where the decision lives. This is not a session transcript and not a second contract. Operating rules are in `AGENTS.md`. The reason for each choice is in `DECISIONS.md`.

If this index disagrees with `AGENTS.md` or `DECISIONS.md`, those files win. Fix this index. When a durable decision changes, supersede the `DECISIONS.md` entry and update the matching line here in the same change.

## Now

- This repository is the workspace root. Read-only v1 API. Ordinary JSON for the OpenAPI routes. Query Postgres `v1_*` views only, never Ash tables.
- Register once on boot and keep serving if the CMS is down (no heartbeat). `GET /health` returns `{"status":"ok"}` and does not touch the database.
- Identity reported by `GET /`: language COBOL, framework POSIX sockets, language version GnuCOBOL 3.2. POSIX sockets have no framework package version. API version string is `0.2.0`.
- Sources are free-format GnuCOBOL (`-free`). See ADR-0002.
- Live SQL and listening go through the C trampolines (`src/pq.c` libpq, `src/listen6.c` dual-stack listen). Not embedded SQL. Not a copy of another sibling's server. See ADR-0001.
- Rows cross the FFI as TSV. See ADR-0003. PIC X buffers are space-padded. Null-terminate before `CALL`, and `MOVE SPACES` before reusing a field. See ADR-0006.
- The image and the local compiler are GnuCOBOL 3.2. Gitea CI installs Debian Bookworm packaged `gnucobol`. See ADR-0004.
- Year-scoped speaker detail includes a `talks` array. See ADR-0005.
- Handler tests call the shipped router (`HANDLE-GET`) with a fake catalog (`src/catalog-fake.cob`).
- Notable runtime packages: libpq and libgmp (GnuCOBOL runtime library).
- Local gates are `make test`, `sast`, `audit`, `gitleaks`, and `lint`.
- Local listen fallback is port 4027. The container image sets `PORT=8080`.

## Where decisions live

| What is true now | Entry |
|---|---|
| C trampolines for libpq and dual-stack listen | `DECISIONS.md` ADR-0001 |
| Free-format GnuCOBOL (`-free`) | `DECISIONS.md` ADR-0002 |
| TSV via libpq | `DECISIONS.md` ADR-0003 |
| GnuCOBOL 3.2 in the image and local prefix; Bookworm `gnucobol` in Gitea CI | `DECISIONS.md` ADR-0004 |
| `talks` on year-scoped speaker detail | `DECISIONS.md` ADR-0005 |
| PIC X is not a C string | `DECISIONS.md` ADR-0006 |
