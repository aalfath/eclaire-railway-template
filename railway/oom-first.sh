#!/bin/sh
# Wrapper for Chromium and LibreOffice: makes them the kernel's first choice if the
# service runs out of memory, so a heavy page or document fails that one job instead
# of killing the whole Eclaire process. Raising oom_score_adj needs no privileges.
echo 1000 > /proc/self/oom_score_adj 2>/dev/null || true
real="$0.real"
case "$(basename "$0")" in
  chrome*|chrome-headless-shell)
    exec "$real" --disable-dev-shm-usage --renderer-process-limit=1 --disable-gpu \
      --disable-site-isolation-trials --disable-features=site-per-process,IsolateOrigins \
      --disable-extensions --mute-audio --js-flags=--max-old-space-size=192 "$@" ;;
  *)
    exec "$real" "$@" ;;
esac
