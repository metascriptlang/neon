#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/../.."
case "$(g++ -dumpmachine)" in *mingw*) ;; *) echo 'windowsImageConsumer needs MinGW on Windows' >&2; exit 2;; esac
mkdir -p out/image-consumer out/image-decode
build() {
	fixture=$1; source=$2; output=$3
	g++ -std=c++17 -O2 -DNOMINMAX -DNEON_IMAGE_WORKER_TEST -I src/platform/windows \
		"$fixture" "$source" -o "$output" -lurlmon -lole32 -lwindowscodecs -ld2d1 -ld3d11 -ldxguid -luuid
}
expectRed() {
	name=$1; message=$2; shift 2
	if timeout 20 "$@" >"out/image-consumer/$name.log" 2>&1; then status=0; else status=$?; fi
	cat "out/image-consumer/$name.log"
	if [ "$status" != 1 ] || ! grep -Fxq "image-consumer assertion: $message" "out/image-consumer/$name.log"; then
		echo "image-consumer-control $name unexpected rc=$status" >&2
		exit 1
	fi
	echo "image-consumer-control $name expected-RED rc=1"
}
g++ --version | head -1
sha256sum src/platform/windows/{image.cpp,image.h,imageDecode.h} \
	tests/platform/windowsImage{Consumer.cpp,Consumer.sh,Worker.cpp} bench/imageInputs.py
python3 bench/imageInputs.py out/image-decode
small=$(cygpath -ma out/image-decode/64.png)
build tests/platform/windowsImageConsumer.cpp src/platform/windows/image.cpp out/windows-image-consumer.exe
timeout 20 out/windows-image-consumer.exe "$small"
build tests/platform/windowsImageWorker.cpp src/platform/windows/image.cpp out/windows-image-worker.exe
uri=$(python3 -c 'from pathlib import Path; print(Path("out/image-decode/4096.png").resolve().as_uri())' | tr -d '\r')
timeout 20 out/windows-image-worker.exe "$uri"
python3 - <<'PY'
from pathlib import Path
source = Path('src/platform/windows/image.cpp').read_text()
for name, old, new in [
    ('owner', 'g_waiting.erase(fetching);\n\t\tif (g_pictureDecodes)', 'if (g_pictureDecodes)'),
    ('cancel', 'g_pictureDecodes->Cancel(fetching);', '(void)fetching;'),
    ('pixels', 'pixels = std::move(decoded.pixels);', 'pixels = std::move(decoded.pixels);\n\tpixels[0] ^= 255;'),
]:
    assert source.count(old) == 1, name
    Path('out/image-consumer/' + name + '.cpp').write_text(source.replace(old, new, 1))
PY
for mode in owner cancel pixels; do
	build tests/platform/windowsImageConsumer.cpp "out/image-consumer/$mode.cpp" "out/windows-image-consumer-$mode.exe"
	case "$mode" in
		owner) message='destroyed request retained an owner';;
		cancel) message='destroy/reuse delivered to wrong picture';;
		pixels) message='production Draw pixels differ from worker buffer';;
	esac
	expectRed "$mode" "$message" "out/windows-image-consumer-$mode.exe" "$small"
done
sha256sum out/windows-image-consumer{,-owner,-cancel,-pixels}.exe out/windows-image-worker.exe \
	out/image-consumer/{owner,cancel,pixels}.cpp out/image-decode/{64,4096}.png
