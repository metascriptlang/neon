#!/bin/sh
# The layer rule of docs/navigationModel.md "Layers": routing and navigation models
# import only src/core and their own layer; renderers import no routing file.
cd "$(dirname "$0")/../.."
set -f
fail=0

imports() {
	sed -n 's/.*from "\([^"]*\)".*/\1/p' "src/navigation/$1.ms"
}

only() {
	layer=$1; allowed=$2; shift 2
	for name in "$@"; do
		if [ ! -f "src/navigation/$name.ms" ]; then
			echo "layers: $layer file src/navigation/$name.ms is missing"; fail=1; continue
		fi
		for path in $(imports "$name"); do
			ok=0
			for pattern in $allowed; do
				case "$path" in $pattern) ok=1 ;; esac
			done
			if [ $ok -eq 0 ]; then
				echo "layers: src/navigation/$name.ms ($layer) imports $path"; fail=1
			fi
		done
	done
}

never() {
	layer=$1; denied=$2; shift 2
	for name in "$@"; do
		if [ ! -f "src/navigation/$name.ms" ]; then
			echo "layers: $layer file src/navigation/$name.ms is missing"; fail=1; continue
		fi
		for path in $(imports "$name"); do
			for pattern in $denied; do
				case "$path" in $pattern)
					echo "layers: src/navigation/$name.ms ($layer) imports $path"; fail=1 ;;
				esac
			done
		done
	done
}

ROUTING="./routing ./routingHistory"
MODELS="./children ./childStack ./childPages"

only routing "../core/* $ROUTING" routing routingHistory
only navigation "../core/* $MODELS" children childStack childPages
never rendering "$ROUTING ./linking" navigatorMotion header layout

if [ $fail -eq 0 ]; then echo "layers: ok"; fi
exit $fail
