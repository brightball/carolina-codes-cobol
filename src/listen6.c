/* Dual-stack listen + tiny HTTP client for one-shot register.
   sockaddr_in6 packing is left in C so COBOL does not have to match
   Linux padding / htons. Request parse and HANDLE-GET stay COBOL. */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int env_int(const char *name, int fallback) {
  const char *v = getenv(name);
  if (!v || !v[0]) return fallback;
  return atoi(v);
}

void carolina_listen(int *port, int *fd) {
  int p = (port && *port > 0) ? *port : env_int("PORT", 4027);
  int s, on = 1, off = 0;
  struct sockaddr_in6 a;
  *fd = -1;
  s = socket(AF_INET6, SOCK_STREAM, 0);
  if (s < 0) {
    fprintf(stderr, "socket: %s\n", strerror(errno));
    return;
  }
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
  setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &off, sizeof off);
  memset(&a, 0, sizeof a);
  a.sin6_family = AF_INET6;
  a.sin6_port = htons((unsigned short)p);
  a.sin6_addr = in6addr_any;
  if (bind(s, (struct sockaddr *)&a, sizeof a) != 0) {
    fprintf(stderr, "bind [::]:%d: %s\n", p, strerror(errno));
    close(s);
    return;
  }
  if (listen(s, 16) != 0) {
    fprintf(stderr, "listen: %s\n", strerror(errno));
    close(s);
    return;
  }
  if (port) *port = p;
  *fd = s;
  fprintf(stdout, "carolina-codes-cobol listening on [::]:%d\n", p);
  fflush(stdout);
}

void carolina_accept(int *listen_fd, int *client_fd) {
  int c;
  *client_fd = -1;
  if (!listen_fd || *listen_fd < 0) return;
  c = accept(*listen_fd, NULL, NULL);
  if (c < 0) {
    fprintf(stderr, "accept: %s\n", strerror(errno));
    return;
  }
  *client_fd = c;
}

void carolina_recv(int *fd, char *buf, int *cap, int *n) {
  int got = 0, c = cap ? *cap : 0;
  *n = 0;
  if (!fd || *fd < 0 || !buf || c <= 0) return;
  while (got < c - 1) {
    int k = (int)recv(*fd, buf + got, (size_t)(c - 1 - got), 0);
    if (k < 0) {
      if (errno == EINTR) continue;
      break;
    }
    if (k == 0) break;
    got += k;
    buf[got] = 0;
    if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n")) break;
  }
  buf[got] = 0;
  *n = got;
}

void carolina_send(int *fd, char *buf, int *n, int *sent) {
  int left = n ? *n : 0;
  int off = 0;
  *sent = 0;
  if (!fd || *fd < 0 || !buf) return;
  while (off < left) {
    int k = (int)send(*fd, buf + off, (size_t)(left - off), 0);
    if (k < 0) {
      if (errno == EINTR) continue;
      return;
    }
    if (k == 0) return;
    off += k;
  }
  *sent = off;
}

void carolina_close(int *fd) {
  if (fd && *fd >= 0) {
    close(*fd);
    *fd = -1;
  }
}

static void parse_host_port(const char *url, char *host, size_t hostn, int *port) {
  const char *rest = url;
  char tmp[256];
  char *colon, *slash;
  *port = 80;
  snprintf(host, hostn, "127.0.0.1");
  if (!rest || !rest[0]) return;
  if (!strncmp(rest, "http://", 7)) rest += 7;
  else if (!strncmp(rest, "https://", 8)) rest += 8;
  snprintf(tmp, sizeof tmp, "%s", rest);
  slash = strchr(tmp, '/');
  if (slash) *slash = 0;
  colon = strrchr(tmp, ':');
  if (colon && colon != tmp && colon[-1] != ']') {
    *colon = 0;
    *port = atoi(colon + 1);
  }
  snprintf(host, hostn, "%s", tmp[0] ? tmp : "127.0.0.1");
}

void carolina_register(void) {
  const char *url = getenv("CAROLINA_URL");
  const char *token = getenv("POLYGLOT_REGISTER_TOKEN");
  const char *base = getenv("PUBLIC_BASE_URL");
  char host[256];
  char body[2048];
  char req[4096];
  char resp[512];
  int port, fd, n, k;
  struct addrinfo hints, *res = NULL, *rp;
  char portstr[16];
  const char *endpoints =
      "["
      "{\"method\":\"GET\",\"path\":\"/\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/health\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/v1/years\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/v1/speakers\",\"query\":[\"year\"]},"
      "{\"method\":\"GET\",\"path\":\"/v1/speakers/:slug\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/v1/speakers/:year/:slug\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/v1/sponsors\",\"query\":[\"year\"]},"
      "{\"method\":\"GET\",\"path\":\"/v1/sponsors/:slug\",\"query\":[]},"
      "{\"method\":\"GET\",\"path\":\"/v1/sponsors/:year/:slug\",\"query\":[]}"
      "]";

  if (!url || !url[0] || !token || !token[0]) return;
  parse_host_port(url, host, sizeof host, &port);
  if (!base || !base[0]) {
    static char fallback[64];
    snprintf(fallback, sizeof fallback, "http://127.0.0.1:%d",
             env_int("PORT", 4027));
    base = fallback;
  }
  snprintf(body, sizeof body,
           "{\"language\":\"COBOL\",\"language_version\":\"GnuCOBOL 3.2\","
           "\"api_version\":\"0.2.0\",\"framework\":\"POSIX sockets\","
           "\"created_year\":2026,\"schema_version\":1,\"endpoints\":%s,"
           "\"base_url\":\"%s\"}",
           endpoints, base);
  snprintf(req, sizeof req,
           "POST /internal/api-endpoints/register HTTP/1.1\r\n"
           "Host: %s\r\n"
           "Authorization: Bearer %s\r\n"
           "Content-Type: application/json\r\n"
           "Content-Length: %zu\r\n"
           "Connection: close\r\n\r\n%s",
           host, token, strlen(body), body);
  memset(&hints, 0, sizeof hints);
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_family = AF_UNSPEC;
  snprintf(portstr, sizeof portstr, "%d", port);
  if (getaddrinfo(host, portstr, &hints, &res) != 0) {
    fprintf(stderr, "register: getaddrinfo failed for %s\n", host);
    return;
  }
  fd = -1;
  for (rp = res; rp; rp = rp->ai_next) {
    fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
    if (fd < 0) continue;
    if (connect(fd, rp->ai_addr, rp->ai_addrlen) == 0) break;
    close(fd);
    fd = -1;
  }
  freeaddrinfo(res);
  if (fd < 0) {
    fprintf(stderr, "register: failed to connect %s:%d\n", host, port);
    return;
  }
  n = (int)strlen(req);
  k = 0;
  while (k < n) {
    int w = (int)send(fd, req + k, (size_t)(n - k), 0);
    if (w <= 0) break;
    k += w;
  }
  n = (int)recv(fd, resp, sizeof resp - 1, 0);
  if (n < 0) n = 0;
  resp[n] = 0;
  {
    char *sp = strchr(resp, ' ');
    fprintf(stderr, "registered with elixir: %s\n",
            sp ? sp + 1 : resp);
  }
  close(fd);
}
