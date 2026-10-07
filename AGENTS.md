# carolina-codes-cobol

Agent entry point for this read-only v1 HTTP API. Install, run, and test commands are in `README.md`. What is true right now is indexed in `MEMORY.md`. Why those choices were made is in `DECISIONS.md`.

Read `MEMORY.md` and `DECISIONS.md` before changing behavior. When a durable decision changes, update both files in the same change: add a `DECISIONS.md` entry (or supersede an accepted one) and refresh the `MEMORY.md` index. An accepted entry stays binding until a later entry supersedes it. `COBOL.md` is the compile diary and the FFI walkthrough. It is not the decision log.

## Workspace

This repository is the workspace root. It is one sibling git remote in the carolina.codes polyglot fleet. The Phoenix CMS is a different remote (`github.com/brightball/carolina-codes`). Do not assume `../elixir` or other sibling directories exist unless those remotes are attached to the same environment. Do not fold this tree into the CMS git remote.

The source of truth for routes and payloads is the CMS contract (`priv/api/openapi.yaml` and `priv/api/AGENTS.md` on that remote). This tree does not vendor `openapi.yaml`. Speak ordinary JSON for the OpenAPI routes, not Ash JSON:API (`application/vnd.api+json`).

You do not need a checkout of the Elixir CMS to build or test this API. Registration is best-effort.

## Purpose

The Phoenix app (`Carolina.Polyglot`) keeps at most one language API warm and reads speakers and sponsors from it. With no APIs registered, it falls back to Ash. This process must:

1. Query Postgres `v1_*` views only, never Ash tables.
2. Expose the OpenAPI routes as ordinary JSON. Wrap list payloads as `{ "data": [ ... ] }`.
3. Register once on boot and keep serving if the CMS is down (no heartbeat).

`GET /health` returns `{"status":"ok"}` and does not touch the database. Year-scoped speaker detail (`GET /v1/speakers/{year}/{slug}`) includes a `talks` array.

## SQL views (query these)

`v1_speakers`, `v1_sponsors`, `v1_years`, `v1_talks`, `v1_sponsorships`, `v1_year_speakers`, `v1_year_sponsors`.

The views live in the CMS database. Do not `SELECT` from `speakers`, `organizations`, `talks`, or other Ash base tables. The views are the API.

Year-scoped speaker listing rows include `languages` and `topics` from `v1_talks`. Year-scoped sponsor rows include `tier`. `photo_path` and `logo_path` are web paths. Return the path. The CMS hosts the bytes.

## Required HTTP routes

- `GET /health` — liveness (`{ "status": "ok" }`). Does not touch the database.
- `GET /` — identity (`language`, `language_version`, `framework`, `api_version`, endpoints)
- `GET /v1/years`
- `GET /v1/speakers` and `GET /v1/speakers?year=`
- `GET /v1/speakers/{slug}` and `GET /v1/speakers/{year}/{slug}` (year-scoped detail includes `talks`)
- `GET /v1/sponsors` and `GET /v1/sponsors?year=`
- `GET /v1/sponsors/{slug}` and `GET /v1/sponsors/{year}/{slug}`

Unknown slugs return 404 with `{"error":"not_found"}`. No writes.

## Register on boot (once)

`POST {CAROLINA_URL}/internal/api-endpoints/register`

```
Authorization: Bearer {POLYGLOT_REGISTER_TOKEN}
Content-Type: application/json
```

Body fields: `language`, `language_version`, `api_version`, `framework`, `created_year`, `base_url` (`PUBLIC_BASE_URL`), `schema_version` (1), `endpoints` (list of GET paths).

Register once on boot. Do not heartbeat. Elixir keep-alives the currently warm API. If `CAROLINA_URL` is empty or the POST fails, log and keep serving. `carolina_register_async` in `src/listen6.c` runs that POST off the accept path so a down CMS does not delay `GET /health`.

## COBOL runtime

Identity is language COBOL and framework POSIX sockets. `GET /` reports `language_version` `GnuCOBOL 3.2`. POSIX sockets have no framework package version. Do not invent one.

Sources are free-format GnuCOBOL (`-free`, and `>>SOURCE FORMAT FREE` in each program). `cobc` compiles COBOL to C, then to a native binary. `CALL "name"` is the FFI.

Live SQL and listening go through the C trampolines (libpq and dual-stack listen), not embedded SQL and not a copy of another sibling's server.

- `src/server.cob` parses the GET target and writes `HTTP/1.1` plus `Content-Length`.
- `src/handler.cob` is `HANDLE-GET`: routing and JSON.
- `src/catalog.cob` null-terminates PIC X buffers and `CALL`s `carolina_query`.
- `src/pq.c` runs parameterized libpq queries and writes TSV.
- `src/listen6.c` is the dual-stack listen (`IPV6_V6ONLY=0` on `[::]`, IPv4 fallback) and the one-shot register client.

Handler tests call the shipped router with a fake catalog. `make test` compiles `tests/test.cob` with `src/handler.cob` and `src/catalog-fake.cob` (same `PROGRAM-ID. CATALOG-QUERY`) and `CALL`s `HANDLE-GET`. Those tests do not need Postgres.

The image and the local compiler are GnuCOBOL 3.2, built from the GNU 3.2 tarball. Gitea CI installs Debian Bookworm packaged `gnucobol` and compiles with `make`, which passes `-free`. Those are two compiler facts. See `DECISIONS.md`.

Notable packages: libpq (queries) and libgmp (GnuCOBOL runtime library; the image installs `libgmp10`).

## Environment

| Variable | Example | Role |
|---|---|---|
| `DATABASE_URL` | `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev` | SQL views |
| `CAROLINA_URL` | `http://127.0.0.1:4000` | Elixir site (optional; register no-ops if down) |
| `POLYGLOT_REGISTER_TOKEN` | `dev` | Bearer token for register |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:4027` | URL Elixir will call |
| `PORT` | `4027` | Listen port |

Local `src/listen6.c` falls back to port 4027. The container image sets `PORT=8080`. Handler tests that use the fake catalog do not need Postgres. Live HTTP against the views needs Postgres 16 and `DATABASE_URL`.

## Local gates

Local gates are `make test`, `sast`, `audit`, `gitleaks`, and `lint`. `make check` runs them. Pre-commit runs the same five. `python3 tests/test_agent_docs.py` checks this file, `README.md`, `MEMORY.md`, and `DECISIONS.md`.

## Layout

| Path | Role |
|---|---|
| `src/handler.cob` | `HANDLE-GET` router and JSON |
| `src/server.cob` | HTTP parse and respond |
| `src/catalog.cob` | Live `CATALOG-QUERY` to libpq |
| `src/catalog-fake.cob` | Test `CATALOG-QUERY` |
| `src/pq.c` | `carolina_query` (libpq, TSV) |
| `src/listen6.c` | Dual-stack listen and one-shot register |
| `tests/test.cob` | `CALL` the shipped handler |
| `MEMORY.md` | Current-state index |
| `DECISIONS.md` | Decision log |
| `COBOL.md` | FFI walkthrough and compile diary |
| `Dockerfile` | GnuCOBOL 3.2 image |
| `fly.toml` | Fly.io app config |

## Checklist

- OpenAPI paths return ordinary JSON (404 on unknown slug)
- `?year=` listing rows include `languages` / `topics` (speakers) and `tier` (sponsors)
- Year-scoped speaker detail includes a `talks` array
- Register once at process start; keep serving if the CMS is down; no heartbeat
- No writes; query `v1_*` views only, never Ash tables
- `GET /health` does not touch the database
