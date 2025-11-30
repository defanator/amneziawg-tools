#!/usr/bin/env make -f

TOPDIR := $(realpath $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SELF   := $(abspath $(lastword $(MAKEFILE_LIST)))

GITHUB_SERVER_URL ?= http://localhost
GITHUB_REPOSITORY ?= amnezia-vpn/amneziawg-tools
GITHUB_RUN_ID     ?= 0
_RUN_URL          := $(GITHUB_SERVER_URL)/$(GITHUB_REPOSITORY)/actions/runs/$(GITHUB_RUN_ID)

ifndef VERSION
VERSION := $(shell git describe --tags --always --match='v[0-9]*' | cut -d '-' -f 1 | tr -d 'v')
endif

LONG_VERSION  := $(shell git describe --tags --always --long --dirty)-$(GITHUB_RUN_ID)
_LONG_VERSION := $(shell echo "$(LONG_VERSION)" | sed 's/^v//')

WHOAMI   := $(shell whoami)
HOSTNAME := $(shell hostname -s)
OS       := $(shell uname -s | tr '[:upper:]' '[:lower:]')
OSARCH   := $(shell uname -m)

ifeq ($(OSARCH),x86_64)
DEB_BUILD_ARCH := amd64
else ifeq ($(OSARCH),aarch64)
DEB_BUILD_ARCH := arm64
else
ARCH := $(OSARCH)
endif

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
	GITHUB_RUN_ID \
	_RUN_URL \
	VERSION \
	LONG_VERSION \
	_LONG_VERSION \
	WHOAMI \
	HOSTNAME \
	OS \
	OSARCH \
	DEB_BUILD_ARCH \
	DISTRO

show-env: $(addprefix show-var-, $(SHOW_ENV_VARS)) ## Show environment details

export-var-%:
	@{ \
	escaped_v="$(subst ",\",$($*))" ; \
	if [ -n "$$escaped_v" ]; then v="$$escaped_v"; else v="(undefined)"; fi; \
	printf "%s=%s\n" "$*" "$$v"; \
	}

EXPORT_ENV_VARS = \
	OSARCH \
	DEB_BUILD_ARCH \
	DISTRO

export-env: $(addprefix export-var-, $(EXPORT_ENV_VARS)) ## Export environment

update-version: ## Update version in sources
	@{ \
	echo "Detected version in Git: $(VERSION)" ; \
	sed -i -e 's,#define WIREGUARD_TOOLS_VERSION ".*,#define WIREGUARD_TOOLS_VERSION "$(VERSION)",' src/version.h ; \
	sed -i -e 's,^Version:.*,Version: $(VERSION),' amneziawg-tools.spec ; \
	}

update-version-verbose: ## Update version with full build references
	@{ \
	echo "Detected verbose version: $(LONG_VERSION)" ; \
	echo "RUN_URL: $(_RUN_URL)" ; \
	sed -i -e 's,#define WIREGUARD_TOOLS_VERSION ".*,#define WIREGUARD_TOOLS_VERSION "$(_LONG_VERSION)",' src/version.h ; \
	sed -i -e 's, - https://amnezia.org, - $(_RUN_URL),' src/wg.c ; \
	}

build: update-version-verbose ## Build binary
	$(MAKE) -C src

dist/debuild: update-version
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
		-e "s,%%RUN_URL%%,$(_RUN_URL),g" \
		-e "s,%%CODENAME%%,$${VERSION_CODENAME},g" \
		-e "s,%%USERNAME%%,$(WHOAMI),g" \
		-e "s,%%USEREMAIL%%,$(WHOAMI)@$(HOSTNAME),g" \
		-e "s/%%DATESTAMP%%/$$(date +"%a, %d %b %Y %H:%M:%S %z")/g" \
	< dist/debuild/debian/changelog.tmpl.in > dist/debuild/debian/changelog ; \
	cat $@ >>dist/debuild/debian/changelog ; \
	}

build-deb: dist/debuild/debian/changelog.orig ## Build .deb package
	cd dist/debuild && debuild -b -uc -us

dist/rpmbuild: update-version
	mkdir -p $@
	mkdir -p $@/SPECS
	mkdir -p $@/SOURCES
	tar -czvf $@/SOURCES/v$(VERSION).tar.gz --transform 's|^|amneziawg-tools-$(VERSION)/|' src/ contrib/ README.md COPYING
	cp amneziawg-tools.spec $@/SPECS/
	sed -i -e "s,%changelog,%changelog\n* $$(date +"%a %b %d %Y") $(WHOAMI) <$(WHOAMI)@$(HOSTNAME)> - $(VERSION)\n- automated build ($(LONG_VERSION))\n- $(_RUN_URL)\n," $@/SPECS/amneziawg-tools.spec

build-rpm: update-version dist/rpmbuild ## Build .rpm package
	rpmbuild -D "_topdir $(TOPDIR)/dist/rpmbuild" -ba dist/rpmbuild/SPECS/amneziawg-tools.spec

builder-%: ## Create containerized builder
	docker build \
		-f $(TOPDIR)/containers/Containerfile.$* \
		-t amneziawg-tools-builder:$* \
		$(TOPDIR)/containers

buildenv-%: ## Run building environment in a container
	docker run --rm \
		-v $(TOPDIR):/amneziawg-tools \
		-ti amneziawg-tools-builder:$* \
		bash

.PHONY: clean
clean: ## Clean up
	rm -rf $(TOPDIR)/dist
	git checkout src/version.h src/wg.c amneziawg-tools.spec
	$(MAKE) -C src clean
