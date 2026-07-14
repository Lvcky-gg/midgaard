# Midgaard Geospatial MVP

This workspace is a first vertical slice for an Esri-like geospatial platform in Odin.

## What is in this MVP

- A shared Odin core for coordinates, layers, features, and routes.
- A native Odin entry point that prints the demo scene summary.
- A browser/WebGL client that renders a 3D globe with imagery, feature points, and route overlays.
- A cvulkan backend stub so the native render path has a defined seam.

## Layout

- `main.odin` - native entry point.
- `geo.odin` - coordinate math and shared types.
- `demo.odin` - built-in sample scene.
- `cvulkan_stub.odin` - native backend seam.
- `web/` - browser MVP.

## Run

Native Odin demo:

```bash
odin run .
```

Web demo:

Open `web/index.html` in a browser.

## MVP scope

The MVP is intentionally small:

- 3D globe first.
- Imagery as a first-class surface layer.
- Feature layers as semantic points and routes.
- Shared model for later native and web renderers.
