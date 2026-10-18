package dev.metascript.neon;

import android.content.Context;
import android.content.res.ColorStateList;
import android.view.View;
import android.widget.ProgressBar;

public final class Spinner extends ProgressBar implements Control {
	private boolean animating = true;
	private boolean hides = true;

	public Spinner(Context context) {
		super(context);
		setIndeterminate(true);
	}

	public void setNeonTag(int value) {}

	private void apply() {
		setVisibility(animating || !hides ? View.VISIBLE : View.INVISIBLE);
	}

	public void setProp(String name, String v) {
		switch (name) {
			case "animating": animating = !"false".equals(v); apply(); break;
			case "hidesWhenStopped": hides = !"false".equals(v); apply(); break;
			case "color": setIndeterminateTintList(v.isEmpty() ? null : ColorStateList.valueOf(Props.color(v, 0xff999999))); break;
			default: break;
		}
	}
}
