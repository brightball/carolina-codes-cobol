/* libpq trampoline for GnuCOBOL CALL. PIC X buffers are not C strings;
   COBOL null-terminates before CALL. A cached connection that dies
   (Fly suspend drops the TCP session) is discarded and the query retried once. */
#include <libpq-fe.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static PGconn *conn = NULL;

static void append(char *out, int *n, int cap, const char *s) {
  size_t L = strlen(s);
  if (*n + (int)L >= cap)
    return;
  memcpy(out + *n, s, L);
  *n += (int)L;
  out[*n] = 0;
}

static void append_cell(char *out, int *n, int cap, const char *s) {
  for (; s && *s; s++) {
    if (*n + 2 >= cap)
      return;
    if (*s == '\t' || *s == '\n' || *s == '\r')
      out[(*n)++] = ' ';
    else
      out[(*n)++] = *s;
  }
  out[*n] = 0;
}

static void close_conn(void) {
  if (conn) {
    PQfinish(conn);
    conn = NULL;
  }
}

static int open_conn(void) {
  const char *dsn;
  char dsnbuf[768];
  size_t L;

  if (conn && PQstatus(conn) != CONNECTION_OK)
    close_conn();
  if (conn)
    return 0;

  dsn = getenv("DATABASE_URL");
  if (!dsn || !dsn[0])
    dsn = "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
  snprintf(dsnbuf, sizeof dsnbuf, "%s", dsn);
  if (!strstr(dsnbuf, "sslmode=")) {
    L = strlen(dsnbuf);
    snprintf(dsnbuf + L, sizeof dsnbuf - L, "%ssslmode=disable", strchr(dsnbuf, '?') ? "&" : "?");
  }
  conn = PQconnectdb(dsnbuf);
  if (PQstatus(conn) != CONNECTION_OK) {
    PQfinish(conn);
    conn = NULL;
    return -1;
  }
  return 0;
}

/* True when the failure is a dead session, not a SQL error we must surface. */
static int connection_lost(PGconn *c, PGresult *res) {
  const char *state;
  if (!c || PQstatus(c) != CONNECTION_OK)
    return 1;
  if (!res)
    return 1;
  if (PQresultStatus(res) != PGRES_FATAL_ERROR)
    return 0;
  state = PQresultErrorField(res, PG_DIAG_SQLSTATE);
  if (!state)
    return 0;
  if (state[0] == '0' && state[1] == '8')
    return 1;
  if (strcmp(state, "57P01") == 0 || strcmp(state, "57P02") == 0 || strcmp(state, "57P03") == 0)
    return 1;
  return 0;
}

static int write_rows(PGresult *res, char *out) {
  int r, f, nt, nf, pos = 0;
  const int cap = 262143;

  nt = PQntuples(res);
  nf = PQnfields(res);
  for (f = 0; f < nf; f++) {
    if (f)
      append(out, &pos, cap, "\t");
    append_cell(out, &pos, cap, PQfname(res, f));
  }
  append(out, &pos, cap, "\n");
  for (r = 0; r < nt; r++) {
    for (f = 0; f < nf; f++) {
      if (f)
        append(out, &pos, cap, "\t");
      if (!PQgetisnull(res, r, f))
        append_cell(out, &pos, cap, PQgetvalue(res, r, f));
    }
    append(out, &pos, cap, "\n");
  }
  return nt;
}

/* carolina_query(sql, arg1, arg2, nargs, outbuf) — outbuf is PIC X large. */
int carolina_query(char *sql, char *a1, char *a2, int *nargs, char *out) {
  const char *vals[2];
  int n = nargs ? *nargs : 0;
  int attempt;
  PGresult *res;

  out[0] = 0;
  if (!sql || !sql[0])
    return 0;

  vals[0] = (n >= 1 && a1 && a1[0]) ? a1 : NULL;
  vals[1] = (n >= 2 && a2 && a2[0]) ? a2 : NULL;

  for (attempt = 0; attempt < 2; attempt++) {
    int lost;
    if (open_conn() != 0)
      return -1;
    if (n <= 0)
      res = PQexec(conn, sql);
    else
      res = PQexecParams(conn, sql, n, NULL, vals, NULL, NULL, 0);
    if (res &&
        (PQresultStatus(res) == PGRES_TUPLES_OK || PQresultStatus(res) == PGRES_COMMAND_OK)) {
      int nt = write_rows(res, out);
      PQclear(res);
      return nt;
    }
    lost = connection_lost(conn, res);
    if (res)
      PQclear(res);
    if (!lost || attempt == 1)
      return -1;
    close_conn();
  }
  return -1;
}
