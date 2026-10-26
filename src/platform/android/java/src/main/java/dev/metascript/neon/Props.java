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
			case "hitSlop": Slop.set(view, value); return;
			case "androidRipple": ripple(view, value); return;
			case "textAlign":
				if (view instanceof android.widget.TextView) align((android.widget.TextView)view, value);
				return;
			// RN Android reads writingDirection and drops it: TextAttributeProps.kt:418 (react-native 693e9628e8c).
			case "writingDirection": return;
			default: break;
		}
		if (view instanceof Input) ((Input)view).setProp(name, value);
		else if (view instanceof Picture) ((Picture)view).setProp(name, value);
		else if (view instanceof Control) ((Control)view).setProp(name, value);
		else if (view instanceof android.widget.TextView) text((android.widget.TextView)view, name, value);
	}

	private static void text(android.widget.TextView label, String name, String value) {
		switch (name) {
			case "textSpans": Spans.set(label, value); break;
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

	// RN useAndroidRippleForView + ReactDrawableHelper: value is color,borderless,radius,foreground,attribute.
	// A RippleDrawable (white mask unless borderless, theme colorControlHighlight when no color) or the
	// theme drawable named by attribute goes to the foreground when foreground is true, else the background.
	// Touch drives its pressed state, since the Touch listener takes the events.
	static void ripple(View view, String value) {
		if (android.os.Build.VERSION.SDK_INT < 23) return;
		view.setForeground(null);
		if (view.getBackground() instanceof android.graphics.drawable.RippleDrawable) view.setBackground(null);
		if (value.isEmpty()) return;
		String[] f = value.split(",", -1);
		android.content.Context context = view.getContext();
		android.util.TypedValue resolved = new android.util.TypedValue();
		android.graphics.drawable.Drawable drawable;
		if (f.length > 4 && !f[4].isEmpty()) {
			int attr = themeAttribute(context, f[4]);
			if (!context.getTheme().resolveAttribute(attr, resolved, true))
				throw new IllegalArgumentException("Attribute " + f[4] + " couldn't be resolved into a drawable");
			drawable = context.getResources().getDrawable(resolved.resourceId, context.getTheme());
		} else {
			int color;
			if (f.length > 0 && !f[0].isEmpty()) {
				color = color(f[0], 0);
			} else if (context.getTheme().resolveAttribute(android.R.attr.colorControlHighlight, resolved, true)) {
				color = resolved.resourceId != 0 ? context.getResources().getColor(resolved.resourceId, context.getTheme()) : resolved.data;
			} else {
				throw new IllegalArgumentException("Attribute colorControlHighlight couldn't be resolved into a drawable");
			}
			boolean borderless = f.length > 1 && "true".equals(f[1]);
			android.graphics.drawable.Drawable mask = borderless ? null : new android.graphics.drawable.ColorDrawable(0xffffffff);
			drawable = new android.graphics.drawable.RippleDrawable(android.content.res.ColorStateList.valueOf(color), null, mask);
		}
		if (f.length > 2 && !f[2].isEmpty() && drawable instanceof android.graphics.drawable.RippleDrawable)
			((android.graphics.drawable.RippleDrawable) drawable).setRadius(Math.round(Float.parseFloat(f[2]) * view.getResources().getDisplayMetrics().density));
		if (f.length > 3 && "true".equals(f[3])) view.setForeground(drawable);
		else view.setBackground(drawable);
	}

	private static int themeAttribute(android.content.Context context, String name) {
		if ("selectableItemBackground".equals(name)) return android.R.attr.selectableItemBackground;
		if ("selectableItemBackgroundBorderless".equals(name)) return android.R.attr.selectableItemBackgroundBorderless;
		return context.getResources().getIdentifier(name, "attr", "android");
	}

	static boolean hasRipple(View view) {
		return android.os.Build.VERSION.SDK_INT >= 23
			&& (view.getForeground() instanceof android.graphics.drawable.RippleDrawable || view.getBackground() instanceof android.graphics.drawable.RippleDrawable);
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
		else if (view instanceof Picture) ((Picture)view).setNeonTag(tag);
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
