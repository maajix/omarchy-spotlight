# Spotlight website

Landing page and documentation for [Spotlight](https://github.com/maajix/omarchy-spotlight), the command palette plugin for Omarchy. The site is hand-written static HTML in `static/`. On every push to `gh-pages`, the Pages workflow builds and uploads the site, then the deploy job publishes that artifact. [Pages workflow](.github/workflows/static.yml)

```bash
hugo server          # http://localhost:1313/omarchy-spotlight/
hugo --minify --cleanDestinationDir
node tests/site.test.cjs
```

- `static/index.html`: the landing page.
- `static/docs/index.html`: all docs pages in one file. Each page is an `<article data-slug>`, shown at `docs/?p=<slug>`; the sidebar, table of contents and search index are built from the articles.
- `static/404.html`: served by GitHub Pages for any missing path, so its links are absolute (`/omarchy-spotlight/...`).
- `static/robots.txt`, `static/sitemap.xml`, `static/llms.txt`: served as is.

## Updating for a release

1. Read the version in `manifest.json` on `main`. Use the Git history to fill in the changelog in `static/docs/index.html`, newest release first.
2. Match that version in the docs header and **Updated for** footer, the landing page JSON-LD (`softwareVersion`) and `static/llms.txt`.
3. Update the `/docs/` modification date in `static/sitemap.xml` when the docs content changes.
4. Run the site test and Hugo build above. After pushing, check the Pages deployment.

## AI showcase

The AI showcase reuses the landing page's palette and timer tabs. Its examples use local artwork and sample data; update them alongside the plugin's card layouts. Keep the showcase height fixed and check every card at desktop and phone widths when changing its content.
