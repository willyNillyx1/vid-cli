PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1
DESTDIR ?=
INSTALL ?= install

.PHONY: all install uninstall check test

all:
	@printf '%s\n' 'Nothing to build. Try: make check, make test, make install'

install:
	mkdir -p "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(MANDIR)"
	$(INSTALL) -m 755 vid-cli "$(DESTDIR)$(BINDIR)/vid-cli"
	$(INSTALL) -m 644 vid-cli.1 "$(DESTDIR)$(MANDIR)/vid-cli.1"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/vid-cli" "$(DESTDIR)$(MANDIR)/vid-cli.1"

check:
	@if ! command -v dash >/dev/null 2>&1; then \
		printf '%s\n' 'dash not found; install dash (apt: dash, brew: dash, pacman: dash)'; \
		exit 1; \
	fi
	@dash -n vid-cli && printf '%s\n' 'dash -n vid-cli: ok'
	@if [ -f tests/run.sh ]; then dash -n tests/run.sh && printf '%s\n' 'dash -n tests/run.sh: ok'; fi
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck vid-cli tests/run.sh; \
	else \
		printf '%s\n' 'shellcheck not found; skipping shellcheck'; \
	fi

test: check
	@dash tests/run.sh
