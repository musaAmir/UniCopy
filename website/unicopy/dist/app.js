// UniCopy website. The page reads fine without this script; it adds the live demo.
document.documentElement.classList.add("js");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Scale the 1280 × 800 desktop to fit its screen.
const screen = document.querySelector(".screen");
const desktop = document.querySelector(".desktop");
new ResizeObserver(([entry]) => desktop.style.setProperty("--scale", entry.contentRect.width / 1280)).observe(screen);

// Capture mode: drag a rectangle; every line of text whose middle falls inside it is "recognised".
const overlay = document.querySelector(".capture");
const marquee = document.querySelector(".marquee");
const hud = document.querySelector(".hud");
const clipboard = document.querySelector(".clipboard");
const clipboardText = document.getElementById("clipboard-text");
const lastItem = document.querySelector('[data-action="last"]');
let origin = null, hudTimer;

function startCapture() {
  closeMenu(); desktop.classList.add("has-tried");
  overlay.hidden = false; marquee.hidden = true; overlay.classList.remove("is-dragging");
}
function endCapture() { overlay.hidden = true; origin = null; }
// Pointer position in the desktop's own 1280 × 800 coordinates.
function local(event) {
  const box = desktop.getBoundingClientRect(), scale = box.width / 1280;
  return { x: (event.clientX - box.left) / scale, y: (event.clientY - box.top) / scale };
}
function rectFrom(a, b) {
  return { left: Math.min(a.x, b.x), top: Math.min(a.y, b.y), width: Math.abs(a.x - b.x), height: Math.abs(a.y - b.y) };
}
overlay.addEventListener("pointerdown", (event) => {
  origin = local(event); overlay.setPointerCapture(event.pointerId);
  overlay.classList.add("is-dragging"); marquee.hidden = false;
  Object.assign(marquee.style, { left: origin.x + "px", top: origin.y + "px", width: "0px", height: "0px" });
});
overlay.addEventListener("pointermove", (event) => {
  if (!origin) return;
  const r = rectFrom(origin, local(event));
  Object.assign(marquee.style, { left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
});
overlay.addEventListener("pointerup", (event) => {
  if (!origin) return;
  const r = rectFrom(origin, local(event));
  endCapture();
  if (r.width < 5 || r.height < 5) return;
  recognise(r);
});

function recognise(r) {
  const box = desktop.getBoundingClientRect(), scale = box.width / 1280;
  const lines = [...document.querySelectorAll("[data-ocr]")].filter((el) => {
    const e = el.getBoundingClientRect();
    const cx = (e.left + e.width / 2 - box.left) / scale, cy = (e.top + e.height / 2 - box.top) / scale;
    return cx >= r.left && cx <= r.left + r.width && cy >= r.top && cy <= r.top + r.height;
  }).map((el) => el.innerText.replace(/\s*\n\s*/g, " ").trim()
      // Receipt rows set the price apart with layout, not spaces.
      .replace(/^(.*?)(\d+\.\d\d)$/, (m, label, price) => label.trim() + " " + price));
  if (!lines.length) { showHud("No text found", false); return; }
  const text = lines.join("\n");
  navigator.clipboard?.writeText(text).catch(() => {});
  showHud(`Copied ${text.length} characters`, true);
  clipboardText.textContent = text; clipboard.hidden = false; clipboard.classList.add("is-in");
  lastItem.disabled = false;
}
function showHud(message, ok) {
  clearTimeout(hudTimer);
  hud.querySelector("span").textContent = ok ? "✓" : "–";
  hud.querySelector("b").textContent = message;
  hud.hidden = true; void hud.offsetWidth; hud.hidden = false;
  hudTimer = setTimeout(() => { hud.hidden = true; }, 2000);
}

// The menu bar item and its menu.
const item = document.querySelector(".app-item");
const menu = document.querySelector(".app-menu");
function closeMenu() { menu.hidden = true; item.setAttribute("aria-expanded", "false"); }
item.addEventListener("click", (event) => {
  event.stopPropagation(); desktop.classList.add("has-tried");
  const open = menu.hidden;
  menu.hidden = !open; item.setAttribute("aria-expanded", String(open));
  if (open && event.detail === 0) menu.querySelector("button").focus({ preventScroll: true });
});
menu.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button || button.disabled) return;
  event.stopPropagation();
  const action = button.dataset.action;
  closeMenu();
  if (action === "capture") startCapture();
  if (action === "last") clipboard.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "center" });
  if (action === "settings") document.getElementById("features").scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth" });
});
document.addEventListener("click", closeMenu);
document.querySelector("[data-start]").addEventListener("click", (event) => { event.stopPropagation(); startCapture(); });
addEventListener("keydown", (event) => {
  if (event.key === "Escape") { closeMenu(); endCapture(); }
  if (event.ctrlKey && event.altKey && event.code === "KeyC") { event.preventDefault(); startCapture(); }
});

// Features: each one shows its page of the real Settings window.
const features = [...document.querySelectorAll(".feature")];
const shots = [...document.querySelectorAll(".shot img")];
function show(feature) {
  features.forEach((f) => { f.classList.toggle("is-on", f === feature); f.setAttribute("aria-selected", String(f === feature)); });
  shots.forEach((img) => img.classList.toggle("is-on", img.dataset.name === feature.dataset.shot));
}
features.forEach((f) => {
  f.addEventListener("click", () => show(f));
  f.addEventListener("mouseenter", () => { if (matchMedia("(hover: hover)").matches) show(f); });
});

// Entrances: each section's parts rise in turn as it enters.
const reveals = new IntersectionObserver((entries) => entries.forEach((entry) => {
  if (!entry.isIntersecting) return;
  entry.target.classList.add("is-in"); reveals.unobserve(entry.target);
}), { rootMargin: "0px 0px -6% 0px" });
document.querySelectorAll("section").forEach((section) => {
  section.querySelectorAll(".reveal").forEach((el, i) => { el.style.setProperty("--i", i); reveals.observe(el); });
});
