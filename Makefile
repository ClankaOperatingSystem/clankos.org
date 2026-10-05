# cos-web-site: build the site from content/ into site/.

EMACS ?= emacs
PORT  ?= 8000

.PHONY: help build serve clean

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
