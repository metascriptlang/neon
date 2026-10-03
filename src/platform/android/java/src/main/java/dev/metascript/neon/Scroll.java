package dev.metascript.neon;

import android.view.View;
import android.view.ViewGroup;

public final class Scroll implements View.OnScrollChangeListener {
	private final int tag;

	public Scroll(int tag) {
		this.tag = tag;
	}

	@Override
	public void onScrollChange(View view, int scrollX, int scrollY, int oldScrollX, int oldScrollY) {
		int contentWidth = 0;
		int contentHeight = 0;
		if (view instanceof ViewGroup && ((ViewGroup) view).getChildCount() > 0) {
			View content = ((ViewGroup) view).getChildAt(0);
			contentWidth = content.getWidth();
			contentHeight = content.getHeight();
		}
		scroll(tag, scrollX, scrollY, view.getWidth(), view.getHeight(), contentWidth, contentHeight);
	}

	static native void scroll(int tag, int x, int y, int width, int height, int contentWidth, int contentHeight);
}
