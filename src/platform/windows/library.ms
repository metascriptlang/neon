when (windows) {
	@compile("./bridge.cpp");
	@compile("./dcompComposition.cpp");
	@compile("./dwriteText.cpp");
	@compile("./scrollView.cpp");
	@compile("./textInput.cpp");
	@passL("-luser32");
	@passL("-luuid");
	@passL("-ldwrite");
	@passL("-loleaut32");
}
