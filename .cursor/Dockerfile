FROM debian:bookworm-slim
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc make libc6-dev libpq-dev libgmp-dev ca-certificates curl xz-utils git \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/gnucobol.tar.xz https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz \
 && tar -xJf /tmp/gnucobol.tar.xz -C /tmp \
 && cd /tmp/gnucobol-3.2 \
 && CFLAGS="-O2 -pipe -std=gnu17 -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion" \
    ./configure --prefix=/usr/local --without-db --without-curses --disable-rpath \
 && make -j"$(nproc)" && make install \
 && rm -rf /tmp/gnucobol-3.2 /tmp/gnucobol.tar.xz
ENV LD_LIBRARY_PATH=/usr/local/lib
