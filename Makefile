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

.PHONY: all test server run clean sast audit gitleaks lint check hooks \
	test-workflow http-bin reconnect-bin test-reconnect

all: server test-bin

bin:
	mkdir -p bin

server: bin
	$(COBC) $(COBCFLAGS) -x -O2 -o bin/carolina-cobol \
		src/server.cob src/handler.cob src/catalog.cob \
		src/pq.c src/listen6.c -lpq -lpthread
	strip --strip-unneeded bin/carolina-cobol

http-bin: bin
	$(COBC) $(COBCFLAGS) -x -O2 -o bin/carolina-http-test \
		src/server.cob src/handler.cob src/catalog-fake.cob \
		src/listen6.c -lpthread
	strip --strip-unneeded bin/carolina-http-test

test-bin: bin
	$(COBC) $(COBCFLAGS) -x -O -o bin/test \
		tests/test.cob src/handler.cob src/catalog-fake.cob

test: test-bin http-bin server
	./bin/test
	python3 tests/test_http.py
	python3 tests/test_health_ready.py
	$(MAKE) test-workflow

test-workflow:
	python3 tests/test_workflow.py
	sh tests/test-ci-env.sh
	sh tests/test_image_digest.sh

reconnect-bin: bin
	gcc -Wall -Wextra -Werror -O2 $(PQ_CFLAGS) -o bin/test-reconnect \
		tests/test_reconnect.c src/pq.c -lpq

test-reconnect: reconnect-bin
	./bin/test-reconnect

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
	# -Wterminator is outside -Wall and would rewrite every CALL/ADD/DISPLAY.
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra -Werror -Wno-terminator \
		src/server.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra -Werror -Wno-terminator \
		src/handler.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra -Werror -Wno-terminator \
		src/catalog.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra -Werror -Wno-terminator \
		src/catalog-fake.cob
	$(COBC) $(COBCFLAGS) -fsyntax-only -Wall -Wextra -Werror -Wno-terminator \
		tests/test.cob
	$(CLANG_FORMAT) --version
	$(CLANG_FORMAT) --dry-run --Werror src/pq.c src/listen6.c

check: test test-reconnect sast audit gitleaks lint

hooks:
	pre-commit install
	git config core.hooksPath .githooks

run: server
	./bin/carolina-cobol

clean:
	rm -f bin/carolina-cobol bin/carolina-http-test bin/test bin/test-reconnect \
		*.c.h src/*.c.h
	rm -rf .sast
