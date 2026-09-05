GNUCBOBOL ?= $(HOME)/.local/opt/gnucobol-3.2
COBC ?= $(GNUCBOBOL)/bin/cobc
export LD_LIBRARY_PATH := $(GNUCBOBOL)/lib:$(LD_LIBRARY_PATH)

.PHONY: all test server run clean

all: server test-bin

bin:
	mkdir -p bin

server: bin
	$(COBC) -x -O -o bin/carolina-cobol \
		src/server.cob src/handler.cob src/catalog.cob \
		src/pq.c src/listen6.c -lpq

test-bin: bin
	$(COBC) -x -O -o bin/test \
		tests/test.cob src/handler.cob src/catalog-fake.cob

test: test-bin
	./bin/test

run: server
	./bin/carolina-cobol

clean:
	rm -f bin/carolina-cobol bin/test *.c.h src/*.c.h
