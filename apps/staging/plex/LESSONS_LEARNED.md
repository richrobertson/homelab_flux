# Plex VAAPI Staging Lessons Learned

## Scope

- Objective: make Plex hardware transcode (VAAPI on Intel i915) work in staging using a custom image while keeping staging recoverable.
- Method: iterative build and isolated probe workflow (scale Plex down, run one-shot GPU probe pod, restore Plex).

## What We Verified

- The staging node and plugin path are healthy:
  - `ghcr.io/linuxserver/ffmpeg:latest` could initialize VAAPI (`iHD`) on the same GPU node.
- Driver path and missing dependency issues were real and fixable:
  - Missing driver path (`LIBVA_DRIVERS_PATH`) was corrected.
  - Missing `libigdgmm.so.12` was identified and supplied.
- `vainfo` success alone is not enough:
  - We reached successful `vainfo` with `iHD`, but Plex Transcoder still failed due to runtime ABI/library interactions.

## Root Cause Pattern

- Main failure mode was mixed runtime ABI expectations:
  - Plex runtime in this image path behaves as musl-oriented.
  - Injected VAAPI stack components are glibc-oriented.
  - Forcing global glibc library search paths can make probes pass but destabilizes Plex Transcoder runtime.

## High-Signal Error Signatures

- Driver/dependency mismatch:
  - `dlopen ... iHD_drv_video.so failed: libigdgmm.so.12: cannot open shared object file`
- Driver/libva interface mismatch:
  - `has no function __vaDriverInit_1_0` or mismatched `__vaDriverInit_*`
- Runtime ABI mismatch:
  - Repeated `Error relocating ... __isoc23_* symbol not found`

## Effective Workflow Guardrails

- Always capture and restore baseline before and after probes.
- Keep probes isolated to a single pod with explicit GPU request/limit and node selector.
- Validate in this order:
  1. file presence and paths
  2. `ldd` dependencies
  3. `vainfo`
  4. `Plex Transcoder` end-to-end test
- Treat `Plex Transcoder` as the final truth, not `vainfo`.

## Decision Outcome

- Staging should be reset to production-like behavior without GPU passthrough until a single-libc-compatible image strategy is used.
- Avoid global `LD_LIBRARY_PATH` overrides in Plex runtime images.