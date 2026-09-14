# TideBar Website

Astro static site for the TideBar product portal.

## Commands

```bash
npm install
npm run dev
npm run build
npm run preview
```

The site is deployed to GitHub Pages by `.github/workflows/website.yml` when files under `website/` change on `main`.

The site uses a desktop-style layout. The bottom navigation expands on hover and switches between content panels. It illustrates the bar interaction; it is not a recording of the app. Viewports ≤820px and no-JS fall back to a stacked scrolling layout with the same DOM.

Useful query params for testing: `?theme=light|dark` overrides the color theme; a `#features`/`#privacy`/`#download`/`#source` hash deep-links into a window.
