# carolina-codes-cobol

Read-only v1 polyglot API for Carolina Code Conference. **GnuCOBOL 3.2** sources compiled by `cobc`, served over **POSIX sockets**.

`HANDLE-GET` is the shipped router (`src/handler.cob`). Tests `CALL` that program with a fake `CATALOG-QUERY` — they do not reimplement routing. Live SQL goes through `src/catalog.cob` → `carolina_query` in `src/pq.c` (libpq) against PostgreSQL `v1_*` views.

How this is possible, and what actually happened on this machine, is in [COBOL.md](COBOL.md).

```bash
make test        # HANDLE-GET tests (CALL shipped router, fake catalog)
make sast        # gcc -fanalyzer on C trampolines (pq.c, listen6.c)
make audit       # Trivy filesystem + Dockerfile HIGH/CRITICAL scan
make gitleaks    # secret detection
make lint        # cobc -fsyntax-only -Wall -Wextra and clang-format --dry-run
make check       # all of the above
make hooks       # install local pre-commit hooks
```

Pre-commit runs the same five checks (`local tests`, `static security scanner`, `3rd-party dependency scanner`, `gitleaks`, `lint`). Install once with `make hooks` (needs `pre-commit` on PATH). Emergency skip: `SKIP=local-tests,sast,audit,gitleaks,lint git commit`.

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
