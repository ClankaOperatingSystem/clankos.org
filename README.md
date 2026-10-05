# Clanka Operating System Website

The site at <https://www.clankaoperatingsystem.org>.

The pages are Org files in `content/`. Emacs builds them into HTML in
`site/`, which is not kept in Git.

```sh
make build      # content/ -> site/
make serve      # build, then preview on http://localhost:8000
```

`make help` lists the rest. The build needs Emacs and nothing else; `make
serve` needs Python 3.

## Writing a page

Add an Org file under `content/`. `content/guide/start.org` becomes
`site/guide/start.html`. Give it a `#+TITLE`, which becomes the page's
heading, and a `#+DESCRIPTION`, which search engines show. Link to another
page as an Org file, `[[file:guide/start.org][Start]]`; the build writes the
link to the HTML page, and fails on a link to a file that is not there.

Every other file under `content/` is copied as it is: the stylesheet, and any
image or font a page uses.

## Changing how a page looks

`template.html` is the page around every Org file's body, and
`content/style.css` is the stylesheet. The template's placeholders are listed
in `publish.el`, which holds the build.

The site is served under a content security policy that allows no inline
script and no inline style, and nothing loaded from another site. Styling
goes in the stylesheet and fonts are served from `content/`. `make build`
fails if a page contains a `<script>`, a `<style>` or a `style` attribute.
