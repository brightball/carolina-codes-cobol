FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc make libc6-dev libpq-dev libgmp-dev ca-certificates curl xz-utils \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSL -o gnucobol.tar.xz https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz \
 && tar -xJf gnucobol.tar.xz \
 && cd gnucobol-3.2 \
 && CFLAGS="-O2 -pipe -std=gnu17 -Wno-incompatible-pointer-types -Wno-implicit-function-declaration -Wno-int-conversion" \
    ./configure --prefix=/usr/local --without-db --without-curses --disable-rpath \
 && make -j"$(nproc)" \
 && make install
COPY src /src/app/src
WORKDIR /src/app
ENV LD_LIBRARY_PATH=/usr/local/lib
RUN cobc -x -O -o /src/carolina-cobol \
      src/server.cob src/handler.cob src/catalog.cob src/pq.c src/listen6.c -lpq

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 libgmp10 ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/lib/libcob.so* /usr/local/lib/
COPY --from=build /src/carolina-cobol /usr/local/bin/carolina-cobol
ENV LD_LIBRARY_PATH=/usr/local/lib
ENV PORT=8080
EXPOSE 8080
CMD ["/usr/local/bin/carolina-cobol"]
