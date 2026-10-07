package dev.metascript.neon;

import android.graphics.Color;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;

public final class Props {
	private Props() {}

	static native void control(int tag, int phase, String value, int width, int height);

	public static int color(String css, int fallback) {
		if (css == null || css.isEmpty()) return fallback;
		try {
			return Color.parseColor(css);
		} catch (IllegalArgumentException e) {
			return fallback;
		}
	}

	public static void set(View view, String name, String value) {
		switch (name) {
			case "accessibilityLabel": view.setContentDescription(value.isEmpty() ? null : value); return;
			case "accessibilityHint":
				if (android.os.Build.VERSION.SDK_INT >= 30) view.setStateDescription(null);
				view.setTooltipText(value.isEmpty() ? null : value);
				return;
			case "accessible": {
				boolean yes = "true".equals(value);
				view.setFocusable(yes || view.isClickable());
				if (android.os.Build.VERSION.SDK_INT >= 28) view.setScreenReaderFocusable(yes);
				view.setImportantForAccessibility(value.isEmpty() ? View.IMPORTANT_FOR_ACCESSIBILITY_AUTO : yes ? View.IMPORTANT_FOR_ACCESSIBILITY_YES : View.IMPORTANT_FOR_ACCESSIBILITY_AUTO);
				return;
			}
			case "accessibilityRole": role(view, value); return;
			default: break;
		}
		if (view instanceof Input) ((Input)view).setProp(name, value);
	}

	private static String roleClass(String role) {
		switch (role) {
			case "button": case "link": return "android.widget.Button";
			case "image": return "android.widget.ImageView";
			case "switch": return "android.widget.Switch";
			case "checkbox": return "android.widget.CheckBox";
			case "search": return "android.widget.EditText";
			case "text": case "header": case "summary": case "alert": return "android.widget.TextView";
			case "adjustable": return "android.widget.SeekBar";
			case "progressbar": return "android.widget.ProgressBar";
			default: return null;
		}
	}

	private static void role(View view, String role) {
		final String className = roleClass(role);
		final boolean heading = "header".equals(role);
		if (className == null && !heading) {
			view.setAccessibilityDelegate(null);
			return;
		}
		view.setAccessibilityDelegate(new View.AccessibilityDelegate() {
			@Override public void onInitializeAccessibilityNodeInfo(View host, AccessibilityNodeInfo info) {
				super.onInitializeAccessibilityNodeInfo(host, info);
				if (className != null) info.setClassName(className);
				if (heading && android.os.Build.VERSION.SDK_INT >= 28) info.setHeading(true);
			}
		});
	}
}
