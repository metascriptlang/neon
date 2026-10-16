when (windows) {
	@compile("./bridge.cpp");
	@compile("./dcompComposition.cpp");
	@compile("./dwriteText.cpp");
	@compile("./scrollView.cpp");
	@passL("-luser32");
	@passL("-luuid");
	@passL("-ldwrite");
}
