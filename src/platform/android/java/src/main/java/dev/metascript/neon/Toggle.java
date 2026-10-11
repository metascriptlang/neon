package dev.metascript.neon;

import android.content.Context;
import android.content.res.ColorStateList;
import android.widget.Switch;

public final class Toggle extends Switch {
	private int tag;
	private boolean value;
	private boolean writing;
	private int trackOn = 0xff81b0ff;
	private int trackOff = 0xff767577;

	public Toggle(Context context) {
		super(context);
		setText("");
		setShowText(false);
		applyTrack();
		setOnCheckedChangeListener((button, checked) -> {
			if (writing || tag == 0) return;
			Props.control(tag, 4, checked ? "true" : "false", 0, 0);
			if (isChecked() != value) write(value);
		});
	}

	public void setNeonTag(int value) { tag = value; }

	private void write(boolean checked) {
		writing = true;
		setChecked(checked);
		writing = false;
	}

	private void applyTrack() {
		int[][] states = { { android.R.attr.state_checked }, {} };
		setTrackTintList(new ColorStateList(states, new int[] { trackOn, trackOff }));
	}

	public void setProp(String name, String v) {
		switch (name) {
			case "value": value = "true".equals(v); if (isChecked() != value) write(value); break;
			case "disabled": setEnabled(!"true".equals(v)); break;
			case "thumbColor": setThumbTintList(v.isEmpty() ? null : ColorStateList.valueOf(Props.color(v, 0xffffffff))); break;
			case "trackColorOn": trackOn = Props.color(v, 0xff81b0ff); applyTrack(); break;
			case "trackColorOff": trackOff = Props.color(v, 0xff767577); applyTrack(); break;
			default: break;
		}
	}
}
