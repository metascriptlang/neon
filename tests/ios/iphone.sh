#!/bin/bash
# Neon physical-iPhone lane: for each class:example pair, generate the example with Ion, build it
# signed for iphoneos, install it with devicectl, and run that XCUITest class from
# tests/ios/counterUITests.swift on the phone (unlocked, Developer Mode on). Without arguments it
# runs every class. Each app is uninstalled first, so a run starts from clean app data. Usage: IOS_DEVICE=<udid> [DEVELOPMENT_TEAM=<team>] tests/ios/iphone.sh [class:example ...]
set -u
cd "$(dirname "$0")/../.."
: "${IOS_DEVICE:?set IOS_DEVICE to the UDID of the phone (xcrun xctrace list devices)}"
ionhome=${ION_HOME:-/private/tmp/ion-flatlist-prerequisite.jU95av/home}
r=$(mktemp -d /private/tmp/neon-iphone.XXXXXX); echo "results=$r"
sign=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-4R7EAZY462}" "CODE_SIGN_IDENTITY=Apple Development")
plist=("INFOPLIST_KEY_NSLocationWhenInUseUsageDescription=Neon reads your position for the device demo."
	"INFOPLIST_KEY_NSCameraUsageDescription=Neon uses the camera in the demo."
	"INFOPLIST_KEY_NSMicrophoneUsageDescription=Neon uses the microphone in the demo."
	"INFOPLIST_KEY_NSPhotoLibraryUsageDescription=Neon picks a photo in the demo.")
lanes=${*:-"CounterUITests:ios ListUITests:list FlatListUITests:flatlist ScrollMatrixUITests:scrollmatrix CatalogUITests:catalog SettingsUITests:settings ApisUITests:apis GalleryUITests:gallery MotionUITests:motion FlutterListsUITests:flutterlists ControlsUITests:controls NavigationUITests:navigation WidgetsUITests:widgets DeviceUITests:device MediaUITests:media SvgUITests:svg CaptureUITests:capture"}
status=0
for lane in $lanes; do
	cls=${lane%%:*}; ex=${lane#*:}; d=$r/$ex
	manifest=examples/$ex/ios/project.ms; [ -f "$manifest" ] || manifest=examples/$ex/project.ms
	HOME=$ionhome "$ionhome/.metascript/bin/ion" generate "$manifest" "$d" > "$r/$ex.generate.log" 2>&1 || { echo "$cls FAIL generate"; status=1; continue; }
	proj=$(ls -d "$d"/*.xcodeproj | head -1); app=$(basename "$proj" .xcodeproj)
	xcodebuild -project "$proj" -target "$app" -configuration Debug -sdk iphoneos -jobs 2 ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
		SYMROOT="$r/products" OBJROOT="$r/objects-$ex" "${sign[@]}" "${plist[@]}" build > "$r/$ex.build.log" 2>&1 || { echo "$cls FAIL build"; grep -E "error" "$r/$ex.build.log" | head -5; status=1; continue; }
	bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$r/products/Debug-iphoneos/$app.app/Info.plist")
	xcrun devicectl device uninstall app --device "$IOS_DEVICE" "$bundle" > "$r/$ex.uninstall.log" 2>&1
	xcrun devicectl device install app --device "$IOS_DEVICE" "$r/products/Debug-iphoneos/$app.app" > "$r/$ex.install.log" 2>&1 || { echo "$cls FAIL install"; tail -5 "$r/$ex.install.log"; status=1; continue; }
	xcodebuild test -project tests/ios/counter.xcodeproj -scheme CounterUITests -only-testing:CounterUITests/$cls \
		-destination "id=$IOS_DEVICE" -derivedDataPath "$r/derived" -resultBundlePath "$r/$cls.xcresult" "${sign[@]}" > "$r/$cls.test.log" 2>&1
	st=$?
	echo "$cls exit=$st $(grep -E "Executed [0-9]+ test" "$r/$cls.test.log" | tail -1)"
	if [ $st -ne 0 ]; then status=1; grep -E "error:" "$r/$cls.test.log" | head -4 | cut -c1-400; fi
done
exit $status
