# Recording GIF export

Save as GIF and Copy as GIF share a streaming exporter. Each rendered frame is
quantized and LZW-compressed by a separate single-image ImageIO destination.
Its color table and compressed image block are appended to a GIF89a file on
disk, using a local color table for each frame. Decoded frames and the complete
encoded animation do not accumulate in memory. This removes the former
300-frame cap (20 seconds at 15 fps or 25 seconds at 12 fps), without introducing
an external encoder dependency. Longer GIFs still require proportionally more
encoding time and disk space.

The animation loops indefinitely. GIF centisecond delays follow the cumulative
frame clock, alternating delays where necessary to avoid drift at 12 and 15 fps.
Every frame covers the canvas and restores the background between frames, so
transparency cannot expose pixels from a preceding frame. The existing edit
composition still applies trim, cuts, export speed and visual effects.

## Temporary-file lifetime

- Export scratch lives under the current user's macOS temporary directory in
  `<bundle identifier>/GIF Exports/<export UUID>/animation.gif`. Directories are
  owner-only (0700); GIF and lease files are owner-only (0600).
- Success, cancellation and failure remove that export's scratch directory
  immediately. A completed GIF is first copied to a hidden sibling of the final
  destination, then atomically moved into place. An existing saved file survives
  failure or cancellation. A write error is reported instead of silently losing
  frames or publishing a partial GIF.
- App startup and the next GIF export sweep abandoned scratch directories.
  Each live export holds a kernel file lock, including across app processes.
  A crash releases the lock; cleanup can remove its directory immediately
  without guessing an expiry time. A separate root lock serializes creation and
  sweeping. Empty root/lease infrastructure can remain for reuse. macOS may also
  purge temporary storage; application cleanup is the primary policy.
- The hidden destination sibling is removed on every normal exit. A crash
  during the final copy can leave that sibling beside the destination; startup
  does not search arbitrary save folders. The original destination remains
  intact. Encoding itself happens in app temporary storage.
- A clipboard copy is a completed artifact, separate from export scratch. It
  remains in `~/Library/Caches/<bundle identifier>/Copied Recordings`, because
  the pasteboard includes both native GIF bytes and a file URL for attachment
  consumers. The existing policy removes copies older than 24 hours when the
  next recording is copied. Saved GIFs and editable recording masters retain
  their existing lifetimes.

## Verification

```sh
./build.sh --test-suite=recorder
./build.sh --dev --install
./build/VorssaintDeveloper --selftest
```

Automated fixtures export and copy a 30-second, 450-frame GIF at 15 fps through
the production exporter. Separate 450-frame writer fixtures decode every frame
at 8, 12 and 15 fps, comparing palettes and alpha with native single-image GIF
output. Tests cover total timing, cancellation preserving the destination,
failed publication, live leases, released crash leases and abandoned directories
created before their lease file exists.

A standalone optimized encoder probe with changing 600×400 frames measured
maximum resident memory using `/usr/bin/time -l`: the previous multi-image
ImageIO encoder used 808,288,256 bytes for 300 frames; the streaming writer used
19,529,728 bytes for 300 and 19,513,344 bytes for 1,800. These are encoder-only
measurements, not whole-app memory guarantees; AVFoundation rendering, the
editor and pasteboard publication have their own memory costs.

Validation on Apple Silicon, macOS 27.0.1: the recorder suite passed all 699
checks; the Developer app built, installed, passed selftest and strict signature
verification, and was launched. A separate SIGKILL probe bypassed all normal
cleanup and confirmed that the next sweep removed the abandoned workspace.
The full suite passed 115,929 of 115,930 checks. Its single failure at
`Tests/NotchCompactTests.swift:218` also reproduced in a clean checkout of
`origin/main` at `fe24c176`, with no GIF changes. Physical capture and pasting
into third-party apps remain manual checks.

For a manual check, record over 30 seconds, then save and copy at 15 fps. Check
the end of the animation and playback duration. Cancel another export partway
through and verify no partial GIF replaces a saved file. Use a destination on
another volume to exercise the completed-file copy and atomic replacement.
