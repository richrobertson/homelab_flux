# Plex Hardware Transcoding Experiment Recap

**Date**: 2026-04-22  
**Scope**: Staging and production Plex GPU rollout, VAAPI image investigation, and live transcoding diagnostics  
**Status**: Production Plex is healthy and GPU-capable, but some real-world Plex transcodes still fall back to software because Plex cannot use a full hardware pipeline for every source/client combination.

## Executive Summary

We completed the Kubernetes and Proxmox-side GPU rollout for Plex and verified that production Plex has:

- Intel iGPU devices available inside the container
- Plex hardware-transcoding settings enabled
- successful full VAAPI transcoding for some historical sessions

The remaining issue is narrower than "hardware transcoding is broken":

- production Plex can use VAAPI for some sessions
- the current problematic Chrome/Plex Web DASH session on `Wallace & Gromit: The Curse of the Were-Rabbit` falls back to software
- the fallback is caused by a failure in the hardware resize path for that specific source and playback shape, not by missing GPU passthrough, bad Kubernetes scheduling, or disabled Plex settings

## Infrastructure Changes Completed

### Kubernetes and VM rollout

- Enabled Intel iGPU passthrough on the production worker nodes
- Verified production workers advertise:
  - `intel.feature.node.kubernetes.io/gpu=true`
  - `gpu.intel.com/i915=1`
- Verified prod Plex is scheduled onto a GPU-capable worker
- Disabled the staging GPU rollout after validating the staging path and shifted the long-term GPU target to production only

### Live runtime state

- Production pod:
  - `default/plex-0`
  - running on `k8s-prod-worker-1`
- Devices present in container:
  - `/dev/dri/card0`
  - `/dev/dri/renderD128`
- Prod image:
  - `ghcr.io/richrobertson/plex-vaapi:20260411-160525`

## Plex Configuration Verified

### Server-side settings

Verified live in Plex UI and from `Preferences.xml`:

- `Use hardware acceleration when available`: enabled
- `Use hardware-accelerated video encoding`: enabled
- selected device:
  - `Intel Raptor Lake-P [Iris Xe Graphics]`
- `HardwareAcceleratedCodecs="1"`
- `HardwareDevicePath="8086:a7a0@0000:01:00.0"`

### Transcoder binary capabilities

Inside the running prod pod, `Plex Transcoder -encoders` reported:

- `h264_vaapi`
- `hevc_vaapi`
- `h264_nvenc`
- `hevc_nvenc`

So the Plex binary advertises VAAPI encode support.

## Initial Production Failure Symptom

The user observed a live production playback session in Plex Web / Chrome that showed:

- source video:
  - `4K (H.264 Constrained Baseline)`
- output:
  - `1080P (H264) — Transcode`
- audio:
  - `AC3 5.1 -> AAC — Transcode`

Despite the UI indicating a video transcode, the active server-side process showed software encoding:

```text
-codec:0 libx264
```

That means Plex was doing CPU video encode for that session.

## Live Diagnostics Performed

### 1. Active process inspection

Checked the running transcoder process in the prod pod.

Observed:

- active Wallace session used:
  - `-codec:0 libx264`
  - `-codec:1 aac`
- this confirmed software video encode for the current session

### 2. Plex logs and session statistics

Inspected:

- `Plex Media Server.log`
- `Plex Transcoder Statistics.log`

Observed for the live Wallace session:

- `protocol="dash"`
- `transcodeHwRequested="1"`
- `transcodeHwFullPipeline="0"`
- repeated progress reports with:
  - `vdec_hw_status=0`

Interpretation:

- Plex requested hardware transcoding
- hardware decode never became active for the current session
- the full hardware pipeline was not established

### 3. Historical Plex session review

Searched rotated transcoder statistics logs.

Confirmed prior successful hardware sessions existed:

- `protocol="hls"`
- `sourceVideoCodec="hevc"`
- `transcodeHwDecoding="vaapi"`
- `transcodeHwEncoding="vaapi"`
- `transcodeHwFullPipeline="1"`

Important negative findings:

- no confirmed `dash` sessions with `transcodeHwFullPipeline="1"`
- no confirmed historical `h264` source sessions with `transcodeHwEncoding="vaapi"`

Interpretation:

- the prod image is not universally broken
- full VAAPI has already worked on this server
- the failing path is narrower and appears associated with certain source/client combinations

## Image and ABI Experiments

### 4. Current custom image ABI checks

Inspected the `Plex Transcoder` linkage in the running prod pod.

Observed:

- `Plex Transcoder` links to bundled Plex runtime libraries in `/usr/lib/plexmediaserver/lib`
- notably:
  - `libc.so`
  - `libgcompat.so.0`
  - `libva.so.2`
  - `libva-drm.so.2`
  - `libdrm.so.2`

This reinforced the earlier suspicion that Plex's bundled runtime is a major part of the VAAPI behavior.

### 5. Direct VAAPI probe in the running prod pod

Ran a direct `Plex Transcoder` VAAPI init test against `/dev/dri/renderD128`.

Observed:

- `Failed to initialise VAAPI connection: -1`

Also tested explicit driver paths and variants.

Observed failures including:

- `dlopen ... iHD_drv_video.so failed`
- `dlopen ... i965_drv_video.so failed`
- repeated relocation failures involving:
  - `__isoc23_* symbol not found`

Interpretation:

- the custom image still has ABI/runtime tension between Plex's bundled runtime and the VAAPI driver stack

### 6. Live library swap experiment

Temporarily replaced bundled Plex `libva` / `libdrm` libraries inside the running prod pod with system copies.

Observed:

- `Plex Transcoder` broke with relocation errors
- the replacement approach was not safe in-place

Action taken:

- restored the original bundled libraries from backup

Result:

- pod returned to normal operation
- software-transcoding session continued

Conclusion:

- the simple "swap bundled libva/libdrm with system versions" approach is not safe as an in-place production hack

### 7. Repository history review

Reviewed prior `docker-builds/plex-vaapi` Dockerfile revisions.

Strategies previously attempted in Git history included:

- linuxserver base with musl-oriented VAAPI driver bundle
- linuxserver base with system glibc driver imports
- linuxserver base with global library path overrides
- official Plex base image variant
- direct replacement of bundled `libva/libdrm` with system versions

High-signal historical lesson:

- global `LD_LIBRARY_PATH` overrides and naive library replacement led to instability or `__isoc23_*` relocation failures

## Throwaway Official Plex Image Test

### 8. Temporary test pod using the official Plex image

Created a throwaway prod test pod:

- image:
  - `plexinc/pms-docker:1.43.1.10611-1e34174b1`
- requested one `gpu.intel.com/i915`

Installed VAAPI userspace packages in the pod and tested:

- `vainfo`
- direct `Plex Transcoder` VAAPI init

Observed:

- `vainfo` succeeded
- direct `Plex Transcoder` VAAPI init still failed with:
  - `Failed to initialise VAAPI connection: -1`

Interpretation:

- simply switching to the official Plex base image does not automatically solve the VAAPI issue
- "use official base only" is not enough by itself

Cleanup:

- deleted the throwaway test pod after validation

## FFmpeg Matrix on the Problem File

To isolate whether the problem was the file, the GPU, the encoder, or the scaling stage, we ran a targeted ffmpeg matrix inside the prod Plex pod.

### 9. Synthetic encoder tests

Results:

- 1080p synthetic source -> hardware encode:
  - passed
- 4K synthetic source -> hardware encode:
  - passed
- 4K synthetic source -> hardware scale + hardware encode:
  - passed

Interpretation:

- the Intel GPU encoder and hardware scaler both work in general

### 10. Wallace file tests

Source file characteristics from `ffprobe`:

- codec:
  - `h264`
- profile:
  - `Constrained Baseline`
- dimensions:
  - `3840x2076`
- pixel format:
  - `yuv420p`
- progressive
- no B-frames

Results:

- Wallace -> software encode:
  - passed
- Wallace -> hardware decode + hardware encode, no scale:
  - passed
- Wallace -> software decode + hardware encode, no scale:
  - passed
- Wallace -> CPU scale to `1920x1038` + hardware encode:
  - passed
- Wallace -> hardware scale to `1920x1038` + hardware encode:
  - failed
- Wallace -> hardware scale to nearby heights (`1040`, `1036`) + hardware encode:
  - failed

Error from failing cases:

```text
Error while filtering: Cannot allocate memory
Failed to inject frame into filter network
```

Interpretation:

- the encoder is not the problem
- hardware decode is not the problem
- the Wallace file specifically fails once it enters the VAAPI resize path
- Plex likely needs a viable all-hardware path for this client/session type
- when the VAAPI resize step fails, Plex falls back to a software pipeline rather than using the hybrid `CPU scale + GPU encode` path that plain `ffmpeg` can use

## What We Learned

### Confirmed working

- Intel iGPU passthrough in Kubernetes
- device plugin allocation
- Plex pod scheduling on GPU workers
- Plex UI configuration for hardware transcoding
- VAAPI access inside the container
- full VAAPI transcoding for some historical HEVC/HLS sessions
- GPU encode on synthetic sources
- GPU encode on the Wallace source when scaling is removed
- hybrid `CPU scale + GPU encode` on the Wallace source using plain `ffmpeg`

### Confirmed not working

- current Chrome / Plex Web DASH Wallace session as full VAAPI
- direct VAAPI init in the current custom prod image
- direct VAAPI init in a plain official Plex image with packages installed
- hardware scaling of the Wallace source with VAAPI

### Main conclusion

Production hardware transcoding is not globally broken.

The current production issue is:

- a file-and-playback-shape-specific limitation in Plex's hardware pipeline
- most clearly reproduced as:
  - Wallace source + 4K H.264 constrained baseline + Plex Web / Chrome + DASH + downscale to 1080p

For this path:

- hardware resize fails
- Plex falls back to software video transcode

## Practical Guidance Going Forward

### Short-term workaround

For titles like this one:

- use a client/playback path that avoids this exact browser DASH transcode
- pre-optimize the file to a 1080p copy
- re-encode the source into a format/profile Plex handles more reliably for GPU full-pipeline transcode

### Medium-term investigation path

If we want to keep pushing this further, the next worthwhile areas are:

- determine whether Plex can be coerced into a hybrid path for problematic files
  - CPU scale + GPU encode
- identify whether this is an H.264 constrained-baseline-specific issue, a `3840x2076` issue, or a broader DASH/browser limitation
- create a repeatable test corpus:
  - HEVC 4K source
  - H.264 4K source with common profiles
  - H.264 4K constrained baseline odd-height source
- compare Plex Web / Chrome DASH against another client or protocol path on the same source

## Current Recommended Repo Position

- Keep production on the current GPU-capable rollout
- Keep staging off the GPU path for now
- Preserve the current image docs, but treat them as experimental rather than a completed solution
- Use this recap plus `apps/staging/plex/LESSONS_LEARNED.md` as the reference set before making the next image change

## Related Files

- [docker-builds/plex-vaapi/Dockerfile](./Dockerfile)
- [docker-builds/plex-vaapi/README.md](./README.md)
- [PLEX_VAAPI_OPTION3_RUNBOOK.md](../../docs/runbooks/PLEX_VAAPI_OPTION3_RUNBOOK.md)
- [apps/staging/plex/LESSONS_LEARNED.md](../../apps/staging/plex/LESSONS_LEARNED.md)
- [apps/prod/plex/README.md](../../apps/prod/plex/README.md)
