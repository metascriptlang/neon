#!/bin/sh
# Neon edge lane, streaming: a worker answers with a streamed render (a Response over the render's
# readable), and the client reads the shell before the slow read is allowed to settle.
# Setup once per checkout: npm install --prefix tests/edge, and --prefix tests/browser for Chrome
set -e
cd "$(dirname "$0")/../.."
MSC=${MSC:-msc}

case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) WORKERD_BIN=$PWD/tests/edge/node_modules/@cloudflare/workerd-windows-64/bin/workerd.exe ;;
*) WORKERD_BIN=$PWD/tests/edge/node_modules/workerd/bin/workerd ;;
esac
WORKERD=${NEON_WORKERD:-$WORKERD_BIN}
if [ ! -f "$WORKERD" ]; then
	echo "workerd not found at $WORKERD — run: npm install --prefix tests/edge" >&2
	exit 2
fi

echo "== edge tests/edge/streamRun.sh"
mkdir -p tests/edge/out
"$MSC" build --target=js -d:server tests/edge/streamPages.ms --output=tests/edge/out/streamPages.js
node tests/edge/streamRun.mjs "$WORKERD" "${NEON_PLAYWRIGHT:-$PWD/tests/browser/node_modules/playwright-core/index.mjs}"
