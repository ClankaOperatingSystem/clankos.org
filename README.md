# Clanka Operating System Website

The site at <https://www.clankaoperatingsystem.org>.

One page, in `site/`: `index.html` and `style.css`. There is no build step.
The page uses no script and no inline style, so it can be served under a
content security policy that allows neither.

To look at it:

```sh
python3 -m http.server --directory site 8000
```

then open <http://localhost:8000>.
