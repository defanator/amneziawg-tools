#!/usr/bin/env make -f

TOPDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SELF   := $(abspath $(lastword $(MAKEFILE_LIST)))

ifndef VERSION
VERSION := $(shell git describe --tags --always --match='v[0-9]*' | cut -d '-' -f 1 | tr -d 'v')
endif

LONG_VERSION := $(shell git describe --tags --always --long --dirty)

WHOAMI   := $(shell whoami)
HOSTNAME := $(shell hostname -s)

DISTRO := $(shell . /etc/os-release 2>/dev/null; printf "%s-%s" "$${ID}" "$${VERSION_ID}")

help: ## Show help message (list targets)
	@awk 'BEGIN {FS = ":.*##"; printf "\nTargets:\n"} /^[$$()% 0-9a-zA-Z_-]+:.*?##/ {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(SELF)

show-var-%:
	@{ \
	escaped_v="$(subst ",\",$($*))" ; \
	if [ -n "$$escaped_v" ]; then v="$$escaped_v"; else v="(undefined)"; fi; \
	printf "%-20s %s\n" "$*" "$$v"; \
	}

SHOW_ENV_VARS = \
	TOPDIR \
	SELF \
	VERSION \
	LONG_VERSION \
	WHOAMI \
	HOSTNAME \
	DISTRO

show-env: $(addprefix show-var-, $(SHOW_ENV_VARS)) ## Show environment details

export-var-%:
	@{ \
	escaped_v="$(subst ",\",$($*))" ; \
	if [ -n "$$escaped_v" ]; then v="$$escaped_v"; else v="(undefined)"; fi; \
	printf "%s=%s\n" "$*" "$$v"; \
	}

EXPORT_ENV_VARS = \
	DISTRO

export-env: $(addprefix export-var-, $(EXPORT_ENV_VARS)) ## Export environment

update-version: ## Update version in sources
	@{ \
	echo "Detected version in Git: $(VERSION)" ; \
	sed -i -e 's,#define WIREGUARD_TOOLS_VERSION ".*,#define WIREGUARD_TOOLS_VERSION "$(VERSION)",' src/version.h ; \
	}

build: update-version ## Build binary
	$(MAKE) -C src

dist/debuild:
	mkdir -p $@
	cp -r src $@/
	cp -r debian $@/
	cp -r contrib $@/

dist/debuild/debian/changelog.orig: dist/debuild
	@{ \
	set -xeu ; \
	. /etc/os-release ; \
	cp dist/debuild/debian/changelog $@ ; \
	sed \
		-e "s,%%VERSION%%,$(VERSION),g" \
		-e "s,%%LONG_VERSION%%,$(LONG_VERSION),g" \
		-e "s,%%CODENAME%%,$${VERSION_CODENAME},g" \
		-e "s,%%USERNAME%%,$(WHOAMI),g" \
		-e "s,%%USEREMAIL%%,$(WHOAMI)@$(HOSTNAME),g" \
		-e "s/%%DATESTAMP%%/$$(date +"%a, %d %b %Y %H:%M:%S %z")/g" \
	< dist/debuild/debian/changelog.tmpl.in > dist/debuild/debian/changelog ; \
	cat $@ >>dist/debuild/debian/changelog ; \
	}

build-deb: update-version dist/debuild/debian/changelog.orig ## Build .deb package
	cd dist/debuild && debuild -b -uc -us

build-rpm: ## Build .rpm package
	$(error not yet)

.PHONY: clean
clean: ## Clean up
	rm -rf $(TOPDIR)/dist
	git checkout src/version.h
	$(MAKE) -C src clean
