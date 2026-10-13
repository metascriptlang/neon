when (windows) {
	@compile("./bridge.cpp");
	@compile("./dcompComposition.cpp");
	@passL("-luser32");
	@passL("-luuid");
}
