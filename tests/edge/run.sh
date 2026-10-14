#!/bin/sh
# Neon edge lane: a page built with --target=js answers requests inside workerd, the
# Cloudflare Workers runtime, served locally from tests/edge/config.capnp.
# The routed site of examples/site answers from a second worker and Chrome hydrates what it sent.
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

echo "== edge tests/edge/run.sh"
mkdir -p tests/edge/out
"$MSC" build --target=js tests/edge/pages.ms --output=tests/edge/out/pages.js
"$MSC" build --target=js examples/site/server.ms --output=tests/edge/out/site.js
"$MSC" build --target=js examples/site/client.jms --output=tests/edge/out/siteClient.js
node tests/edge/run.mjs "$WORKERD" "${NEON_PLAYWRIGHT:-$PWD/tests/browser/node_modules/playwright-core/index.mjs}"
