-keep class dev.metascript.neon.Web {
	<init>(android.content.Context);
}

-keepclassmembers class dev.metascript.neon.Web$Bridge {
	@android.webkit.JavascriptInterface <methods>;
}
