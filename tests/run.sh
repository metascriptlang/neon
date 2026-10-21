#!/bin/sh
# Neon test gate — every test file of tests/ and neon-ui/tests/ but the browser ones and the *Server.test.ms files runs
# native, then --target=js. The *Server.test.ms files run in the SSR lane under -d:server, the
# one build with a server renderer. Then the browser lane in real Chrome, then the edge lane in workerd.
# js-lane skips: tests/style/style.test.ms, tests/platform/void.test.ms, tests/platform/voidPark.test.ms,
# tests/platform/voidInput.test.ms, voidFont.test.ms, windowHost.test.ms and sokolInput.test.ms import the Void platform
# host, a C-only sibling repo; tests/platform/ionAudio.test.ms and ionAppServices.test.ms import Ion's runtime, C-only;
# tests/platform/native<Name>.test.ms files link the native host against a C mock bridge.
# tests/browser is bound to a real DOM: it has no C lowering and no `document`
# under node, so it runs only through tests/browser/run.sh.
MSC=${MSC:-msc}
cd "$(dirname "$0")/.."
files=$(find tests neon-ui/tests -name "*.test.ms" -not -name "*Server.test.ms" -not -path "tests/browser/*" | sort)
fail=0
tests/macros/run.sh || fail=1
tests/navigation/layers.sh || fail=1
tests/apps/run.sh || fail=1
tests/refresh/run.sh || fail=1
for f in $files; do
	echo "== native $f"
	"$MSC" test "$f" || fail=1
done
for f in $files; do
	case "$f" in
	*style/style.test.ms | *platform/void.test.ms | *platform/voidInput.test.ms | *platform/voidPark.test.ms | *platform/voidFont.test.ms | *platform/voidPaint.test.ms | *platform/windowHost.test.ms | *platform/sokolInput.test.ms | *platform/ionAudio.test.ms | *platform/ionAppServices.test.ms | *platform/native[A-Z]*.test.ms | *platform/voidRaw.test.ms | *render/scene3d.test.ms | *render/scene3dCamera.test.ms | *render/scene3dNodes.test.ms | *render/scene3dGltf.test.ms | *render/scene2d.test.ms | *render/scene2dPaint.test.ms | *render/scene2dText.test.ms | *render/scene2dBackground.test.ms | *render/scene2dFont.test.ms | *render/scene2dOrder.test.ms | *render/scene2dEffects.test.ms | *render/scene2dGraphics.test.ms | *render/scene2dGraphicsPaint.test.ms | *render/scene2dQuery.test.ms | *render/scene2dTile.test.ms | *platform/voidRawPlacement.test.ms | *platform/voidLayerShown.test.ms | *render/scene2dAnimation.test.ms | *render/scene3dArea.test.ms | *render/scene2dIcon.test.ms | *render/scene3dLayers.test.ms | *render/scene3dOutline.test.ms | *render/scene2dCursorClock.test.ms | *render/scene2dLabelStyle.test.ms | *render/scene3dLightBindings.test.ms)
		echo "== js skip $f"
		continue
		;;
	esac
	echo "== js $f"
	"$MSC" test --target=js "$f" || fail=1
done
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*)
	echo "== desktop examples/voidWindow.ms"
	"$MSC" build examples/voidWindow.ms --output=out/voidWindow.exe || fail=1
	echo "== desktop examples/voidDraw.ms"
	"$MSC" build examples/voidDraw.ms --output=out/voidDraw.exe || fail=1
	echo "== desktop examples/voidInputs.ms"
	"$MSC" build examples/voidInputs.ms --output=out/voidInputs.exe || fail=1
	echo "== desktop examples/voidCanvas.ms"
	"$MSC" build examples/voidCanvas.ms --output=out/voidCanvas.exe || fail=1
	echo "== desktop examples/desktopAudio.ms"
	"$MSC" build examples/desktopAudio.ms --output=out/desktopAudio.exe || fail=1
	echo "== desktop examples/windowsNative/app.ms"
	"$MSC" build examples/windowsNative/app.ms --output=out/windowsNative.exe || fail=1
	echo "== desktop examples/windowsNative/text.ms"
	"$MSC" build examples/windowsNative/text.ms --output=out/windowsText.exe || fail=1
	echo "== desktop examples/windowsNative/ion.ms"
	"$MSC" build examples/windowsNative/ion.ms --output=out/windowsIon.exe || fail=1
	echo "== desktop examples/windowsNative/ionText.ms"
	"$MSC" build examples/windowsNative/ionText.ms --output=out/windowsIonText.exe || fail=1
	echo "== desktop examples/windowsNative/ionPress.ms"
	"$MSC" build examples/windowsNative/ionPress.ms --output=out/windowsIonPress.exe || fail=1
	;;
Darwin)
	echo "== desktop examples/macosNative/ionVoid.ms --check"
	{ "$MSC" build examples/macosNative/ionVoid.ms --output=out/macosIonVoid && out/macosIonVoid --check; } || fail=1
	;;
*) echo "== desktop skip examples/voidWindow.ms, examples/voidDraw.ms, examples/voidInputs.ms, examples/voidCanvas.ms, examples/desktopAudio.ms and examples/windowsNative: Windows-only" ;;
esac
sh tests/ssrParity/run.sh || fail=1
tests/browser/run.sh || fail=1
sh tests/edge/run.sh || fail=1
exit $fail
