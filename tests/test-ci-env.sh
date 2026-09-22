#!/bin/sh
# Drive the shipped scripts/ci-env.sh pack/unpack path (not a reimplementation).
set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
helper="${root}/scripts/ci-env.sh"
if [ ! -f "$helper" ]; then
  echo "missing $helper" >&2
  exit 1
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

stub="${scratch}/stub"
mkdir -p "${stub}/src" "${stub}/.ci-env/bin" "${stub}/.ci-env/debs"
printf 'all:\n\techo ok\n' >"${stub}/Makefile"
printf 'hello-handler\n' >"${stub}/src/handler.cob"
printf '#!/bin/sh\necho cobc-stub\n' >"${stub}/.ci-env/bin/cobc"
printf 'deb-bytes\n' >"${stub}/.ci-env/debs/example.deb"
chmod +x "${stub}/.ci-env/bin/cobc"

archive="${scratch}/prepared-env.tar.gz"
bash "$helper" pack "$stub" "$archive"
if [ ! -s "$archive" ]; then
  echo "pack did not write $archive" >&2
  exit 1
fi

out="${scratch}/restored"
mkdir -p "$out"
bash "$helper" unpack "$archive" "$out"

if [ ! -f "${out}/Makefile" ]; then
  echo "unpack missing Makefile" >&2
  exit 1
fi
if [ ! -f "${out}/src/handler.cob" ]; then
  echo "unpack missing src/handler.cob" >&2
  exit 1
fi
if [ ! -x "${out}/.ci-env/bin/cobc" ]; then
  echo "unpack did not restore executable .ci-env/bin/cobc" >&2
  exit 1
fi
if [ ! -f "${out}/.ci-env/debs/example.deb" ]; then
  echo "unpack did not restore apt archive payload .ci-env/debs" >&2
  exit 1
fi
if ! grep -q 'dpkg --force-depends --install' "$helper"; then
  echo "ci-env apply does not install staged apt debs onto the system" >&2
  exit 1
fi
if ! grep -q '/var/cache/apt/archives/' "$helper"; then
  echo "ci-env stage does not capture apt archives" >&2
  exit 1
fi

got="$(grep -c 'hello-handler' "${out}/src/handler.cob")"
if [ "$got" -ne 1 ]; then
  echo "restored handler.cob contents mismatch" >&2
  exit 1
fi

ran="$("${out}/.ci-env/bin/cobc")"
case "$ran" in
  *cobc-stub*) ;;
  *)
    echo "restored cobc did not run: $ran" >&2
    exit 1
    ;;
esac

echo "ok: pack/unpack restored tree and executable"
