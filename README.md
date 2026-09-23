# Spotlight website

Landing page and documentation for [Spotlight](https://github.com/maajix/omarchy-spotlight), the command palette plugin for Omarchy. The site is hand-written static HTML in `static/`; Hugo only copies it into `public/`, and the workflow in `.github/workflows/static.yml` deploys it to GitHub Pages on every push to `gh-pages`.

```bash
hugo server          # http://localhost:1313/omarchy-spotlight/
hugo --gc --minify   # build into public/
```

- `static/index.html`: the landing page.
- `static/docs/index.html`: all docs pages in one file. Each page is an `<article data-slug>`, shown at `docs/?p=<slug>`; the sidebar, table of contents and search index are built from the articles.
- `static/404.html`: served by GitHub Pages for any missing path, so its links are absolute (`/omarchy-spotlight/...`).
- `static/robots.txt`, `static/sitemap.xml`, `static/llms.txt`: served as is.

When a release ships, update the version in the landing page JSON-LD (`softwareVersion`), the docs header button, the docs changelog and `llms.txt`.
