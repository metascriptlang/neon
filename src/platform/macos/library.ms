when (macos) {
	@compile("./bridge.m", "-fobjc-arc");
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
}
