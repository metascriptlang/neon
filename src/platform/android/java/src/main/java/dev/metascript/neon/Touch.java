package dev.metascript.neon;

import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;

public final class Touch implements View.OnTouchListener {
	static final int REPORTED_UP = -1;
	private final int tag;
	private int target;

	public Touch(int tag) {
		this.tag = tag;
		this.target = tag;
	}

	@Override
	public boolean onTouch(View view, MotionEvent event) {
		int action = event.getActionMasked();
		if (action == MotionEvent.ACTION_DOWN) target = Spans.tagAt(view, event.getX(), event.getY(), tag);
		if (android.os.Build.VERSION.SDK_INT >= 23 && view.getForeground() instanceof android.graphics.drawable.RippleDrawable) {
			view.drawableHotspotChanged(event.getX(), event.getY());
			if (action == MotionEvent.ACTION_DOWN) view.setPressed(true);
			else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) view.setPressed(false);
		}
		return touch(target, event.getActionMasked(), event.getRawX(), event.getRawY(), event.getEventTime());
	}

	static void claim(View view, boolean block) {
		ViewParent parent = view.getParent();
		if (parent != null) parent.requestDisallowInterceptTouchEvent(block);
	}

	static native boolean touch(int tag, int action, float x, float y, long time);
}
