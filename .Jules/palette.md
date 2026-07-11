## 2026-07-06 - Backend-Rendered HTML Forms UX Insight
**Learning:** In purely backend-rendered Python templates (like FastAPI generating HTML directly), adding standard Javascript `onsubmit` confirmation dialogs is a highly effective, zero-dependency way to prevent destructive actions (like stopping clusters or cleaning workers) without introducing complex frontend frameworks.
**Action:** When working on backend-rendered UI projects without a dedicated frontend framework, prioritize native browser features (like `confirm()`) and semantic HTML (like `role="alert"`) for immediate UX and accessibility wins before reaching for external libraries or custom Javascript.

## 2024-07-11 - Adding Tooltips to Disabled Fieldset Content
**Learning:** `pointer-events: none` applied via CSS (e.g. `fieldset[disabled] { pointer-events: none; }`) drops pointer events to all descendant elements, making them immune to native HTML tooltip hover logic via `title`.
**Action:** Wrap the disabled element (like a button inside a disabled fieldset) in a `<span>` (or `<div>`) with `pointer-events: auto` to allow hover events to register, thus re-enabling native tooltips on elements that are otherwise disabled.
