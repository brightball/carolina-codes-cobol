# Serving HTTP and Postgres from COBOL

This sibling is a real GnuCOBOL program, not a relabel of `c/` or `cpp/` and not a Python wrapper. Identity is `language: COBOL`, `framework: POSIX sockets`. This page is both the “how is that possible?” answer and a log of compiling it here.

## How it is possible

COBOL the language has no sockets and no libpq. **GnuCOBOL (`cobc`) compiles COBOL to C**, then to a native binary, and `CALL "name"` is the FFI. That is the whole trick.

```
GET request
    → server.cob parses the target (method, path, ?year=)
    → CALL "HANDLE-GET" USING path year status body
    → HANDLE-GET CALLs "CATALOG-QUERY" with SQL + $1/$2
    → catalog.cob null-terminates PIC X buffers and CALLs carolina_query
    → pq.c runs PQexec / PQexecParams and writes TSV
    → HANDLE-GET parses TSV and writes JSON into the body
    → server.cob writes HTTP/1.1 + Content-Length
```

Tests skip the listen: they compile `handler.cob` with `catalog-fake.cob` (same `PROGRAM-ID. CATALOG-QUERY`) and `CALL "HANDLE-GET"` directly. That is the shipped router, not a second implementation.

### PIC X is not a C string

A COBOL alphanumeric field is space-padded and has no trailing NUL. C `PQexec` and `getenv` need NULs. `catalog.cob` writes `X"00"` after `FUNCTION TRIM` before the libpq trampoline. `pq.c` writes TSV plus a trailing NUL; the handler stops a parse at NUL or a run of spaces.

`STRING INTO` a PIC X field does **not** clear the remainder. If the previous value was longer, leftover characters stay. That bit us on live data (see below).

### Why TSV, not a COBOL SQL precompiler

Embedded SQL (ocesql / GixSQL) would be a second toolchain. libpq is already on this host (`/usr/include/libpq-fe.h`, `/usr/lib/libpq.so`). A small C trampoline (`carolina_query`) runs parameterized SQL and returns tab-separated rows with a header line. COBOL already knows how to walk characters. Year-scoped speaker `languages` / `topics` come from a second query against `v1_talks`, not `v1_year_speakers`. Postgres `text[]` shows up as `{php,elixir}`; the handler turns that into `["php","elixir"]`.

### Listen: COBOL CALL, sockaddr in C

GnuCOBOL can `CALL "socket"` / `bind` / `listen`. `struct sockaddr_in6` is 28 bytes with `htons` on the port and `IPV6_V6ONLY=0` for dual-stack `[::]`. Getting that layout wrong in COBOL `PIC` fields binds garbage and fails silently. After a smoke test proved a 40-line C trampoline (`src/listen6.c`: `carolina_listen` / `accept` / `recv` / `send` / `close`) works, that is what the server uses. Request parse, routing, and JSON stay COBOL.

Register is the same file: one `POST {CAROLINA_URL}/internal/api-endpoints/register` at process start (no heartbeat). Writing a second HTTP client in COBOL was not worth it.

### Tests isolate WORKING-STORAGE

`PROGRAM-ID. HANDLE-GET IS INITIAL.` so each `CALL` resets tables. Without `IS INITIAL`, `RN` / TSV cells leak across `/health` and `/v1/speakers`.

## Experience on this machine

### Compiler was not on PATH

`cobc` was missing. GnuCOBOL **3.2.0** was built from
`https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz` into
`$HOME/.local/opt/gnucobol-3.2`.

```
export PATH="$HOME/.local/opt/gnucobol-3.2/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/opt/gnucobol-3.2/lib"
```

Configure used `--without-db --without-curses --disable-rpath`. This API does not need indexed files or a TTY. Berkeley DB is not installed here.

### GCC 16 vs GnuCOBOL 3.2

First `./configure && make` against **GCC 16.2.1** died in `libcob`:

- `call.c` / `common.c`: `-Wincompatible-pointer-types` (C23 / GCC 14+ treat these as errors; GnuCOBOL 3.2 is C89-style function pointers)
- `xmlCleanupParser` implicit declaration (libxml2 2.14)

Rebuild with:

```
CFLAGS="-O2 -pipe -std=gnu17 -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion"
```

After that, `cobc (GnuCOBOL) 3.2.0` and a hello program printed `hello from gnucobol`. The Dockerfile uses the same CFLAGS so a bookworm GCC 12 build still works if a newer compiler shows up.

### What compiled, what hurt

1. **Smoke:** two COBOL programs + C listen, `CALL "HANDLE-GET"`, `IS INITIAL`, bind `[::]:18080`. Worked.
2. **`CELL` / `CELLS` are reserved** (screen section). Two-dimensional `OCCURS 64 TIMES 24 TIMES` is not accepted. Nested groups (`SP-ROW OCCURS 64` / `SP-CELL OCCURS 24`) compile. Indexes are `SP-CELL(row, col)`.
3. **Fake catalog over-matched** `v1_speakers WHERE slug` — the year-scoped list SQL is `WHERE slug IN (SELECT … FROM v1_talks)`. That looked like a detail query, ARG1 was `"2026"`, not `diana-pham`, so tests got `{"data":[]}`. Match `WHERE slug =` for detail.
4. **Live JSON was invalid** until `MOVE SPACES TO FIELD-JSON` before every `STRING INTO`. Years rendered as `"year":2025ast` because `"status":"past"` leftover `ast"` sat in the buffer. Classic COBOL, invisible until `carolina_dev` had more than one row.
5. **Handler tests** (`make test`) drive `HANDLE-GET`: `/health` JSON with `"status"` and `"ok"`, 404 unknown slug, year-scoped speakers include `languages`/`topics` from `v1_talks`, year-scoped sponsors include `tier`. Passed after (3).
6. **Two live launches on :4027** with the AGENTS.md env vars. Each run: register `200` against Phoenix `:4000`, `GET /health` → `{"status":"ok"}`, `GET /` → COBOL + POSIX sockets, `GET /v1/speakers?year=2026` → 27 rows with `languages`/`topics`, `GET /v1/sponsors?year=2026` → 29 rows with `tier`.
7. **`OCCURS 64` dropped speakers.** `carolina_dev` has 94 `v1_speakers` rows (and 64 sponsors, so the cap was already tight). `PARSE-TSV` did `ADD 1 TO RN` then `IF RN > 64 EXIT PERFORM`, so RN became 65 and `EMIT-ROW-TO-BUF` indexed `SP-CELL(65)` past the table. Tables are `OCCURS 256` (`SP-CAP` / `TK-CAP`); the guard is now `IF RN >= SP-CAP EXIT` **before** incrementing. Tests `CALL "HANDLE-GET"` on `/v1/speakers` with 80 fake rows and require at least 65 `"slug"` hits.

### Layout

| File | Role |
|---|---|
| `src/handler.cob` | `HANDLE-GET` router + JSON |
| `src/catalog.cob` | live `CATALOG-QUERY` → libpq |
| `src/catalog-fake.cob` | test `CATALOG-QUERY` |
| `src/server.cob` | HTTP parse / respond |
| `src/pq.c` | `carolina_query` |
| `src/listen6.c` | dual-stack listen + register POST |
| `tests/test.cob` | CALL the shipped handler |

Not used: Micro Focus, CICS/IMS, Apache CGI, cobol-wrap, or any copy of the C sibling’s server.

Listen port is **4027**. Fleet wiring (`ALL_APIS`, Fly `carolina-codes-cobol.fly.dev`) is valid only because `/health` actually served.
