# Decisions

In-repo decision log for this GnuCOBOL and POSIX sockets API. One decision per entry, in ADR form.

Each entry has a status, context, alternatives considered, the decision, and consequences. An accepted entry stays binding until a later entry supersedes it. When that happens, leave the old entry in place, set its status to superseded, and name the entry that replaces it. Do not delete accepted history.

Agents read this file with `AGENTS.md` and `MEMORY.md`. When a durable decision changes, add the superseding entry and update the `MEMORY.md` index in the same change. `COBOL.md` records how the compiler behaved on a given machine. It does not replace this log.

## ADR-0001: C trampolines for SQL and sockets

- Status: accepted
- Context: COBOL has no sockets and no libpq. This API has to query Postgres `v1_*` views and accept HTTP on a dual-stack port. GnuCOBOL compiles to C, and `CALL "name"` is the FFI, so the missing pieces can live in a small C file without taking over request handling.
- Alternatives considered: Embedded SQL (ocesql or GixSQL), which adds a second precompiler. Packing `struct sockaddr_in6` into COBOL `PIC` fields and `CALL`ing `socket`, `bind`, and `listen` directly. Copying another sibling's HTTP server into this tree and relabeling it.
- Decision: Live SQL and listening go through the C trampolines. `src/pq.c` exposes `carolina_query` (libpq). `src/listen6.c` exposes `carolina_listen`, `accept`, `recv`, `send`, `close`, and the one-shot register client. Request parse, routing, and JSON stay in `src/server.cob` and `src/handler.cob`. This is not embedded SQL and not a copy of another sibling's server.
- Consequences: Socket layout, `htons`, and `IPV6_V6ONLY=0` stay in C, where the struct size is the platform's. COBOL does not bind a garbage address. A new query still goes through `CATALOG-QUERY` and returns TSV (ADR-0003). Register stays a single POST at process start, off the accept path, so a down CMS does not block `GET /health`.

## ADR-0002: Free-format GnuCOBOL

- Status: accepted
- Context: GnuCOBOL accepts fixed-form (columns 7–72) and free-form source. The programs in this tree are indented like ordinary structured code, with `>>SOURCE FORMAT FREE` at column 1. The image and the local compiler are GnuCOBOL 3.2. Gitea CI installs Debian Bookworm packaged `gnucobol`, which is the 3.1 line. GnuCOBOL 3.2 accepts the directive at column 1. 3.1.2 needs `-free`.
- Alternatives considered: Fixed-form source, which would fight indentation and the C-like layout of the handler. Relying on the column-1 directive alone, which fails the Bookworm compiler. Maintaining two copies of the programs.
- Decision: Sources stay free-format GnuCOBOL. The `Makefile` passes `-free` on every `cobc` invocation, which satisfies both GnuCOBOL 3.2 and Bookworm `gnucobol` 3.1.2. Each program also carries `>>SOURCE FORMAT FREE`.
- Consequences: New COBOL files must be free-format and must be compiled with `-free`. Do not switch the tree to fixed-form. Do not drop `-free` from the `Makefile` while CI still installs Bookworm `gnucobol`.

## ADR-0003: TSV via libpq

- Status: accepted
- Context: `carolina_query` has to return rows to COBOL. A COBOL alphanumeric field is space-padded and is not a C string. libpq result objects are not something the handler can walk. The handler already walks characters to build JSON.
- Alternatives considered: Embedded SQL cursors into COBOL host variables. Returning libpq's binary format. One JSON document built in C, which would move the contract encoder out of `HANDLE-GET`.
- Decision: `src/pq.c` runs parameterized SQL with `PQexec` / `PQexecParams` and writes TSV (a header line, then rows, tab-separated, trailing NUL). `src/catalog.cob` writes `X"00"` after `FUNCTION TRIM` before the `CALL`. The handler stops a field at NUL or a run of spaces. Postgres `text[]` values arrive as `{php,elixir}` and the handler turns them into JSON arrays.
- Consequences: SQL stays in `src/handler.cob` as text against `v1_*` views. New columns are header cells, not a new FFI struct. `MOVE SPACES` before `STRING INTO` a PIC X field, or leftover characters from a longer previous value stay in the buffer and corrupt JSON. Tabs and newlines inside a cell are flattened to spaces by the trampoline.

## ADR-0004: GnuCOBOL 3.2 in the image and local prefix, Bookworm gnucobol in Gitea CI

- Status: accepted
- Context: The API reports `language_version` `GnuCOBOL 3.2`. The `Dockerfile` downloads `gnucobol-3.2.tar.xz`, checks its digest, and installs that compiler. Local builds prefer the same 3.2 prefix when it is present. Gitea Actions runs on `debian:bookworm-slim` and `apt-get install`s packaged `gnucobol`, which is not the 3.2 tarball.
- Alternatives considered: Installing the 3.2 tarball inside every CI job (slower prepare, a second copy of the digest check). Pinning CI to 3.2 and dropping `-free` once the directive is enough. Reporting the Bookworm package version as `language_version`, which would disagree with the image that actually serves traffic.
- Decision: The image and the local compiler are GnuCOBOL 3.2. Gitea CI keeps Debian Bookworm packaged `gnucobol`. Identity stays `GnuCOBOL 3.2` because that is what the serving binary is built with. CI and local `make` both pass `-free` (ADR-0002). Treat the two compilers as two facts.
- Consequences: Do not collapse the docs or the identity string into one version. A CI-only syntax feature from 3.1, or a 3.2-only feature that Bookworm cannot compile, is a bug. Changing `language_version` requires a superseding entry and a change to `BUILD-IDENTITY` in `src/handler.cob` and the register body in `src/listen6.c`.

## ADR-0005: Talks on year-scoped speaker detail

- Status: accepted
- Context: `GET /v1/speakers/{year}/{slug}` is the year-scoped speaker detail route. Callers need the talks that speaker gave in that year, including `youtube_id`, not only the speaker row plus `languages` and `topics`. Unscoped `GET /v1/speakers/{slug}` stays the speaker row alone.
- Alternatives considered: Omitting talks and letting the client query a talks route this API does not expose. Hanging `talks` off every speaker payload, including the unscoped detail and the list routes. Reading talks from `v1_year_speakers` instead of `v1_talks`.
- Decision: Year-scoped speaker detail includes a `talks` array. `SPEAKER-YEAR-DETAIL` loads the speaker from `v1_speakers`, then loads `v1_talks` for that slug and year, and emits `talks` on the JSON object. An empty talk set for that year is a 404. List routes still attach `languages` and `topics` from `v1_talks`. They do not embed the talk objects.
- Consequences: Handler tests must `CALL` the shipped `HANDLE-GET` with the fake catalog and require a `talks` array on the year-scoped detail. Adding a talk column means extending `TALK-COLS` and the fake catalog together. Do not drop `talks` from this route without a superseding entry.

## ADR-0006: PIC X is not a C string

- Status: accepted
- Context: The trampolines in ADR-0001 and ADR-0003 cross a language boundary. COBOL `PIC X` items are space-padded and have no trailing NUL. C `PQexec`, `PQexecParams`, and `getenv` stop at NUL. `STRING INTO` a `PIC X` item does not clear the tail. If the previous value was longer, leftover characters remain.
- Alternatives considered: Assuming GnuCOBOL passes a NUL-terminated buffer (it does not, for these linkage items). Building every JSON string in C so COBOL never reuses a buffer. Fixed-length records with an explicit length on every `CALL`, which pushes more of the parser into C.
- Decision: COBOL writes `X"00"` after `FUNCTION TRIM` before calling `carolina_query`. `pq.c` writes TSV and a trailing NUL. The handler treats NUL or a run of spaces as the end of a cell. Before every `STRING INTO` a reused `PIC X` field, `MOVE SPACES` to that field. `PROGRAM-ID. HANDLE-GET IS INITIAL` so each `CALL` from the tests resets `WORKING-STORAGE`.
- Consequences: A new buffer that crosses into C needs the same NUL. A new `STRING INTO` of a reused field needs `MOVE SPACES` first. Removing `IS INITIAL` makes row state leak across `/health` and `/v1/speakers` in the handler tests.

## ADR-0007: Bound a dead cached libpq session

- Status: accepted
- Context: `carolina_query` keeps one `PGconn` for the process. Fly suspend freezes the machine and the remote Postgres TCP session dies without an RST. After resume, `PQstatus` still reports `CONNECTION_OK` until a round trip. A blocking `PQexec` then waits on kernel retransmits. The server is one thread, so that wait stalls the data request for many seconds. `GET /health` does not touch the database, so the machine still looks healthy. Retrying after the blocked call returns is too late.
- Alternatives considered: Leaving autosuspend off so a request never wakes a dead socket. That keeps a machine running all the time and does not fix a session that dies for any other reason. Relying on TCP keepalives alone. They do not run while the machine is frozen, and they do not limit the wait once a query is already written. Caching JSON responses in front of Postgres.
- Decision: Each attempt uses the nonblocking libpq calls and waits at most one second (`QUERY_DEADLINE_MS`). On timeout or a lost connection the cached session is closed without blocking and the query runs once more on a new connection. `TCP_USER_TIMEOUT` on the socket is set to that same one second. SQL errors that are not connection failures are still returned without a retry.
- Consequences: A year-scoped data request that wakes a suspended machine pays about one second for the dead session, then a normal query. It must not sit on kernel retransmits. `tests/test_reconnect.c` calls the shipped `carolina_query`, terminates that backend, and also freezes the live TCP session without an RST. Both follow-up calls must return rows in under two seconds. Do not go back to a blocking `PQexec` on the cached connection without a superseding entry.
