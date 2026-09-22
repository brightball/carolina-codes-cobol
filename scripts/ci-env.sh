#!/usr/bin/env bash
# Pack, restore, and transfer the Gitea CI workspace + toolchain.
#
# act_runner starts a fresh container per job, so prepare persists both the
# GITHUB_SHA checkout and the Bookworm tool tree (apt .debs + /usr/local).
# Check jobs fetch this file with the job token, then restore — they do not
# clone or reinstall gnucobol/gcc/libpq/clang-format/trivy/gitleaks.
#
# Artifact transfer uses Gitea's Actions pipeline HTTP API (no Node).
# Official upload-artifact@v4 treats this Gitea as GHES and aborts.
set -euo pipefail

ARTIFACT_NAME="${CI_ENV_ARTIFACT_NAME:-prepared-env}"
TAR_PATH="${CI_ENV_TAR:-/tmp/prepared-env.tar.gz}"

json_string() {
  key="$1"
  file="$2"
  tr -d '\n' <"$file" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

artifact_token() {
  t="${ACTIONS_RUNTIME_TOKEN:-${GITHUB_TOKEN:-${GITEA_TOKEN:-}}}"
  if [ -z "$t" ]; then
    echo "missing artifact token (ACTIONS_RUNTIME_TOKEN/GITHUB_TOKEN)" >&2
    exit 1
  fi
  printf '%s' "$t"
}

artifact_base() {
  if [ -n "${ACTIONS_RUNTIME_URL:-}" ]; then
    u="${ACTIONS_RUNTIME_URL}"
    case "$u" in
      */) printf '%s' "$u" ;;
      *) printf '%s/' "$u" ;;
    esac
    return
  fi
  if [ -z "${GITHUB_SERVER_URL:-}" ]; then
    echo "missing ACTIONS_RUNTIME_URL or GITHUB_SERVER_URL" >&2
    exit 1
  fi
  printf '%s/api/actions_pipeline/' "${GITHUB_SERVER_URL%/}"
}

rewrite_runtime_url() {
  url="$1"
  url="$(printf '%s' "$url" | sed 's#\\/#/#g')"
  case "$url" in
    *_apis/*)
      suffix="${url#*_apis/}"
      printf '%s_apis/%s' "$(artifact_base)" "$suffix"
      ;;
    /*)
      printf '%s%s' "$(artifact_base)" "${url#/}"
      ;;
    http://*|https://*)
      printf '%s' "$url"
      ;;
    *)
      printf '%s%s' "$(artifact_base)" "$url"
      ;;
  esac
}

workspace_dir() {
  printf '%s' "${GITHUB_WORKSPACE:-$(pwd)}"
}

cmd_stage() {
  ws="${1:-$(workspace_dir)}"
  mkdir -p "${ws}/.ci-env/debs" "${ws}/.ci-env/usr-local" "${ws}/.ci-env/bin"
  if ! ls /var/cache/apt/archives/*.deb >/dev/null 2>&1; then
    echo "no .deb files in /var/cache/apt/archives; cannot stage CI env" >&2
    exit 1
  fi
  cp -a /var/cache/apt/archives/*.deb "${ws}/.ci-env/debs/"
  if [ -d /usr/local ]; then
    cp -a /usr/local/. "${ws}/.ci-env/usr-local/"
  fi
  # Only copy standalone release binaries here. gcc/cobc/make come from the
  # staged .debs; copying those ELFs into /usr/local/bin would shadow them.
  for tool in trivy gitleaks; do
    if command -v "$tool" >/dev/null 2>&1; then
      cp "$(command -v "$tool")" "${ws}/.ci-env/bin/"
    fi
  done
  chmod -R a+X "${ws}/.ci-env/bin" 2>/dev/null || true
  echo "staged toolchain into ${ws}/.ci-env"
}

cmd_pack() {
  src="${1:-$(workspace_dir)}"
  dest="${2:-$TAR_PATH}"
  if [ ! -d "$src" ]; then
    echo "pack source is not a directory: $src" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  # Always pack outside the tree, then the caller may move it.
  # TEMPLATE must end in XXXXXX on GNU mktemp (Bookworm coreutils).
  tmp="$(mktemp "${TMPDIR:-/tmp}/ci-env.XXXXXX")"
  tar -C "$src" \
    --exclude='./prepared-env.tar.gz' \
    --exclude="./$(basename "$dest")" \
    -czf "$tmp" .
  mv -f "$tmp" "$dest"
  echo "packed $dest"
}

cmd_unpack() {
  tar="${1:-$TAR_PATH}"
  dest="${2:-$(workspace_dir)}"
  if [ ! -f "$tar" ]; then
    echo "missing tarball $tar" >&2
    exit 1
  fi
  mkdir -p "$dest"
  tar -C "$dest" -xzf "$tar"
  echo "unpacked $tar -> $dest"
}

cmd_apply() {
  ws="${1:-$(workspace_dir)}"
  if [ ! -d "${ws}/.ci-env" ]; then
    echo "restored tree is missing .ci-env" >&2
    exit 1
  fi
  if [ -d "${ws}/.ci-env/debs" ] && ls "${ws}/.ci-env/debs"/*.deb >/dev/null 2>&1; then
    if [ "$(id -u)" = 0 ]; then
      export DEBIAN_FRONTEND=noninteractive
      dpkg --force-depends --install "${ws}/.ci-env/debs"/*.deb
      ldconfig || true
    else
      echo "skipping dpkg apply (not root)"
    fi
  fi
  if [ -d "${ws}/.ci-env/usr-local" ] && [ -w /usr/local ]; then
    cp -a "${ws}/.ci-env/usr-local/." /usr/local/
  fi
  if [ -d "${ws}/.ci-env/bin" ]; then
    if [ -w /usr/local/bin ]; then
      cp -a "${ws}/.ci-env/bin/." /usr/local/bin/
      chmod a+x /usr/local/bin/* 2>/dev/null || true
    fi
    if [ -n "${GITHUB_PATH:-}" ]; then
      echo "${ws}/.ci-env/bin" >>"$GITHUB_PATH"
      echo "/usr/local/bin" >>"$GITHUB_PATH"
    fi
    export PATH="${ws}/.ci-env/bin:/usr/local/bin:${PATH}"
  fi
  hash -r || true
  echo "applied toolchain from ${ws}/.ci-env"
}

cmd_upload() {
  if [ ! -f "$TAR_PATH" ]; then
    echo "missing tarball $TAR_PATH" >&2
    exit 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$TAR_PATH" "$ARTIFACT_NAME" <<'PY'
import base64, hashlib, json, os, sys, urllib.parse, urllib.request

path, name = sys.argv[1], sys.argv[2]


def env_get(*names):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    raise SystemExit("missing required environment: " + ", ".join(names))


def runtime_url():
    url = os.environ.get("ACTIONS_RUNTIME_URL")
    if url:
        return url if url.endswith("/") else url + "/"
    return env_get("GITHUB_SERVER_URL").rstrip("/") + "/api/actions_pipeline/"


def runtime_token():
    return env_get("ACTIONS_RUNTIME_TOKEN", "GITHUB_TOKEN", "GITEA_TOKEN")


def run_id():
    return env_get("GITHUB_RUN_ID", "GITEA_RUN_ID")


def resolve_url(url):
    if not url:
        raise SystemExit("artifact API returned an empty URL")
    runtime = runtime_url()
    parsed = urllib.parse.urlparse(url.replace("\\/", "/"))
    rt = urllib.parse.urlparse(runtime)
    if not parsed.scheme:
        return urllib.parse.urljoin(runtime, url.lstrip("/"))
    return urllib.parse.urlunparse(
        (rt.scheme, rt.netloc, parsed.path, parsed.params, parsed.query, parsed.fragment)
    )


def request(method, url, data=None, headers=None):
    hdrs = {"Authorization": "Bearer " + runtime_token()}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        return urllib.request.urlopen(req, timeout=600)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"{method} {url} failed: {exc.code} {body}") from exc


api = (
    f"{runtime_url()}_apis/pipelines/workflows/{run_id()}/artifacts"
    "?api-version=6.0-preview"
)
size = os.path.getsize(path)
if size < 1:
    raise SystemExit(f"refusing to upload empty artifact: {path}")
payload = json.dumps({"Type": "actions_storage", "Name": name, "RetentionDays": 1}).encode()
with request("POST", api, data=payload, headers={"Content-Type": "application/json"}) as resp:
    created = json.load(resp)
upload_base = resolve_url(
    created.get("fileContainerResourceUrl") or created.get("fileContainerResourceURL") or ""
)
item = urllib.parse.quote(name + "/" + os.path.basename(path), safe="")
sep = "&" if "?" in upload_base else "?"
put_url = upload_base + sep + "itemPath=" + item
data = open(path, "rb").read()
md5 = base64.b64encode(hashlib.md5(data).digest()).decode("ascii")
put_headers = {
    "Content-Type": "application/octet-stream",
    "Content-Range": "bytes 0-%d/%d" % (len(data) - 1, len(data)),
    "x-tfs-filelength": str(len(data)),
    "x-actions-results-md5": md5,
}
with request("PUT", put_url, data=data, headers=put_headers):
    pass
confirm = api + "&artifactName=" + urllib.parse.quote(name)
with request("PATCH", confirm):
    pass
print("uploaded", name, path)
PY
    return
  fi
  echo "python3 is required to upload the prepared-env artifact" >&2
  exit 1
}

cmd_download() {
  mkdir -p "$(dirname "$TAR_PATH")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$TAR_PATH" "$ARTIFACT_NAME" <<'PY'
import gzip, json, os, sys, time, urllib.error, urllib.parse, urllib.request

dest, name = sys.argv[1], sys.argv[2]


def env_get(*names):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    raise SystemExit("missing required environment: " + ", ".join(names))


def runtime_url():
    url = os.environ.get("ACTIONS_RUNTIME_URL")
    if url:
        return url if url.endswith("/") else url + "/"
    return env_get("GITHUB_SERVER_URL").rstrip("/") + "/api/actions_pipeline/"


def runtime_token():
    return env_get("ACTIONS_RUNTIME_TOKEN", "GITHUB_TOKEN", "GITEA_TOKEN")


def run_id():
    return env_get("GITHUB_RUN_ID", "GITEA_RUN_ID")


def resolve_url(url):
    if not url:
        raise SystemExit("artifact API returned an empty URL")
    runtime = runtime_url()
    parsed = urllib.parse.urlparse(url.replace("\\/", "/"))
    rt = urllib.parse.urlparse(runtime)
    if not parsed.scheme:
        return urllib.parse.urljoin(runtime, url.lstrip("/"))
    return urllib.parse.urlunparse(
        (rt.scheme, rt.netloc, parsed.path, parsed.params, parsed.query, parsed.fragment)
    )


def request(method, url, data=None, headers=None):
    hdrs = {"Authorization": "Bearer " + runtime_token()}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    return urllib.request.urlopen(req, timeout=600)


api = (
    f"{runtime_url()}_apis/pipelines/workflows/{run_id()}/artifacts"
    "?api-version=6.0-preview"
)
listing = None
last_err = None
for _ in range(12):
    try:
        with request("GET", api) as resp:
            listing = json.load(resp)
        break
    except urllib.error.HTTPError as err:
        last_err = err
        if err.code not in (404, 500):
            body = err.read().decode("utf-8", "replace")
            raise SystemExit(f"GET {api} failed: {err.code} {body}") from err
        time.sleep(2)
if listing is None:
    raise SystemExit(f"artifact list failed: {last_err}")
items = listing.get("value") or []
match = next((item for item in items if item.get("name") == name), None)
if match is None:
    raise SystemExit(f"artifact {name!r} not found; have {[i.get('name') for i in items]}")
container = resolve_url(
    match.get("fileContainerResourceUrl") or match.get("fileContainerResourceURL") or ""
)
sep = "&" if "?" in container else "?"
files_url = container + sep + "itemPath=" + urllib.parse.quote(name, safe="")
with request("GET", files_url) as resp:
    files = json.load(resp)
entries = files.get("value") or []
if not entries:
    raise SystemExit(f"artifact {name!r} has no files")
entry = next(
    (row for row in entries if str(row.get("path", "")).endswith(".tar.gz")),
    entries[0],
)
location = resolve_url(entry.get("contentLocation") or "")
with request("GET", location) as resp:
    blob = resp.read()
    encoding = (resp.headers.get("Content-Encoding") or "").lower()
if encoding == "gzip":
    blob = gzip.decompress(blob)
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
open(dest, "wb").write(blob)
print("downloaded", name, "->", dest)
PY
    echo "downloaded $TAR_PATH"
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl or python3 is required to download the prepared-env artifact" >&2
    exit 1
  fi
  if [ -z "${GITHUB_RUN_ID:-}" ]; then
    echo "missing GITHUB_RUN_ID" >&2
    exit 1
  fi
  token="$(artifact_token)"
  base="$(artifact_base)"
  list_url="${base}_apis/pipelines/workflows/${GITHUB_RUN_ID}/artifacts?api-version=6.0-preview"
  resp="$(mktemp)"
  curl -fsS -H "Authorization: Bearer ${token}" "$list_url" -o "$resp"
  container_url="$(json_string fileContainerResourceUrl "$resp")"
  rm -f "$resp"
  if [ -z "$container_url" ]; then
    echo "artifact list did not return fileContainerResourceUrl" >&2
    exit 1
  fi
  container_url="$(rewrite_runtime_url "$container_url")"
  files="$(mktemp)"
  sep='?'
  case "$container_url" in
    *\?*) sep='&' ;;
  esac
  curl -fsS -H "Authorization: Bearer ${token}" \
    "${container_url}${sep}itemPath=${ARTIFACT_NAME}" -o "$files"
  content_url="$(json_string contentLocation "$files")"
  rm -f "$files"
  if [ -z "$content_url" ]; then
    echo "artifact download did not return contentLocation" >&2
    exit 1
  fi
  content_url="$(rewrite_runtime_url "$content_url")"
  curl -fsS -H "Authorization: Bearer ${token}" "$content_url" -o "$TAR_PATH"
  echo "downloaded $TAR_PATH"
}

cmd_prepare() {
  ws="$(workspace_dir)"
  if [ -d "${ws}/.git" ] && [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ]; then
    git -C "$ws" remote set-url origin "${GITHUB_SERVER_URL%/}/${GITHUB_REPOSITORY}" || true
  fi
  cmd_stage "$ws"
  cmd_pack "$ws" "$TAR_PATH"
  cmd_upload
}

cmd_restore() {
  echo "restoring prepared environment"
  cmd_download
  cmd_unpack "$TAR_PATH" "$(workspace_dir)"
  cmd_apply "$(workspace_dir)"
}

usage() {
  echo "usage: $0 prepare|restore|stage|pack|unpack|apply|upload|download [args]" >&2
  exit 2
}

cmd="${1:-}"
shift || true
case "$cmd" in
  prepare) cmd_prepare "$@" ;;
  restore) cmd_restore "$@" ;;
  stage) cmd_stage "$@" ;;
  pack) cmd_pack "$@" ;;
  unpack) cmd_unpack "$@" ;;
  apply) cmd_apply "$@" ;;
  upload) cmd_upload "$@" ;;
  download) cmd_download "$@" ;;
  *) usage ;;
esac
