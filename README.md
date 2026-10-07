# carolina-codes-cobol

Read-only v1 polyglot API for Carolina Code Conference.

## Runtime

`GET /` reports the versions this process actually serves:

- Language version: **GnuCOBOL 3.2** (`language_version`). Sources are free-format GnuCOBOL, compiled by `cobc`.
- Framework: **POSIX sockets**. POSIX sockets have no package version. This API does not invent a framework semver.
- API version string: `0.2.0`.

Notable packages added for this stack:

- **libpq** — parameterized queries through `src/pq.c` (`libpq-dev` at build, `libpq5` in the image).
- **libgmp** — GnuCOBOL runtime library. The image installs `libgmp10`. The build stage installs `libgmp-dev`. `libcob` links it.

The image and a local GnuCOBOL 3.2 prefix are built from the GNU 3.2 tarball. Gitea CI installs Debian Bookworm packaged `gnucobol` and compiles with `make`, which passes `-free`. Those are two compilers. Identity stays GnuCOBOL 3.2 because that is what the image serves.

`HANDLE-GET` is the shipped router (`src/handler.cob`). Tests `CALL` that program with a fake `CATALOG-QUERY`. They do not reimplement routing. Live SQL goes through `src/catalog.cob` to `carolina_query` in `src/pq.c` (libpq) and returns TSV from PostgreSQL `v1_*` views.

How the FFI works, and what happened while bringing the compiler up, is in [COBOL.md](COBOL.md). Decisions are in [DECISIONS.md](DECISIONS.md). The current-state index is [MEMORY.md](MEMORY.md). Agent rules are in [AGENTS.md](AGENTS.md).

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

`GET /` reports `language: "COBOL"` and `framework: "POSIX sockets"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. The local listen fallback is port **4027**. The container image sets `PORT=8080`.

GnuCOBOL for local builds is expected at `$HOME/.local/opt/gnucobol-3.2` (see COBOL.md). `bin/server` puts that prefix on `PATH` / `LD_LIBRARY_PATH` when the prefix exists. Otherwise `make` uses `cobc` on `PATH`.
