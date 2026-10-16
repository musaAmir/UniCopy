# UniCopy

Select an area of your Mac screen and copy its text.

macOS 14+ · Apple silicon & Intel · Local development version 0.1.0

Press **Control–Option–C**, drag over text, and release. Escape cancels. Successful recognition copies text with a small confirmation; the menu can reopen the editable result. If you copied something else while recognition was running, UniCopy preserves that newer clipboard and opens a review instead.

- Local Apple Vision OCR, with optional line joining and language correction.
- Defaults to supported Mac preferred languages plus English. Optional automatic detection supports other Vision languages.
- Recognition runs only when requested. Its helper exits after each image. The first request can take longer while macOS prepares the recognition model.
- One temporary text result, no screenshot files, no uploads or background recording.
- Optional launch at login; menu fallback if the shortcut is already registered.

Build: `./build.sh universal` · Test: `swift test`

Packaged helper check: `build/UniCopy.app/Contents/MacOS/UniCopy --test-worker`

Open `build/UniCopy.app`. **Try Sample Text** works without screen access and does not change your clipboard. For screen capture, use **Enable Screen Recording…** and approve UniCopy under System Settings → Privacy & Security → Screen Recording. macOS may ask you to quit and reopen the app.

If Settings shows UniCopy enabled but Preferences still asks for access after restarting, remove its Screen Recording entry and add the current `build/UniCopy.app` again. Rebuilding these ad-hoc signed development versions can invalidate an earlier permission grant.

Select within one display per capture. Large regions are limited to 4096 pixels per edge to bound memory. OCR can misread small text, code, complex columns, or unsupported languages; the result is editable.

These local builds are ad-hoc signed and not notarized. No update feed or public release has been configured yet. Automated tests use generated images; actual screen capture and mixed-scale physical displays require hands-on testing after approval.
