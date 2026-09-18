# Spotlight website

Landing page and documentation for [Spotlight](https://github.com/maajix/omarchy-spotlight), the command palette plugin for Omarchy. Built with Hugo, no theme dependency, deployed to GitHub Pages by the workflow in `.github/workflows/hugo.yml`.

```bash
hugo server          # http://localhost:1313/hugo-spotlight/
hugo --gc --minify   # build into public/
```

Docs live in `content/docs/`. The plugin version shown on the site is `params.version` in `hugo.toml`.
