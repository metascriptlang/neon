package dev.metascript.neon;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Build;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.FrameLayout;

// RN StatusBar on Android: bar style, visibility and background colour of the
// activity's status bar. From targetSdk 35 the window is edge-to-edge and
// ignores setStatusBarColor, so a scrim view under the bar paints the colour.
public final class SystemBars {
	private static View scrim;
	private static int scrimColor;
	private static boolean translucent;

	private SystemBars() {}

	static Activity activity(View view) {
		Context context = view.getContext();
		while (context instanceof ContextWrapper) {
			if (context instanceof Activity) return (Activity)context;
			context = ((ContextWrapper)context).getBaseContext();
		}
		return null;
	}

	public static void set(View view, String name, String value) {
		Activity activity = activity(view);
		if (activity == null) return;
		Window window = activity.getWindow();
		switch (name) {
			case "statusBarStyle": style(window, "dark-content".equals(value)); break;
			case "statusBarHidden": hidden(window, "true".equals(value)); break;
			case "statusBarBackgroundColor": background(activity, window, Props.color(value, 0xff000000)); break;
			case "statusBarTranslucent":
				translucent = "true".equals(value);
				if (scrim != null) scrim.setVisibility(translucent ? View.GONE : View.VISIBLE);
				break;
			default: break;
		}
	}

	private static void style(Window window, boolean darkIcons) {
		if (Build.VERSION.SDK_INT >= 30) {
			WindowInsetsController controller = window.getInsetsController();
			if (controller == null) return;
			int flag = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS;
			controller.setSystemBarsAppearance(darkIcons ? flag : 0, flag);
			return;
		}
		View decor = window.getDecorView();
		int flags = decor.getSystemUiVisibility();
		int light = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
		decor.setSystemUiVisibility(darkIcons ? flags | light : flags & ~light);
	}

	private static void hidden(Window window, boolean hide) {
		if (Build.VERSION.SDK_INT >= 30) {
			WindowInsetsController controller = window.getInsetsController();
			if (controller == null) return;
			if (hide) controller.hide(WindowInsets.Type.statusBars());
			else controller.show(WindowInsets.Type.statusBars());
			return;
		}
		if (hide) window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
		else window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
	}

	private static int statusBarHeight(View view) {
		WindowInsets insets = view.getRootWindowInsets();
		if (insets == null) return 0;
		if (Build.VERSION.SDK_INT >= 30) return insets.getInsets(WindowInsets.Type.statusBars()).top;
		return insets.getSystemWindowInsetTop();
	}

	private static void background(Activity activity, Window window, int color) {
		if (Build.VERSION.SDK_INT < 35) {
			window.setStatusBarColor(color);
			return;
		}
		scrimColor = color;
		ViewGroup content = activity.findViewById(android.R.id.content);
		if (content == null) return;
		if (scrim == null || scrim.getParent() != content) {
			scrim = new View(activity);
			scrim.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
			content.addView(scrim, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, Gravity.TOP));
			final View bar = scrim;
			content.getViewTreeObserver().addOnGlobalLayoutListener(() -> fit(bar));
		}
		scrim.setBackgroundColor(scrimColor);
		scrim.setVisibility(translucent ? View.GONE : View.VISIBLE);
		fit(scrim);
	}

	private static void fit(View bar) {
		ViewGroup.LayoutParams params = bar.getLayoutParams();
		int height = statusBarHeight(bar);
		if (params.height == height) return;
		params.height = height;
		bar.setLayoutParams(params);
	}
}
