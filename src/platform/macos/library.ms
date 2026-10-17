when (macos) {
	@compile("./bridge.m");
	@passL("-framework Cocoa");
	@passL("-framework QuartzCore");
}
