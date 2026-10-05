# cos-web-site: build the site from content/ into site/, and publish it.
#
# Publishing is the platform's: `deploy`, `check-deploy`, `releases` and
# `rollback` call its cloudlab Makefile, which holds the host, the paths and
# the releases. They need PLATFORM, the path to a checkout of it.

EMACS ?= emacs
PORT  ?= 8000

# SITE is this site's key under static_sites in the platform's CMDB.
SITE = $(MAKE) -C $(PLATFORM)/cloudlab SITE=cos-web-site

.PHONY: help build serve clean platform deploy check-deploy releases rollback

help:
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n", $$1, $$2}'

# The site is served under a content security policy that allows no inline
# script or style, so a page that carries either is broken where it is
# published and looks fine here. The build refuses it.
build: clean ## Build content/ into site/
	$(EMACS) --batch -Q --load publish.el --funcall cos-build
	@if grep -rnE '<script|<style| style="' --include='*.html' site; then \
	  echo "REFUSING: inline script or style in the pages above" >&2; exit 1; \
	fi

serve: build ## Build, then preview on localhost:$(PORT)
	python3 -m http.server --directory site $(PORT)

clean: ## Remove the built site
	rm -rf site

platform:
	@test -n "$(PLATFORM)" || { echo "usage: make $(MAKECMDGOALS) PLATFORM=<platform checkout>" >&2; exit 2; }

deploy: platform build ## Build, then publish site/ as a new release
	$(SITE) site-publish SRC=$(CURDIR)/site

check-deploy: platform build ## Build, then dry-run a publish
	$(SITE) site-publish-check SRC=$(CURDIR)/site

releases: platform ## List the releases on the host, and which is current
	$(SITE) site-releases

# make rollback PLATFORM=<platform checkout> RELEASE=20261005T101500
rollback: platform ## Re-point the site at an earlier release
	@test -n "$(RELEASE)" || { echo "usage: make rollback PLATFORM=<platform checkout> RELEASE=<id>  (see: make releases)" >&2; exit 2; }
	$(SITE) site-rollback RELEASE=$(RELEASE)
