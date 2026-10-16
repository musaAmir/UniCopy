# Recognition lifecycle

UniCopy captures one selected region with ScreenCaptureKit and sends a PNG through pipes to a packaged helper. The helper performs Apple Vision OCR and exits. Images never need temporary disk files; only the latest recognised text is retained in the app.

The first accurate Vision request can spend significant time preparing its model. A packaged synthetic fixture took about 14 seconds on this Mac, followed by 0.31 seconds in a fresh helper using the prepared cache. An early 25-second timeout sometimes killed cold initialisation before it completed. The worker now allows up to 60 seconds, supports cancellation, and defaults to the Mac's supported preferred languages plus English. Automatic language detection is optional.

The regression command `build/UniCopy.app/Contents/MacOS/UniCopy --test-worker` sends a generated invoice through the real packaged helper twice. It allows model preparation for the first request, then requires a new helper to return the expected text within five seconds. It does not access the screen or clipboard. Timing varies by hardware and macOS version.

The UI test uses Try Sample Text. No screen permission is needed for that path. Screen Recording approval is required for a real selection/capture test. Mixed-scale monitors, Spaces, and fullscreen apps still need hands-on checks.
