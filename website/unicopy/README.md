# UniCopy website

Live at **https://musaamir.github.io/UniCopy/**, hosted on GitHub Pages.

A buildless page: `dist/index.html`, `dist/styles.css`, `dist/app.js` and `dist/assets/`.
Preview locally from this folder:

```sh
python3 -m http.server 4173 --directory dist
```

Pushing changes under `website/unicopy/dist/` to `main` runs the
[Pages workflow](../../.github/workflows/pages.yml), which checks the JavaScript and publishes `dist/`.

## Content

- The hero demo (desktop, windows, menu bar, UniCopy menu and capture overlay) is built in HTML.
  It "recognises" the page's own text inside the selected area; the app reads real pixels with Apple Vision.
  The three Settings images are real screenshots of UniCopy.
- Download links point to the GitHub releases page. Once a release is published, link straight to its zip.
- Apple's system font. No web fonts, analytics, cookies or third-party requests.
- Wallpaper by Andrew Ridley on Unsplash (Unsplash License), credited in the footer.
