package dev.metascript.neon;

import android.graphics.Rect;
import android.view.MotionEvent;
import android.view.TouchDelegate;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import java.util.Map;
import java.util.WeakHashMap;

// RN hitSlop on Android: the parent's TouchDelegate hands a touch that lands in a child's slop
// (and in no child) to that child. A parent that takes touches itself (a tagged view) never
// consults its delegate, so the slop reaches only through untagged containers.
public final class Slop extends TouchDelegate {
	private static final Map<View, Rect> SLOPS = new WeakHashMap<>();
	private final ViewGroup parent;
	private View target;

	private Slop(ViewGroup parent) {
		super(new Rect(), parent);
		this.parent = parent;
	}

	static void set(View view, String value) {
		String[] parts = value.split(",");
		if (parts.length != 4) {
			SLOPS.remove(view);
			return;
		}
		boolean fresh = !SLOPS.containsKey(view);
		float density = view.getResources().getDisplayMetrics().density;
		SLOPS.put(view, new Rect(Math.round(Float.parseFloat(parts[1]) * density), Math.round(Float.parseFloat(parts[0]) * density),
			Math.round(Float.parseFloat(parts[3]) * density), Math.round(Float.parseFloat(parts[2]) * density)));
		install(view);
		if (!fresh) return;
		view.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
			@Override public void onViewAttachedToWindow(View v) { install(v); }
			@Override public void onViewDetachedFromWindow(View v) {}
		});
	}

	private static void install(View view) {
		ViewParent parent = view.getParent();
		if (!(parent instanceof ViewGroup)) return;
		ViewGroup group = (ViewGroup)parent;
		if (!(group.getTouchDelegate() instanceof Slop)) group.setTouchDelegate(new Slop(group));
	}

	@Override
	public boolean onTouchEvent(MotionEvent event) {
		int action = event.getActionMasked();
		if (action == MotionEvent.ACTION_DOWN) {
			target = null;
			Rect area = new Rect();
			for (int i = parent.getChildCount() - 1; i >= 0; i--) {
				View child = parent.getChildAt(i);
				Rect slop = SLOPS.get(child);
				if (slop == null || child.getVisibility() != View.VISIBLE) continue;
				child.getHitRect(area);
				area.set(area.left - slop.left, area.top - slop.top, area.right + slop.right, area.bottom + slop.bottom);
				if (area.contains(Math.round(event.getX()), Math.round(event.getY()))) {
					target = child;
					break;
				}
			}
		}
		View child = target;
		if (child == null) return false;
		if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) target = null;
		MotionEvent inside = MotionEvent.obtain(event);
		float x = Math.max(0, Math.min(event.getX() - child.getLeft(), child.getWidth() - 1));
		float y = Math.max(0, Math.min(event.getY() - child.getTop(), child.getHeight() - 1));
		inside.setLocation(x, y);
		boolean handled = child.dispatchTouchEvent(inside);
		inside.recycle();
		return handled;
	}
}
