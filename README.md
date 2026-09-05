# carolina-codes-cobol

Read-only v1 polyglot API for Carolina Code Conference. **GnuCOBOL 3.2** sources compiled by `cobc`, served over **POSIX sockets**.

`HANDLE-GET` is the shipped router (`src/handler.cob`). Tests `CALL` that program with a fake `CATALOG-QUERY` — they do not reimplement routing. Live SQL goes through `src/catalog.cob` → `carolina_query` in `src/pq.c` (libpq) against PostgreSQL `v1_*` views.

How this is possible, and what actually happened on this machine, is in [COBOL.md](COBOL.md).

```bash
make test
```

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4027 \
PORT=4027 \
./bin/server
```

`GET /` reports `language: "COBOL"` and `framework: "POSIX sockets"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. Listen port is **4027**.

GnuCOBOL is expected at `$HOME/.local/opt/gnucobol-3.2` (see COBOL.md). `bin/server` puts that prefix on `PATH` / `LD_LIBRARY_PATH`.
