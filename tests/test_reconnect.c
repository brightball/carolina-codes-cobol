/* Drive shipped carolina_query: succeed, terminate that backend, query again,
   then freeze the live TCP session (no RST, the Fly-suspend failure) and
   require the next call to return rows in under 2 seconds. */
#define _POSIX_C_SOURCE 200809L
#include <libpq-fe.h>
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int carolina_query(char *sql, char *a1, char *a2, int *nargs, char *out);

static pid_t proxy_pid = -1;

static int fail(const char *msg) {
  fprintf(stderr, "FAIL: %s\n", msg);
  if (proxy_pid > 0)
    kill(proxy_pid, SIGTERM);
  return 1;
}

static void on_alarm(int sig) {
  (void)sig;
  fprintf(stderr, "FAIL: carolina_query still blocked after 5s\n");
  if (proxy_pid > 0)
    kill(proxy_pid, SIGTERM);
  _exit(1);
}

static double mono_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
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

static int copy_fd(int src, int dst) {
  char buf[8192];
  ssize_t n, off = 0;

  n = read(src, buf, sizeof buf);
  if (n == 0)
    return -1;
  if (n < 0)
    return (errno == EINTR) ? 0 : -1;
  while (off < n) {
    ssize_t w = write(dst, buf + off, (size_t)(n - off));
    if (w < 0) {
      if (errno == EINTR)
        continue;
      return -1;
    }
    off += w;
  }
  return 1;
}

/* Hold the accepted sockets open and stop reading once *freeze is set.
   That is a silent peer: the query is not RST'd, which is what suspend does
   to a cached libpq session. */
static void splicer(int client_fd, int server_fd, int *freeze, int live) {
  /* live sessions were accepted after the freeze and must keep forwarding.
     Older sessions stop reading so the cached libpq socket goes half-open. */
  while (live || !*freeze) {
    struct pollfd pfd[2];
    int rc;

    pfd[0].fd = client_fd;
    pfd[0].events = POLLIN;
    pfd[0].revents = 0;
    pfd[1].fd = server_fd;
    pfd[1].events = POLLIN;
    pfd[1].revents = 0;
    rc = poll(pfd, 2, 100);
    if (!live && *freeze)
      break;
    if (rc < 0) {
      if (errno == EINTR)
        continue;
      break;
    }
    if (rc == 0)
      continue;
    if ((pfd[0].revents & (POLLERR | POLLNVAL)) || (pfd[1].revents & (POLLERR | POLLNVAL)))
      break;
    if ((pfd[0].revents & POLLIN) && copy_fd(client_fd, server_fd) < 0)
      break;
    if ((pfd[1].revents & POLLIN) && copy_fd(server_fd, client_fd) < 0)
      break;
    if ((pfd[0].revents & POLLHUP) || (pfd[1].revents & POLLHUP))
      break;
  }
  if (!live && *freeze) {
    for (;;)
      pause();
  }
  close(client_fd);
  close(server_fd);
  _exit(0);
}

static void proxy_main(int listen_fd, int *freeze) {
  signal(SIGCHLD, SIG_IGN);
  for (;;) {
    struct sockaddr_in peer, up;
    socklen_t plen = sizeof peer;
    int client_fd, server_fd;
    pid_t kid;

    client_fd = accept(listen_fd, (struct sockaddr *)&peer, &plen);
    if (client_fd < 0) {
      if (errno == EINTR)
        continue;
      _exit(1);
    }
    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    memset(&up, 0, sizeof up);
    up.sin_family = AF_INET;
    up.sin_port = htons(5432);
    up.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (server_fd < 0 || connect(server_fd, (struct sockaddr *)&up, sizeof up) != 0) {
      close(client_fd);
      if (server_fd >= 0)
        close(server_fd);
      continue;
    }
    kid = fork();
    if (kid < 0) {
      close(client_fd);
      close(server_fd);
      continue;
    }
    if (kid == 0) {
      int live = *freeze;
      close(listen_fd);
      splicer(client_fd, server_fd, freeze, live);
    }
    close(client_fd);
    close(server_fd);
  }
}

static int start_proxy(int *port, int **freeze) {
  int listen_fd, on = 1;
  struct sockaddr_in addr;
  socklen_t len = sizeof addr;
  pid_t pid;
  int *flag;

  flag = mmap(NULL, sizeof *flag, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  if (flag == MAP_FAILED)
    return -1;
  *flag = 0;
  listen_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (listen_fd < 0)
    return -1;
  setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
  memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  addr.sin_port = 0;
  if (bind(listen_fd, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(listen_fd, 16) != 0)
    return -1;
  if (getsockname(listen_fd, (struct sockaddr *)&addr, &len) != 0)
    return -1;
  *port = ntohs(addr.sin_port);
  pid = fork();
  if (pid < 0)
    return -1;
  if (pid == 0) {
    proxy_main(listen_fd, flag);
    _exit(0);
  }
  close(listen_fd);
  proxy_pid = pid;
  *freeze = flag;
  return 0;
}

static int timed_query(char *out, int *pid, double *elapsed) {
  char arg1[4] = {0};
  char arg2[4] = {0};
  int nargs = 0;
  int rows;
  double t0 = mono_seconds();

  alarm(5);
  rows = carolina_query("SELECT pg_backend_pid() AS pid", arg1, arg2, &nargs, out);
  alarm(0);
  *elapsed = mono_seconds() - t0;
  if (rows < 1)
    return -1;
  if (parse_pid(out, pid) != 0)
    return -2;
  return rows;
}

int main(void) {
  char out[262144];
  char arg1[4] = {0};
  char arg2[4] = {0};
  int nargs = 0;
  int rows, pid1 = 0, pid2 = 0, pid3 = 0;
  int proxy_port = 0;
  int *freeze = NULL;
  char dsn[768];
  char admin_dsn[768];
  char term[96];
  const char *db;
  PGconn *admin;
  PGresult *res;
  double elapsed = 0;
  struct timespec settle = {0, 300000000};

  setvbuf(stdout, NULL, _IONBF, 0);
  signal(SIGALRM, on_alarm);
  signal(SIGPIPE, SIG_IGN);

  db = getenv("CAROLINA_RECONNECT_DB");
  if (!db || !db[0])
    db = "postgres";
  if (start_proxy(&proxy_port, &freeze) != 0)
    return fail("start blackhole proxy");
  snprintf(dsn, sizeof dsn,
           "postgres://postgres:postgres@127.0.0.1:%d/%s"
           "?sslmode=disable&application_name=carolina_cobol_reconn",
           proxy_port, db);
  snprintf(admin_dsn, sizeof admin_dsn,
           "postgres://postgres:postgres@127.0.0.1:5432/%s"
           "?sslmode=disable&application_name=carolina_cobol_reconn_admin",
           db);
  if (setenv("DATABASE_URL", dsn, 1) != 0)
    return fail("setenv DATABASE_URL");

  rows = carolina_query("SELECT pg_backend_pid() AS pid", arg1, arg2, &nargs, out);
  if (rows < 1) {
    fprintf(stderr, "FAIL: first query returned no rows (%s)\n", out);
    return fail("first query");
  }
  if (parse_pid(out, &pid1) != 0)
    return fail("first query did not return a backend pid");
  printf("ok: first query backend %d via proxy %d\n", pid1, proxy_port);

  admin = PQconnectdb(admin_dsn);
  if (PQstatus(admin) != CONNECTION_OK) {
    fprintf(stderr, "FAIL: admin connect %s\n", PQerrorMessage(admin));
    PQfinish(admin);
    return fail("admin connect");
  }
  snprintf(term, sizeof term, "SELECT pg_terminate_backend(%d)", pid1);
  res = PQexec(admin, term);
  if (!res || PQresultStatus(res) != PGRES_TUPLES_OK) {
    fprintf(stderr, "FAIL: terminate backend %d: %s\n", pid1, PQerrorMessage(admin));
    if (res)
      PQclear(res);
    PQfinish(admin);
    return fail("terminate");
  }
  PQclear(res);
  if (backend_gone(admin, pid1) != 0) {
    PQfinish(admin);
    return fail("terminated backend still listed");
  }
  PQfinish(admin);

  if (timed_query(out, &pid2, &elapsed) < 1) {
    fprintf(stderr, "FAIL: second query returned no rows after %.3fs (%s)\n", elapsed, out);
    return fail("second query");
  }
  printf("ok: reconnected backend %d -> %d in %.3fs\n", pid1, pid2, elapsed);
  if (pid2 == pid1)
    return fail("second query reused the terminated backend");
  if (elapsed >= 2.0)
    return fail("post-terminate carolina_query took 2 seconds or longer");

  *freeze = 1;
  nanosleep(&settle, NULL);
  if (timed_query(out, &pid3, &elapsed) < 1) {
    fprintf(stderr, "FAIL: blackhole query returned no rows after %.3fs (%s)\n", elapsed, out);
    return fail("blackhole query");
  }
  printf("ok: half-open session recovered %d -> %d in %.3fs\n", pid2, pid3, elapsed);
  if (pid3 == pid2)
    return fail("blackhole query reused the frozen backend");
  if (elapsed >= 2.0)
    return fail("half-open carolina_query took 2 seconds or longer");
  printf("reconnect test passed\n");
  kill(proxy_pid, SIGTERM);
  waitpid(proxy_pid, NULL, 0);
  return 0;
}
