package dev.metascript.neon;

import android.view.MotionEvent;
import android.view.View;

public final class Touch implements View.OnTouchListener {
	private final int tag;

	public Touch(int tag) {
		this.tag = tag;
	}

	@Override
	public boolean onTouch(View view, MotionEvent event) {
		return touch(tag, event.getActionMasked());
	}

	static native boolean touch(int tag, int action);
}
