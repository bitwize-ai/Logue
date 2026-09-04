# README artwork

Filenames carry a content hash: `<name>.<first 8 of sha256>.png`.

GitHub rewrites the README's relative image paths to
`github.com/bitwize-ai/Logue/raw/main/docs/images/<file>` and serves them with
`cache-control: max-age=300`. Replacing an image in place keeps that URL identical, so
browsers and the CDN keep painting the copy they already hold — the picture looks
unchanged for everyone who had loaded the page before, with nothing wrong in the repo to
find. Changing the name changes the URL, and a URL that has never been requested cannot
be served from a stale cache.

So when you replace one, rename it too:

```bash
cd docs/images
f=home-dashboard.393d5e51.png            # the file you just overwrote
base=${f%%.*}                            # -> home-dashboard
git mv "$f" "$base.$(shasum -a 256 "$f" | cut -c1-8).png"
```

Then update the reference in `README.md`. Nothing builds these, so the rename and the
reference are both by hand — a stale reference shows as a broken image on the repository
front page, which is the failure you want rather than the silent one.

The sources live in the marketing site's `public/screenshots/` and `public/assets/`; the
Logue wordmarks are rendered from the app's own `Logue/Resources/LogueLogo*.svg`.
