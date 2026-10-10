#!/bin/sh
# Neon Refresh through Vite in headless Chrome. Every scenario runs on a copy of
# these sources under out/refreshVite, so the tracked files are never edited.
# --install-links copies the recompiler's Vite plugin into node_modules so it
# resolves magic-string from there; a symlinked plugin resolves from recompiler.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
npm install --prefix "$here" --install-links --no-package-lock --no-audit --no-fund --loglevel=error
node "$here/drive.mjs"
