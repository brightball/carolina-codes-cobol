#!/bin/sh
# Pinned GnuCOBOL 3.2 digest, Fly suspend, production -O2, warning-failing lint.
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
script="${root}/scripts/verify-gnucobol-tarball.sh"
pin="3bb48af46ced4779facf41fdc2ee60e4ccb86eaa99d010b36685315df39c2ee2"

if [ ! -f "$script" ]; then
  echo "missing $script" >&2
  exit 1
fi
if ! grep -q "$pin" "$script"; then
  echo "verifier is not pinned to the GnuCOBOL 3.2 sha256" >&2
  exit 1
fi

bad="$(mktemp)"
trap 'rm -f "$bad"' EXIT
printf 'not-the-gnucobol-tarball\n' >"$bad"
if sh "$script" "$bad"; then
  echo "mismatched digest was accepted" >&2
  exit 1
fi
echo "ok: mismatched digest fails"

python3 - "$root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
docker = (root / "Dockerfile").read_text()
verify_at = docker.find("verify-gnucobol-tarball.sh")
configure_at = docker.find("./configure")
if verify_at < 0 or configure_at < 0 or verify_at > configure_at:
    raise SystemExit("Dockerfile must check the tarball digest before configure")
if "gnucobol-3.2" not in docker:
    raise SystemExit("image must build GnuCOBOL 3.2")
if "gnucobol-3.1" in docker:
    raise SystemExit("image must not switch to distro GnuCOBOL 3.1")
if "-O2" not in docker or "strip" not in docker:
    raise SystemExit("image build must compile at -O2 and strip")
fly = (root / "fly.toml").read_text()
for needle in (
    'auto_stop_machines = "suspend"',
    "min_machines_running = 0",
    'memory = "256mb"',
):
    if needle not in fly:
        raise SystemExit(f"fly.toml missing {needle}")
make = (root / "Makefile").read_text()
if "-Werror" not in make:
    raise SystemExit("COBOL lint must treat warnings as errors")
if "-O2" not in make:
    raise SystemExit("production cobc flags must include -O2")
print("ok: digest check precedes configure; suspend; -O2; lint -Werror")
PY

if [ -x "${HOME}/.local/opt/gnucobol-3.2/bin/cobc" ]; then
  cobc="${HOME}/.local/opt/gnucobol-3.2/bin/cobc"
elif command -v cobc >/dev/null 2>&1; then
  cobc="cobc"
else
  echo "cobc not found" >&2
  exit 1
fi

warn="$(mktemp)"
cat >"$warn" <<'EOF'
>>SOURCE FORMAT FREE
IDENTIFICATION DIVISION.
PROGRAM-ID. WARN-ME.
DATA DIVISION.
WORKING-STORAGE SECTION.
01 WS-X PIC X(2).
PROCEDURE DIVISION.
    MOVE "abcd" TO WS-X
    STOP RUN.
END PROGRAM WARN-ME.
EOF
if "$cobc" -free -fsyntax-only -Wall -Wextra -Werror "$warn" >/dev/null 2>&1; then
  rm -f "$warn"
  echo "COBOL warning did not fail cobc -Wall -Wextra -Werror" >&2
  exit 1
fi
rm -f "$warn"
echo "ok: COBOL warnings fail the lint flags"
