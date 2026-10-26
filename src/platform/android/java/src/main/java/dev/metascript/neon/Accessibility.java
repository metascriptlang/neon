package dev.metascript.neon;

import android.app.Activity;
import android.content.ContentResolver;
import android.database.ContentObserver;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.accessibility.AccessibilityManager;
import java.util.HashMap;

// Mirrors AccessibilityInfoModule.kt (animationScaleObserver for reduce motion): the same settings keys, read when asked and watched for changes.
final class Accessibility {
	private static final String HIGH_TEXT_CONTRAST = "high_text_contrast_enabled";
	private static final String DALTONIZER_ENABLED = "accessibility_display_daltonizer_enabled";
	private static final String DALTONIZER_MODE = "accessibility_display_daltonizer";

	private static final HashMap<String, String> published = new HashMap<>();

	private Accessibility() {}

	static String call(Activity a, String name, String arg) {
		switch (name) {
			case "a11y.invertColors": return flag(invertColors(a));
			case "a11y.grayscale": return flag(grayscale(a));
			case "a11y.highTextContrast": return flag(highTextContrast(a));
			case "a11y.accessibilityService": return flag(manager(a).isEnabled());
			case "a11y.timeout": return Integer.toString(recommendedTimeout(a, Integer.parseInt(arg)));
			case "a11y.announceQueue":
				a.getWindow().getDecorView().announceForAccessibility(arg.substring(arg.indexOf('\u001f') + 1));
				return "";
			default: throw new IllegalArgumentException("unknown accessibility command " + name);
		}
	}

	static void observe(Activity a) {
		ContentResolver resolver = a.getContentResolver();
		publish("invertColorsChanged", invertColors(a));
		publish("grayscaleChanged", grayscale(a));
		publish("highTextContrastChanged", highTextContrast(a));
		publish("accessibilityServiceChanged", manager(a).isEnabled());
		watch(resolver, Settings.Global.getUriFor(Settings.Global.TRANSITION_ANIMATION_SCALE), () -> {
			String value = flag(App.reduceMotion(a));
			if (!value.equals(published.put("reduceMotion", value))) App.event(App.REDUCE_MOTION, value);
		});
		published.put("reduceMotion", flag(App.reduceMotion(a)));
		manager(a).addAccessibilityStateChangeListener(enabled -> publish("accessibilityServiceChanged", enabled));
		watch(resolver, Settings.Secure.getUriFor(Settings.Secure.ACCESSIBILITY_DISPLAY_INVERSION_ENABLED),
			() -> publish("invertColorsChanged", invertColors(a)));
		watch(resolver, Settings.Secure.getUriFor(DALTONIZER_ENABLED), () -> publish("grayscaleChanged", grayscale(a)));
		watch(resolver, Settings.Secure.getUriFor(DALTONIZER_MODE), () -> publish("grayscaleChanged", grayscale(a)));
		watch(resolver, Settings.Secure.getUriFor(HIGH_TEXT_CONTRAST), () -> publish("highTextContrastChanged", highTextContrast(a)));
	}

	private static void watch(ContentResolver resolver, Uri uri, Runnable changed) {
		resolver.registerContentObserver(uri, false, new ContentObserver(new Handler(Looper.getMainLooper())) {
			@Override public void onChange(boolean selfChange) { changed.run(); }
		});
	}

	private static void publish(String name, boolean on) {
		String value = flag(on);
		if (value.equals(published.put(name, value))) return;
		App.event(App.ACCESSIBILITY, name + "\u001f" + value);
	}

	private static String flag(boolean on) {
		return on ? "1" : "0";
	}

	private static AccessibilityManager manager(Activity a) {
		return (AccessibilityManager) a.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE);
	}

	private static boolean invertColors(Activity a) {
		return Settings.Secure.getInt(a.getContentResolver(), Settings.Secure.ACCESSIBILITY_DISPLAY_INVERSION_ENABLED, 0) == 1;
	}

	// Grayscale is the colour-correction setting switched on with mode 0 (AccessibilityInfoModule.kt isGrayscaleEnabledValue).
	private static boolean grayscale(Activity a) {
		ContentResolver resolver = a.getContentResolver();
		return Settings.Secure.getInt(resolver, DALTONIZER_ENABLED, 0) == 1 && Settings.Secure.getInt(resolver, DALTONIZER_MODE, -1) == 0;
	}

	private static boolean highTextContrast(Activity a) {
		return Settings.Secure.getInt(a.getContentResolver(), HIGH_TEXT_CONTRAST, 0) != 0;
	}

	private static int recommendedTimeout(Activity a, int original) {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return original;
		return manager(a).getRecommendedTimeoutMillis(original, AccessibilityManager.FLAG_CONTENT_CONTROLS);
	}
}
