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

The page itself is the product demo: a simulated macOS desktop where the bottom TideBar is the navigation that switches content windows — it rests as a breathing hairline and rises on hover, exactly like the app. Viewports ≤820px and no-JS fall back to a stacked scrolling layout with the same DOM.

Useful query params for testing: `?theme=light|dark` overrides the color theme; a `#features`/`#privacy`/`#download`/`#source` hash deep-links into a window.
