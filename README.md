# Midgaard Geospatial MVP

This workspace is a first vertical slice for an Esri-like geospatial platform in Odin.

## What is in this MVP

- A shared Odin core for coordinates, layers, features, and routes.
- A native Odin entry point that prints the demo scene summary.
- A browser/WebGL client that renders a 3D globe with imagery, feature points, and route overlays.
- A cvulkan backend stub so the native render path has a defined seam.

## Layout

- `main.odin` - native entry point.
- `geo_app/` - native app loop, input wiring, scene bootstrap.
- `geo_core/` - camera, mesh generation, math/types.
- `geo_layers/` - scene model and imagery tile addressing.
- `geo_ingest/` - edge cache and bundle ingest helpers.
- `geo_sync/` - fetch queue and network worker helpers.
- `geo_cvulkan/` - Vulkan device/swapchain/pipeline/frame/texture code.
- `geo_render/` - shared render-facing structs (push constants, commands).
- `geo_style/`, `geo_catalog/`, `geo_webgl/` - style/catalog/web backend stubs.
- `web/` - browser MVP.

## Run

Native Odin demo:

```bash
odin run .
```

Native compile check:

```bash
odin check .
```

Web demo:

Open `web/index.html` in a browser.

## Native Usage

### Controls

- Left mouse drag: orbit (rotate around the globe).
- Left click (no drag): select the feature under the cursor; clicking empty
  space clears the selection. The picked feature pulses and its details print
  to the console.
- Right mouse drag: tilt (change elevation angle only).
- Mouse wheel: zoom in/out.
- `Esc`: close window.

### Interaction Tuning

- Orbit drag sensitivity is intentionally reduced to avoid over-rotation.
- Zoom speed scales with distance so far-away zoom is faster and close-in zoom is precise.

## Imagery and Streaming

Midgaard uses edge-first imagery lookup:

1. Cache (`./.cache/imagery/base/...`)
2. Offline bundle (`./edge_bundles/imagery/base/...`)
3. Remote fetch (ArcGIS export/tile endpoints)

At startup, the app warms a small seed tile set and may fetch missing tiles. During runtime it:

- Prefetches around camera focus.
- Deduplicates fetch queue entries.
- Throttles fetch work to reduce interaction lag.
- Swaps world imagery LOD conservatively (cooldowns + capped max texture size).

## Performance Notes

- Depth testing is enabled in Vulkan so back-side features do not render through the globe.
- Streaming work is deferred during active zoom/drag interaction to prioritize smooth camera motion.
- If interaction still feels heavy on your machine, reduce source imagery resolution or increase streaming cadence intervals in `geo_app/app.odin`.

## Cache and Data Paths

- Runtime cache: `./.cache/imagery/base/`
- Optional offline bundle root: `./edge_bundles/imagery/base/`

Safe cleanup for cached imagery:

```bash
rm -rf .cache/imagery/base
```

## Troubleshooting

- `libvulkan.so.1 not found`: install Vulkan loader packages for your distro.
- Black/fallback globe texture: verify network access to ArcGIS imagery export endpoint and check cache write permissions.
- Slow first run: expected while warming cache and downloading first imagery LODs.

## Development Package Guide

This repository is organized as small Odin packages with clear boundaries. Use this section as the default guide when adding features.

### Package Responsibilities

- `geo_app`: app composition layer. Owns lifecycle (`app_run`, init/destroy), input callbacks, and frame-to-frame orchestration.
- `geo_core`: foundational math and camera behavior. Keep it independent from rendering backends.
- `geo_layers`: domain scene model (layers/features/routes) and tile coordinate logic. No GPU code here.
- `geo_ingest`: prepares local imagery data (cache roots, bundle binding) before runtime rendering.
- `geo_sync`: async-like fetch orchestration primitives (queue/tasks/batch worker execution).
- `geo_cvulkan`: native GPU backend; Vulkan-only concerns live here.
- `geo_render`: backend-agnostic render structs shared by backends.
- `geo_style`, `geo_catalog`, `geo_webgl`: extension points for styling, catalog metadata, and WebGL bridge.

### Dependency Direction

Keep dependencies flowing inward to avoid circular coupling:

- `geo_app` -> may import all feature/backend packages.
- `geo_cvulkan` -> may import `geo_core`, `geo_layers`, `geo_render`.
- `geo_layers` -> may import `geo_core`.
- `geo_core` and `geo_render` -> should remain near-leaf/foundation packages.

Rule of thumb: if a package starts importing "up" into app orchestration, move that code to `geo_app`.

### Common Development Workflows

Add camera/input behavior:

1. Implement math/state behavior in `geo_core`.
2. Bind input event handling in `geo_app/window.odin`.
3. Trigger app-level cooldown/throttling in `geo_app/app.odin` if interaction affects frame pacing.

Add new scene/layer data:

1. Extend structs and helpers in `geo_layers`.
2. Seed demo/test data in `geo_app/demo.odin`.
3. Convert to GPU inputs in `geo_app` upload path (and backend package if needed).

Picking and labels:

- Picking is CPU-side screen-space projection (`geo_app/picking.odin` +
  `geo_core.camera_world_to_screen`), with a hemisphere test so back-side
  features cannot be selected. Run `odin test geo_app` to validate.
- Labels are billboarded text quads built once from feature names
  (`geo_layers/labels.odin`, embedded public-domain 8x8 font) and offset in
  screen space by `shaders/label.vert`; they fade past the globe horizon.
- The selected feature index rides in the shared push constants
  (`geo_render.Push_Constants.selected_index`) and drives the pulse highlight
  in `shaders/feature.vert`.

Add imagery behavior:

1. Tile addressing/probing changes go in `geo_layers/imagery.odin`.
2. Queue/fetch policy changes go in `geo_sync`.
3. Frame budget/cadence decisions stay in `geo_app/app.odin`.

Add native rendering features:

1. Backend resources/pipeline changes in `geo_cvulkan`.
2. Shared constants or command structs in `geo_render`.
3. Keep scene semantics in `geo_layers`, not Vulkan files.

### Fast Inner Loop

- Compile check: `odin check .`
- Run app: `odin run .`
- Rebuild changed GLSL: `glslc shaders/<name>.vert -o shaders/<name>.vert.spv` and/or `glslc shaders/<name>.frag -o shaders/<name>.frag.spv`

### Performance-Safe Editing Tips

- Avoid disk reads in per-frame loops; prefer probe/metadata paths.
- Gate expensive streaming/fetch work by interaction cooldowns and cadence intervals.
- Treat large texture swaps as expensive; throttle LOD switching.
- Prefer adding coarse-grained toggles in `geo_app/app.odin` for quick runtime tuning.

## MVP scope

The MVP is intentionally small:

- 3D globe first.
- Imagery as a first-class surface layer.
- Feature layers as semantic points and routes.
- Shared model for later native and web renderers.
