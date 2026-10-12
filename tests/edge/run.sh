#!/bin/sh
# Neon edge lane: a page built with --target=js answers requests inside workerd, the
# Cloudflare Workers runtime, served locally from tests/edge/config.capnp.
# Setup once per checkout: npm install --prefix tests/edge
set -e
cd "$(dirname "$0")/../.."
MSC=${MSC:-msc}

WORKERD=${NEON_WORKERD:-$PWD/tests/edge/node_modules/workerd/bin/workerd}
if [ ! -f "$WORKERD" ]; then
	echo "workerd not found at $WORKERD — run: npm install --prefix tests/edge" >&2
	exit 2
fi

mkdir -p tests/edge/out
"$MSC" build --target=js tests/edge/pages.ms --output=tests/edge/out/pages.js
node tests/edge/run.mjs "$WORKERD"
