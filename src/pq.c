/* libpq trampoline for GnuCOBOL CALL. PIC X buffers are not C strings;
   COBOL null-terminates before CALL. */
#include <libpq-fe.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/* carolina_query(sql, arg1, arg2, nargs, outbuf) — outbuf is PIC X large. */
int carolina_query(char *sql, char *a1, char *a2, int *nargs, char *out) {
  static PGconn *conn = NULL;
  static int connect_count = 0;
  const char *vals[2];
  int n = nargs ? *nargs : 0;
  PGresult *res;
  int r, f, nt, nf, pos = 0;
  const int cap = 262143;

  out[0] = 0;
  if (!sql || !sql[0])
    return 0;

  if (!conn) {
    const char *dsn = getenv("DATABASE_URL");
    char dsnbuf[768];
    if (!dsn || !dsn[0])
      dsn = "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
    snprintf(dsnbuf, sizeof dsnbuf, "%s", dsn);
    if (!strstr(dsnbuf, "sslmode=")) {
      size_t L = strlen(dsnbuf);
      snprintf(dsnbuf + L, sizeof dsnbuf - L, "%ssslmode=disable", strchr(dsnbuf, '?') ? "&" : "?");
    }
    connect_count++;
    conn = PQconnectdb(dsnbuf);
    if (PQstatus(conn) != CONNECTION_OK) {
      PQfinish(conn);
      conn = NULL;
      return -1;
    }
  }

  vals[0] = (n >= 1 && a1 && a1[0]) ? a1 : NULL;
  vals[1] = (n >= 2 && a2 && a2[0]) ? a2 : NULL;
  if (n <= 0)
    res = PQexec(conn, sql);
  else
    res = PQexecParams(conn, sql, n, NULL, vals, NULL, NULL, 0);

  if (!res || (PQresultStatus(res) != PGRES_TUPLES_OK && PQresultStatus(res) != PGRES_COMMAND_OK)) {
    if (res)
      PQclear(res);
    return -1;
  }
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
  PQclear(res);
  (void)connect_count;
  return nt;
}
