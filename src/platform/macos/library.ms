when (macos) {
	@compile("./bridge.m", "-fobjc-arc");
	@compile("./media.m", "-fobjc-arc");
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
	@passL("-framework WebKit");
	@passL("-framework AVFoundation");
	@passL("-framework AVKit");
	@passL("-framework CoreMedia");
}
