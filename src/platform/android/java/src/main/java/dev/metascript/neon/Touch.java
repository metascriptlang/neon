package dev.metascript.neon;

import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;

public final class Touch implements View.OnTouchListener {
	private final int tag;
	private int target;

	public Touch(int tag) {
		this.tag = tag;
		this.target = tag;
	}

	@Override
	public boolean onTouch(View view, MotionEvent event) {
		if (event.getActionMasked() == MotionEvent.ACTION_DOWN) target = Spans.tagAt(view, event.getX(), event.getY(), tag);
		return touch(target, event.getActionMasked(), event.getRawX(), event.getRawY(), event.getEventTime());
	}

	static void claim(View view, boolean block) {
		ViewParent parent = view.getParent();
		if (parent != null) parent.requestDisallowInterceptTouchEvent(block);
	}

	static native boolean touch(int tag, int action, float x, float y, long time);
}
