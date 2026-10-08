/* libpq trampoline for GnuCOBOL CALL. PIC X buffers are not C strings;
   COBOL null-terminates before CALL. A cached connection that dies
   (Fly suspend drops the TCP session) is discarded and the query retried once.
   PQstatus stays CONNECTION_OK until a round trip, and the kernel can
   retransmit a dead session for far longer than the site will wait, so each
   attempt is bounded by QUERY_DEADLINE_MS. */
#define _POSIX_C_SOURCE 200809L
#include <libpq-fe.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>

#ifndef TCP_USER_TIMEOUT
#define TCP_USER_TIMEOUT 18
#endif

/* One second: long enough for a live v1_* query, short enough that a dead
   session plus one reconnect still finishes inside a few seconds. */
#define QUERY_DEADLINE_MS 1000

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
  int fd, flags;
  if (!conn)
    return;
  /* PQfinish writes a terminate message. A dead peer must not stall it. */
  fd = PQsocket(conn);
  if (fd >= 0) {
    flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
      fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  }
  PQfinish(conn);
  conn = NULL;
}

static void arm_user_timeout(PGconn *c) {
  int fd = PQsocket(c);
  int ms = QUERY_DEADLINE_MS;
  if (fd < 0)
    return;
  (void)setsockopt(fd, IPPROTO_TCP, TCP_USER_TIMEOUT, &ms, sizeof ms);
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
  arm_user_timeout(conn);
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
    return 1;
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

static long long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Wait until the socket is ready, or until the attempt deadline. */
static int wait_socket(PGconn *c, int for_write, int timeout_ms) {
  struct pollfd pfd;
  int rc;

  pfd.fd = PQsocket(c);
  pfd.events = POLLIN | (for_write ? POLLOUT : 0);
  pfd.revents = 0;
  if (pfd.fd < 0 || timeout_ms < 0)
    return -1;
  rc = poll(&pfd, 1, timeout_ms);
  if (rc <= 0)
    return -1;
  if (pfd.revents & (POLLERR | POLLNVAL))
    return -1;
  return 0;
}

static void drain_results(void) {
  PGresult *extra;
  while ((extra = PQgetResult(conn)) != NULL)
    PQclear(extra);
}

/* Dispatch one query. Returns 0 and sets *out on completion (out may be an
   error result). Returns -1 when the attempt exceeded QUERY_DEADLINE_MS or
   the socket failed; the caller must drop the connection. */
static int exec_bounded(const char *sql, int n, const char **vals, PGresult **out) {
  long long deadline = now_ms() + QUERY_DEADLINE_MS;
  int sent;

  *out = NULL;
  if (PQsetnonblocking(conn, 1) != 0)
    return -1;
  if (n <= 0)
    sent = PQsendQuery(conn, sql);
  else
    sent = PQsendQueryParams(conn, sql, n, NULL, vals, NULL, NULL, 0);
  if (sent != 1)
    return -1;

  for (;;) {
    int left = (int)(deadline - now_ms());
    int flushing;
    if (left <= 0)
      return -1;
    flushing = PQflush(conn);
    if (flushing < 0)
      return -1;
    if (flushing == 0 && !PQisBusy(conn))
      break;
    if (wait_socket(conn, flushing == 1, left) != 0)
      return -1;
    if (PQconsumeInput(conn) != 1)
      return -1;
  }
  *out = PQgetResult(conn);
  drain_results();
  return 0;
}

/* carolina_query(sql, arg1, arg2, nargs, outbuf) — outbuf is PIC X large. */
int carolina_query(char *sql, char *a1, char *a2, int *nargs, char *out) {
  const char *vals[2];
  int n = nargs ? *nargs : 0;
  int attempt;
  PGresult *res = NULL;

  out[0] = 0;
  if (!sql || !sql[0])
    return 0;

  vals[0] = (n >= 1 && a1 && a1[0]) ? a1 : NULL;
  vals[1] = (n >= 2 && a2 && a2[0]) ? a2 : NULL;

  for (attempt = 0; attempt < 2; attempt++) {
    int lost;
    if (open_conn() != 0)
      return -1;
    if (exec_bounded(sql, n, vals, &res) != 0) {
      if (res)
        PQclear(res);
      close_conn();
      if (attempt == 1)
        return -1;
      continue;
    }
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
