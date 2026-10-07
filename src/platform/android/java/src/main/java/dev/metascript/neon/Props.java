package dev.metascript.neon;

import android.graphics.Color;
import android.view.View;
import android.view.accessibility.AccessibilityNodeInfo;
import java.util.Map;
import java.util.WeakHashMap;

public final class Props {
	private Props() {}

	private static final Map<View, String> STATES = new WeakHashMap<>();

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
		if (name.startsWith("statusBar")) { SystemBars.set(view, name, value); return; }
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
			case "overflow":
				if (view instanceof android.view.ViewGroup) ((android.view.ViewGroup)view).setClipChildren("hidden".equals(value));
				return;
			case "accessibilityState": state(view, value); return;
			case "textAlign":
				if (view instanceof android.widget.TextView) align((android.widget.TextView)view, value);
				return;
			default: break;
		}
		if (view instanceof Input) ((Input)view).setProp(name, value);
		else if (view instanceof Toggle) ((Toggle)view).setProp(name, value);
		else if (view instanceof Spinner) ((Spinner)view).setProp(name, value);
		else if (view instanceof Picture) ((Picture)view).setProp(name, value);
		else if (view instanceof Overlay) ((Overlay)view).setProp(name, value);
		else if (view instanceof Control) ((Control)view).setProp(name, value);
		else if (view instanceof android.widget.TextView) text((android.widget.TextView)view, name, value);
	}

	private static void text(android.widget.TextView label, String name, String value) {
		switch (name) {
			case "numberOfLines": {
				int lines = value.isEmpty() ? 0 : Integer.parseInt(value);
				label.setMaxLines(lines > 0 ? lines : Integer.MAX_VALUE);
				if (lines > 0 && label.getEllipsize() == null) label.setEllipsize(android.text.TextUtils.TruncateAt.END);
				break;
			}
			case "ellipsizeMode":
				switch (value) {
					case "head": label.setEllipsize(android.text.TextUtils.TruncateAt.START); break;
					case "middle": label.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE); break;
					case "clip": label.setEllipsize(null); break;
					default: label.setEllipsize(android.text.TextUtils.TruncateAt.END); break;
				}
				break;
			case "selectable": label.setTextIsSelectable("true".equals(value)); break;
			default: break;
		}
	}

	// RN ReactTextView: textAlign is the horizontal gravity, justify is inter-word justification
	// (API 26+) over left gravity, and auto is the locale's start.
	static void align(android.widget.TextView label, String value) {
		int horizontal;
		switch (value) {
			case "left": case "justify": horizontal = android.view.Gravity.LEFT; break;
			case "center": horizontal = android.view.Gravity.CENTER_HORIZONTAL; break;
			case "right": horizontal = android.view.Gravity.RIGHT; break;
			default: horizontal = android.view.Gravity.START; break;
		}
		int vertical = label.getGravity() & android.view.Gravity.VERTICAL_GRAVITY_MASK;
		label.setGravity(horizontal | vertical);
		if (android.os.Build.VERSION.SDK_INT >= 26) {
			label.setJustificationMode("justify".equals(value) ? android.text.Layout.JUSTIFICATION_MODE_INTER_WORD : android.text.Layout.JUSTIFICATION_MODE_NONE);
		}
	}

	public static void setTag(View view, int tag) {
		if (view instanceof Input) ((Input)view).setNeonTag(tag);
		else if (view instanceof Toggle) ((Toggle)view).setNeonTag(tag);
		else if (view instanceof Picture) ((Picture)view).setNeonTag(tag);
		else if (view instanceof Overlay) ((Overlay)view).setNeonTag(tag);
		else if (view instanceof Control) ((Control)view).setNeonTag(tag);
	}

	private static boolean has(String state, String token) {
		for (String part : state.split(",")) if (part.equals(token)) return true;
		return false;
	}

	private static void state(View view, String value) {
		STATES.put(view, value);
		view.setSelected(has(value, "selected"));
		if (android.os.Build.VERSION.SDK_INT >= 30) {
			String text = has(value, "checked") ? "checked" : has(value, "unchecked") ? "not checked"
				: has(value, "mixed") ? "partially checked" : has(value, "expanded") ? "expanded"
				: has(value, "collapsed") ? "collapsed" : null;
			view.setStateDescription(text);
		}
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
			case "radio": return "android.widget.RadioButton";
			case "radiogroup": return "android.widget.RadioGroup";
			case "tab": return "android.app.ActionBar$Tab";
			case "tablist": return "android.widget.TabWidget";
			case "togglebutton": return "android.widget.ToggleButton";
			case "combobox": return "android.widget.Spinner";
			case "menu": return "android.widget.ListView";
			case "menuitem": return "android.widget.Button";
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
				String state = STATES.get(host);
				if (state != null && (has(state, "checked") || has(state, "unchecked") || has(state, "mixed"))) {
					info.setCheckable(true);
					info.setChecked(has(state, "checked"));
				}
				if (heading && android.os.Build.VERSION.SDK_INT >= 28) info.setHeading(true);
			}
		});
	}
}
