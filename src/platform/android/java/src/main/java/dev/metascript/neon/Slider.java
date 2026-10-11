package dev.metascript.neon;

import android.content.Context;
import android.content.res.ColorStateList;
import android.widget.SeekBar;

final class Slider extends SeekBar implements Control {
	private static final int CONTINUOUS = 1000;
	private int tag;
	private double minimum = 0;
	private double maximum = 1;
	private double step = 0;
	private double value = 0;
	private boolean writing;
	private boolean tracking;

	Slider(Context context) {
		super(context);
		applyRange();
		setOnSeekBarChangeListener(new OnSeekBarChangeListener() {
			@Override public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
				if (writing || !fromUser || tag == 0) return;
				Props.control(tag, 4, Controls.number(valueAt(progress)), 0, 0);
			}
			@Override public void onStartTrackingTouch(SeekBar bar) { tracking = true; }
			@Override public void onStopTrackingTouch(SeekBar bar) {
				tracking = false;
				if (tag != 0) Props.control(tag, 8, Controls.number(valueAt(getProgress())), 0, 0);
			}
		});
	}

	@Override public void setNeonTag(int value) { tag = value; }

	@Override protected synchronized void onMeasure(int widthSpec, int heightSpec) {
		super.onMeasure(widthSpec, heightSpec);
		if (Controls.intrinsicQuery(widthSpec, heightSpec)) setMeasuredDimension(0, getMeasuredHeight());
	}

	private int steps() {
		if (step > 0 && maximum > minimum) return (int)Math.max(1, Math.round((maximum - minimum) / step));
		return CONTINUOUS;
	}

	private double valueAt(int progress) {
		if (step > 0) return Math.min(maximum, minimum + progress * step);
		return minimum + (maximum - minimum) * progress / (double)CONTINUOUS;
	}

	private void applyRange() {
		writing = true;
		setMax(steps());
		double span = maximum - minimum;
		int progress = span <= 0 ? 0 : step > 0 ? (int)Math.round((value - minimum) / step) : (int)Math.round((value - minimum) / span * CONTINUOUS);
		if (!tracking) setProgress(Math.max(0, Math.min(getMax(), progress)));
		writing = false;
	}

	private static double parse(String v, double fallback) {
		try { return Double.parseDouble(v); } catch (NumberFormatException e) { return fallback; }
	}

	@Override public void setProp(String name, String v) {
		switch (name) {
			case "minimumValue": minimum = parse(v, 0); applyRange(); break;
			case "maximumValue": maximum = parse(v, 1); applyRange(); break;
			case "step": step = parse(v, 0); applyRange(); break;
			case "value": value = parse(v, 0); applyRange(); break;
			case "disabled": setEnabled(!"true".equals(v)); break;
			case "inverted": setScaleX("true".equals(v) ? -1f : 1f); break;
			case "minimumTrackTintColor": setProgressTintList(v.isEmpty() ? null : ColorStateList.valueOf(Props.color(v, 0xff2196f3))); break;
			case "maximumTrackTintColor": setProgressBackgroundTintList(v.isEmpty() ? null : ColorStateList.valueOf(Props.color(v, 0xffbdbdbd))); break;
			case "thumbTintColor": setThumbTintList(v.isEmpty() ? null : ColorStateList.valueOf(Props.color(v, 0xff2196f3))); break;
			default: break;
		}
	}
}
