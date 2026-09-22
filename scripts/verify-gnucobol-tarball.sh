#!/bin/sh
# Fail unless the file is the pinned GnuCOBOL 3.2 release tarball.
# Published SHA256 of https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz
# (GNU gsrc / fossies, 2902828 bytes).
set -eu
file="${1:?tarball path required}"
expected="3bb48af46ced4779facf41fdc2ee60e4ccb86eaa99d010b36685315df39c2ee2"
echo "${expected}  ${file}" | sha256sum -c -
