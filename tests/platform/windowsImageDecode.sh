#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/../.."
case "$(g++ -dumpmachine)" in *mingw*) ;; *) echo 'windowsImageDecode needs MinGW on Windows' >&2; exit 2;; esac
mkdir -p out/image-decode
build() {
	g++ -std=c++17 -O2 -DNOMINMAX -DNEON_IMAGE_WORKER_TEST -I src/platform/windows \
		"$1" "$2" -o "$3" -lurlmon -lole32 -lwindowscodecs -ld2d1 -ldxguid -luuid
}
expectRed() {
	name=$1; message=$2; shift 2
	if timeout 20 "$@" >"out/image-decode/$name.log" 2>&1; then status=0; else status=$?; fi
	cat "out/image-decode/$name.log"
	if [ "$status" != 1 ] || ! grep -Fxq "$message" "out/image-decode/$name.log"; then
		echo "image-decode-control $name unexpected rc=$status" >&2
		exit 1
	fi
	echo "image-decode-control $name expected-RED rc=1"
}
g++ --version | head -1
sha256sum src/platform/windows/image.cpp src/platform/windows/imageDecode.h src/platform/windows/image.h \
	tests/platform/windowsImageDecode.cpp tests/platform/windowsImageWorker.cpp \
	tests/platform/windowsImageDecode.sh bench/imageInputs.py
python3 bench/imageInputs.py out/image-decode
small=$(cygpath -ma out/image-decode/64.png)
large=$(cygpath -ma out/image-decode/4096.png)
build tests/platform/windowsImageDecode.cpp src/platform/windows/image.cpp out/windows-image-decode.exe
timeout 20 out/windows-image-decode.exe "$small" "$large"
build tests/platform/windowsImageWorker.cpp src/platform/windows/image.cpp out/windows-image-worker.exe
uri=$(python3 -c 'from pathlib import Path; print(Path("out/image-decode/4096.png").resolve().as_uri())' | tr -d '\r')
expectRed legacy 'image-worker assertion: decode ran on host thread' out/windows-image-worker.exe "$uri"
python3 - <<'PY'
from pathlib import Path
source = Path('src/platform/windows/image.cpp').read_text()
variants = {}
for name, old, new in [
    ('workers', 'static constexpr uint32_t workerLimit = 2;', 'static constexpr uint32_t workerLimit = 3;'),
    ('bytes', '(activeBytes <= byteBudget && bytes <= byteBudget - activeBytes)', 'true'),
    ('early', 'if (!result.byteCount) release(bytes);', 'release(bytes);'),
]:
    assert source.count(old) == 1, name
    variants[name] = source.replace(old, new, 1)
assert source.count('\t\tif (path.find(') == 1
start = source.index('\t\tif (path.find(')
end = source.index('\t\tint length', start)
assert 'malformed URI' in source[start:end] and 'return E_INVALIDARG;' in source[start:end]
variants['nul'] = source[:start] + source[end:]
for name, content in variants.items():
    Path('out/image-decode/' + name + '.cpp').write_text(content)
PY
for mode in workers bytes early nul; do
	build tests/platform/windowsImageDecode.cpp "out/image-decode/$mode.cpp" "out/windows-image-decode-$mode.exe"
	case "$mode" in
		workers) message='two-worker cap while blocked';;
		bytes) message='one oversized decode admitted alone';;
		early) message='ready pixels escaped byte reservation';;
		nul) message='encoded NUL URI silently loaded prefix file';;
	esac
	expectRed "$mode" "image-decode assertion: $message" "out/windows-image-decode-$mode.exe" "$small" "$large"
done
sha256sum out/windows-image-decode.exe out/windows-image-worker.exe \
	out/windows-image-decode-{workers,bytes,early,nul}.exe out/image-decode/{workers,bytes,early,nul}.cpp
