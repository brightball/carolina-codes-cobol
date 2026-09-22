/* Drive shipped carolina_query: succeed, terminate that backend, query again. */
#define _POSIX_C_SOURCE 200809L
#include <libpq-fe.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

int carolina_query(char *sql, char *a1, char *a2, int *nargs, char *out);

static int fail(const char *msg) {
  fprintf(stderr, "FAIL: %s\n", msg);
  return 1;
}

static int parse_pid(const char *tsv, int *pid) {
  const char *line;
  char *end;
  long value;

  line = strchr(tsv, '\n');
  if (!line || line[1] == '\0')
    return -1;
  value = strtol(line + 1, &end, 10);
  if (end == line + 1 || value <= 0)
    return -1;
  *pid = (int)value;
  return 0;
}

static int backend_gone(PGconn *admin, int pid) {
  char query[128];
  PGresult *res;
  int gone = 0;
  int i;

  snprintf(query, sizeof query, "SELECT 1 FROM pg_stat_activity WHERE pid = %d", pid);
  for (i = 0; i < 50; i++) {
    res = PQexec(admin, query);
    if (res && PQresultStatus(res) == PGRES_TUPLES_OK && PQntuples(res) == 0)
      gone = 1;
    if (res)
      PQclear(res);
    if (gone)
      return 0;
    {
      struct timespec pause = {0, 20000000};
      nanosleep(&pause, NULL);
    }
  }
  return -1;
}

int main(void) {
  char out[262144];
  char arg1[4] = {0};
  char arg2[4] = {0};
  int nargs = 0;
  int rows, pid1 = 0, pid2 = 0;
  char dsn[768];
  char admin_dsn[768];
  char term[96];
  const char *db;
  PGconn *admin;
  PGresult *res;

  db = getenv("CAROLINA_RECONNECT_DB");
  if (!db || !db[0])
    db = "postgres";
  snprintf(dsn, sizeof dsn,
           "postgres://postgres:postgres@127.0.0.1:5432/%s"
           "?sslmode=disable&application_name=carolina_cobol_reconn",
           db);
  snprintf(admin_dsn, sizeof admin_dsn,
           "postgres://postgres:postgres@127.0.0.1:5432/%s"
           "?sslmode=disable&application_name=carolina_cobol_reconn_admin",
           db);
  if (setenv("DATABASE_URL", dsn, 1) != 0)
    return fail("setenv DATABASE_URL");

  rows = carolina_query("SELECT pg_backend_pid() AS pid", arg1, arg2, &nargs, out);
  if (rows < 1) {
    fprintf(stderr, "FAIL: first query returned no rows (%s)\n", out);
    return 1;
  }
  if (parse_pid(out, &pid1) != 0)
    return fail("first query did not return a backend pid");
  printf("ok: first query backend %d\n", pid1);

  admin = PQconnectdb(admin_dsn);
  if (PQstatus(admin) != CONNECTION_OK) {
    fprintf(stderr, "FAIL: admin connect %s\n", PQerrorMessage(admin));
    PQfinish(admin);
    return 1;
  }
  snprintf(term, sizeof term, "SELECT pg_terminate_backend(%d)", pid1);
  res = PQexec(admin, term);
  if (!res || PQresultStatus(res) != PGRES_TUPLES_OK) {
    fprintf(stderr, "FAIL: terminate backend %d: %s\n", pid1, PQerrorMessage(admin));
    if (res)
      PQclear(res);
    PQfinish(admin);
    return 1;
  }
  PQclear(res);
  if (backend_gone(admin, pid1) != 0) {
    PQfinish(admin);
    return fail("terminated backend still listed");
  }
  PQfinish(admin);

  rows = carolina_query("SELECT pg_backend_pid() AS pid", arg1, arg2, &nargs, out);
  if (rows < 1) {
    fprintf(stderr, "FAIL: second query returned no rows (%s)\n", out);
    return 1;
  }
  if (parse_pid(out, &pid2) != 0)
    return fail("second query did not return a backend pid");
  if (pid2 == pid1)
    return fail("second query reused the terminated backend");
  printf("ok: reconnected backend %d -> %d\n", pid1, pid2);
  printf("reconnect test passed\n");
  return 0;
}
