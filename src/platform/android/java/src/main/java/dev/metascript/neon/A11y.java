package dev.metascript.neon;

import android.view.View;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction;
import android.os.Bundle;
import java.util.HashMap;
import java.util.Map;
import java.util.WeakHashMap;

// The accessibility props of RN Android: BaseViewManager.java (props), ReactAccessibilityDelegate.kt
// (the node info and the actions), ReactViewManager.kt (focusable); react-native 693e9628e8c.
final class A11y {
	private A11y() {}

	private static final int ACTION_EVENT = 15;
	private static final int ACTION_EVENT_DELAY_MS = 200;

	private static final class Spec {
		String label = "", hint = "", role = "", accessibilityRole = "", state = "", value = "", actions = "";
		boolean selectedEventPending;
		View.AccessibilityDelegate delegate;

		boolean empty() {
			return label.isEmpty() && hint.isEmpty() && role.isEmpty() && accessibilityRole.isEmpty() && state.isEmpty()
				&& value.isEmpty() && actions.isEmpty();
		}
	}

	private static final Map<View, Spec> SPECS = new WeakHashMap<>();
	private static final Map<String, Integer> ACTION_IDS = new HashMap<>();
	private static final Map<Integer, String> ACTION_NAMES = new HashMap<>();
	private static int customActionCounter = 0x3f000000;

	static void set(View view, String name, String value) {
		switch (name) {
			case "importantForAccessibility": important(view, value); return;
			case "accessibilityLiveRegion": liveRegion(view, value); return;
			case "focusable":
				if ("true".equals(value)) view.setFocusable(true);
				return;
			case "accessibilityLabelledBy": case "accessibilityElementsHidden": case "accessibilityViewIsModal": return;
			default: break;
		}
		Spec spec = SPECS.get(view);
		if (spec == null) { spec = new Spec(); SPECS.put(view, spec); }
		switch (name) {
			case "accessibilityLabel": spec.label = value; describe(view, spec); break;
			case "accessibilityHint": spec.hint = value; break;
			case "accessibilityRole": className(value); spec.accessibilityRole = value; break;
			case "role": spec.role = value; break;
			case "accessibilityValue": spec.value = value; describe(view, spec); break;
			case "accessibilityActions": spec.actions = value; registerActions(value); break;
			case "accessibilityState": spec.state = value; state(view, value); break;
			default: throw new IllegalArgumentException("A11y: no handler for " + name);
		}
		if (spec.empty()) {
			SPECS.remove(view);
			if (spec.delegate != null) view.setAccessibilityDelegate(null);
		} else if (spec.delegate == null) {
			spec.delegate = delegate(spec);
			view.setAccessibilityDelegate(spec.delegate);
		}
	}

	// RN BaseViewManager.updateViewContentDescription: the label and the value's text, joined by ", ".
	private static void describe(View view, Spec spec) {
		String text = valueText(spec.value);
		String joined = spec.label.isEmpty() ? text : text.isEmpty() ? spec.label : spec.label + ", " + text;
		view.setContentDescription(joined.isEmpty() ? null : joined);
	}

	private static void important(View view, String value) {
		int mode = View.IMPORTANT_FOR_ACCESSIBILITY_AUTO;
		switch (value) {
			case "yes": mode = View.IMPORTANT_FOR_ACCESSIBILITY_YES; break;
			case "no": mode = View.IMPORTANT_FOR_ACCESSIBILITY_NO; break;
			case "no-hide-descendants": mode = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS; break;
			default: break;
		}
		view.setImportantForAccessibility(mode);
	}

	private static void liveRegion(View view, String value) {
		int mode = View.ACCESSIBILITY_LIVE_REGION_NONE;
		if ("polite".equals(value)) mode = View.ACCESSIBILITY_LIVE_REGION_POLITE;
		else if ("assertive".equals(value)) mode = View.ACCESSIBILITY_LIVE_REGION_ASSERTIVE;
		view.setAccessibilityLiveRegion(mode);
	}

	private static boolean has(String state, String token) {
		for (String part : state.split(",")) if (part.equals(token)) return true;
		return false;
	}

	private static void state(View view, String value) {
		view.setSelected(has(value, "selected"));
		if (android.os.Build.VERSION.SDK_INT >= 30) {
			String text = has(value, "checked") ? "checked" : has(value, "unchecked") ? "not checked"
				: has(value, "mixed") ? "partially checked" : has(value, "expanded") ? "expanded"
				: has(value, "collapsed") ? "collapsed" : null;
			view.setStateDescription(text);
		}
	}

	// "min,max,now,text": the text comes last and may hold commas.
	private static String valueText(String value) {
		String[] f = value.split(",", 4);
		return f.length > 3 ? f[3] : "";
	}

	private static int[] range(String value) {
		String[] f = value.split(",", 4);
		if (f.length < 3 || f[0].isEmpty() || f[1].isEmpty() || f[2].isEmpty()) return null;
		int min = (int)Double.parseDouble(f[0]);
		int max = (int)Double.parseDouble(f[1]);
		int now = (int)Double.parseDouble(f[2]);
		return max > min && now >= min && max >= now ? new int[] { min, max, now } : null;
	}

	private static void registerActions(String lines) {
		for (String line : lines.split("\n")) {
			if (line.isEmpty()) continue;
			String name = line.split("\t", 2)[0];
			if (actionId(name) == 0) {
				int id = customActionCounter++;
				ACTION_IDS.put(name, id);
				ACTION_NAMES.put(id, name);
			}
		}
	}

	private static int actionId(String name) {
		switch (name) {
			case "activate": return AccessibilityAction.ACTION_CLICK.getId();
			case "longpress": return AccessibilityAction.ACTION_LONG_CLICK.getId();
			case "increment": return AccessibilityAction.ACTION_SCROLL_FORWARD.getId();
			case "decrement": return AccessibilityAction.ACTION_SCROLL_BACKWARD.getId();
			case "expand": return AccessibilityNodeInfo.ACTION_EXPAND;
			case "collapse": return AccessibilityNodeInfo.ACTION_COLLAPSE;
			default: Integer id = ACTION_IDS.get(name); return id == null ? 0 : id;
		}
	}

	private static String actionName(int id) {
		if (id == AccessibilityAction.ACTION_CLICK.getId()) return "activate";
		if (id == AccessibilityAction.ACTION_LONG_CLICK.getId()) return "longpress";
		if (id == AccessibilityAction.ACTION_SCROLL_FORWARD.getId()) return "increment";
		if (id == AccessibilityAction.ACTION_SCROLL_BACKWARD.getId()) return "decrement";
		if (id == AccessibilityNodeInfo.ACTION_EXPAND) return "expand";
		if (id == AccessibilityNodeInfo.ACTION_COLLAPSE) return "collapse";
		return ACTION_NAMES.get(id);
	}

	// RN AccessibilityRole.fromRole: the ARIA role's accessibilityRole, null when it has none.
	private static String fromRole(String role) {
		switch (role) {
			case "alert": case "button": case "checkbox": case "combobox": case "grid": case "link": case "list": case "menu":
			case "menubar": case "menuitem": case "none": case "progressbar": case "radio": case "radiogroup":
			case "scrollbar": case "spinbutton": case "summary": case "switch": case "tab": case "tablist": case "timer":
			case "toolbar":
				return role;
			case "heading": return "header";
			case "img": return "image";
			case "searchbox": return "search";
			case "slider": return "adjustable";
			default: return null;
		}
	}

	// RN AccessibilityRole.fromViewTag: the ARIA role decides when it is set, even when it maps to nothing.
	private static String effectiveRole(Spec spec) {
		if (!spec.role.isEmpty()) return fromRole(spec.role);
		return spec.accessibilityRole.isEmpty() ? null : spec.accessibilityRole;
	}

	// RN AccessibilityRole.getValue.
	private static String className(String role) {
		switch (role) {
			case "button": return "android.widget.Button";
			case "dropdownlist": return "android.widget.Spinner";
			case "togglebutton": return "android.widget.ToggleButton";
			case "search": return "android.widget.EditText";
			case "image": return "android.widget.ImageView";
			case "imagebutton": return "android.widget.ImageButton";
			case "keyboardkey": return "android.inputmethodservice.Keyboard$Key";
			case "text": return "android.widget.TextView";
			case "adjustable": return "android.widget.SeekBar";
			case "checkbox": return "android.widget.CheckBox";
			case "radio": return "android.widget.RadioButton";
			case "spinbutton": return "android.widget.SpinButton";
			case "switch": return "android.widget.Switch";
			case "list": return "android.widget.AbsListView";
			case "grid": return "android.widget.GridView";
			case "scrollview": return "android.widget.ScrollView";
			case "horizontalscrollview": return "android.widget.HorizontalScrollView";
			case "pager": return "androidx.viewpager.widget.ViewPager";
			case "drawerlayout": return "androidx.drawerlayout.widget.DrawerLayout";
			case "slidingdrawer": return "android.widget.SlidingDrawer";
			case "iconmenu": return "com.android.internal.view.menu.IconMenuView";
			case "viewgroup": return "android.view.ViewGroup";
			case "webview": return "android.webkit.WebView";
			case "": return "android.view.View";
			case "none": case "link": case "summary": case "header": case "alert": case "combobox": case "menu":
			case "menubar": case "menuitem": case "progressbar": case "radiogroup": case "scrollbar": case "tab":
			case "tablist": case "timer": case "toolbar":
				return "android.view.View";
			default: throw new IllegalArgumentException("Invalid accessibility role value: " + role);
		}
	}

	// RN ReactAccessibilityDelegate.setRole; the role descriptions are RN's English strings.
	private static void setRole(AccessibilityNodeInfo info, String role) {
		info.setClassName(className(role));
		switch (role) {
			case "link": description(info, "Link"); break;
			case "image": description(info, "Image"); break;
			case "imagebutton": description(info, "Image Button"); info.setClickable(true); break;
			case "button": info.setClickable(true); break;
			case "togglebutton": info.setClickable(true); info.setCheckable(true); break;
			case "summary": description(info, "Summary"); break;
			case "header": if (android.os.Build.VERSION.SDK_INT >= 28) info.setHeading(true); break;
			case "alert": description(info, "Alert"); break;
			case "combobox": description(info, "Combo Box"); break;
			case "menu": description(info, "Menu"); break;
			case "menubar": description(info, "Menu Bar"); break;
			case "menuitem": description(info, "Menu Item"); break;
			case "progressbar": description(info, "Progress Bar"); break;
			case "radiogroup": description(info, "Radio Group"); break;
			case "scrollbar": description(info, "Scroll Bar"); break;
			case "spinbutton": description(info, "Spin Button"); break;
			case "tab": description(info, "Tab"); break;
			case "tablist": description(info, "Tab List"); break;
			case "timer": description(info, "Timer"); break;
			case "toolbar": description(info, "Tool Bar"); break;
			default: break;
		}
	}

	private static void description(AccessibilityNodeInfo info, String text) {
		info.getExtras().putCharSequence("AccessibilityNodeInfo.roleDescription", text);
	}

	private static View.AccessibilityDelegate delegate(final Spec spec) {
		return new View.AccessibilityDelegate() {
			@Override public void onInitializeAccessibilityNodeInfo(View host, AccessibilityNodeInfo info) {
				super.onInitializeAccessibilityNodeInfo(host, info);
				String role = effectiveRole(spec);
				if (role != null) setRole(info, role);
				if (!spec.hint.isEmpty() && android.os.Build.VERSION.SDK_INT >= 28) info.setTooltipText(spec.hint);
				if (has(spec.state, "checked") || has(spec.state, "unchecked") || has(spec.state, "mixed")) {
					info.setCheckable(true);
					info.setChecked(has(spec.state, "checked"));
				}
				for (String line : spec.actions.split("\n")) {
					if (line.isEmpty()) continue;
					String[] f = line.split("\t", 2);
					info.addAction(new AccessibilityAction(actionId(f[0]), f.length > 1 ? f[1] : ""));
				}
				int[] range = range(spec.value);
				if (range != null) {
					info.setRangeInfo(AccessibilityNodeInfo.RangeInfo.obtain(AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_INT, range[0], range[1], range[2]));
				}
			}

			@Override public void onInitializeAccessibilityEvent(View host, AccessibilityEvent event) {
				super.onInitializeAccessibilityEvent(host, event);
				int[] range = range(spec.value);
				if (range != null) {
					event.setItemCount(range[1] - range[0]);
					event.setCurrentItemIndex(range[2]);
				}
			}

			@Override public boolean performAccessibilityAction(View host, int action, Bundle args) {
				String name = actionName(action);
				if (name == null || !hasAction(spec.actions, name)) return super.performAccessibilityAction(host, action, args);
				int tag = Props.tagOf(host);
				if (tag != 0) Props.control(tag, ACTION_EVENT, name, 0, 0);
				boolean adjusts = "adjustable".equals(effectiveRole(spec))
					&& (action == AccessibilityAction.ACTION_SCROLL_FORWARD.getId() || action == AccessibilityAction.ACTION_SCROLL_BACKWARD.getId());
				if (adjusts && !spec.value.isEmpty() && valueText(spec.value).isEmpty() && !spec.selectedEventPending) {
					spec.selectedEventPending = true;
					host.postDelayed(() -> {
						spec.selectedEventPending = false;
						host.sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SELECTED);
					}, ACTION_EVENT_DELAY_MS);
				}
				return true;
			}
		};
	}

	private static boolean hasAction(String lines, String name) {
		for (String line : lines.split("\n")) if (line.split("\t", 2)[0].equals(name)) return true;
		return false;
	}
}
