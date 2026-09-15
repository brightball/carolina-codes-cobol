GNUCBOBOL ?= $(HOME)/.local/opt/gnucobol-3.2
ifneq ($(wildcard $(GNUCBOBOL)/bin/cobc),)
  COBC ?= $(GNUCBOBOL)/bin/cobc
  export LD_LIBRARY_PATH := $(GNUCBOBOL)/lib:$(LD_LIBRARY_PATH)
else
  COBC ?= cobc
endif
export PATH := $(HOME)/.local/bin:$(HOME)/.local/share/mise/installs/gitleaks/8.30.1:$(PATH)

# GnuCOBOL 3.2 accepts >>SOURCE FORMAT FREE at column 1; 3.1.2 needs -free.
COBCFLAGS ?= -free
PQ_CFLAGS ?= $(shell pkg-config --cflags libpq 2>/dev/null)

GITLEAKS ?= gitleaks
TRIVY ?= trivy
CLANG_FORMAT ?= clang-format

.PHONY: all test server run clean sast audit gitleaks lint check hooks

all: server test-bin

bin:
	mkdir -p bin

server: bin
	$(COBC) $(COBCFLAGS) -x -O -o bin/carolina-cobol \
		src/server.cob src/handler.cob src/catalog.cob \
		src/pq.c src/listen6.c -lpq

test-bin: bin
	$(COBC) $(COBCFLAGS) -x -O -o bin/test \
		tests/test.cob src/handler.cob src/catalog-fake.cob

test: test-bin
	./bin/test

sast:
	gcc --version | head -1
	mkdir -p .sast
	gcc -fanalyzer -Wall -Wextra -Werror $(PQ_CFLAGS) -c src/pq.c -o .sast/pq.o
	gcc -fanalyzer -Wall -Wextra -Werror -c src/listen6.c -o .sast/listen6.o

audit:
	$(TRIVY) version
	$(TRIVY) fs --scanners vuln,misconfig \
		--severity HIGH,CRITICAL --ignore-unfixed \
		--skip-dirs .cursor --skip-dirs bin --skip-dirs .sast \
		--exit-code 1 .

gitleaks:
	$(GITLEAKS) version
	$(GITLEAKS) detect --source . --verbose --redact

lint:
	$(COBC) --version | head -1
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra src/server.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra src/handler.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra src/catalog.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra src/catalog-fake.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra tests/test.cob
	$(CLANG_FORMAT) --version
	$(CLANG_FORMAT) --dry-run --Werror src/pq.c src/listen6.c

check: test sast audit gitleaks lint

hooks:
	pre-commit install
	git config core.hooksPath .githooks

run: server
	./bin/carolina-cobol

clean:
	rm -f bin/carolina-cobol bin/test *.c.h src/*.c.h
	rm -rf .sast
