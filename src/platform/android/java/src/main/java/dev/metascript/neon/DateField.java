package dev.metascript.neon;

import android.app.DatePickerDialog;
import android.app.TimePickerDialog;
import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.text.format.DateFormat;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.TextView;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

final class DateField extends TextView implements Control {
	private int tag;
	private String mode = "date";
	private String value = "";
	private long minimum = Long.MIN_VALUE;
	private long maximum = Long.MAX_VALUE;
	private int accent = 0;

	DateField(Context context) {
		super(context);
		setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
		setTextColor(0xff1c1b1f);
		setGravity(Gravity.CENTER_VERTICAL);
		float density = context.getResources().getDisplayMetrics().density;
		int pad = Math.round(12 * density);
		setPadding(pad, Math.round(8 * density), pad, Math.round(8 * density));
		GradientDrawable box = new GradientDrawable();
		box.setColor(0xffeeeeee);
		box.setCornerRadius(8 * density);
		setBackground(box);
		setClickable(true);
		setOnClickListener(view -> open());
		show();
	}

	@Override public void setNeonTag(int value) { tag = value; }

	private String pattern() {
		switch (mode) {
			case "time": return "HH:mm";
			case "datetime": return "yyyy-MM-dd'T'HH:mm";
			default: return "yyyy-MM-dd";
		}
	}

	private Calendar current() {
		Calendar c = Calendar.getInstance();
		Date d = parse(value);
		if (d != null) c.setTime(d);
		return c;
	}

	private Date parse(String text) {
		if (text == null || text.isEmpty()) return null;
		try { return new SimpleDateFormat(pattern(), Locale.US).parse(text); } catch (ParseException e) { return null; }
	}

	private void show() {
		Date d = parse(value);
		if (d == null) { setText(value); return; }
		Context c = getContext();
		String date = DateFormat.getMediumDateFormat(c).format(d);
		String time = DateFormat.getTimeFormat(c).format(d);
		setText("time".equals(mode) ? time : "datetime".equals(mode) ? date + " " + time : date);
	}

	private void emit(Calendar c) {
		String text = new SimpleDateFormat(pattern(), Locale.US).format(c.getTime());
		if (tag != 0) Props.control(tag, 4, text, 0, 0);
	}

	private void open() {
		if (!isEnabled()) return;
		final Calendar c = current();
		if ("time".equals(mode)) { openTime(c); return; }
		DatePickerDialog dialog = new DatePickerDialog(getContext(), (picker, year, month, day) -> {
			c.set(year, month, day);
			if ("datetime".equals(mode)) openTime(c);
			else emit(c);
		}, c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH));
		if (minimum != Long.MIN_VALUE) dialog.getDatePicker().setMinDate(minimum);
		if (maximum != Long.MAX_VALUE) dialog.getDatePicker().setMaxDate(maximum);
		dialog.show();
		if (accent != 0) {
			dialog.getButton(DatePickerDialog.BUTTON_POSITIVE).setTextColor(accent);
			dialog.getButton(DatePickerDialog.BUTTON_NEGATIVE).setTextColor(accent);
		}
	}

	private void openTime(final Calendar c) {
		new TimePickerDialog(getContext(), (picker, hour, minute) -> {
			c.set(Calendar.HOUR_OF_DAY, hour);
			c.set(Calendar.MINUTE, minute);
			emit(c);
		}, c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE), DateFormat.is24HourFormat(getContext())).show();
	}

	private long bound(String text, long fallback) {
		if (text.isEmpty()) return fallback;
		try { return new SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(text.length() >= 10 ? text.substring(0, 10) : text).getTime(); }
		catch (ParseException e) { return fallback; }
	}

	@Override public void setProp(String name, String v) {
		switch (name) {
			case "mode": mode = v.isEmpty() ? "date" : v; show(); break;
			case "value": value = v; show(); break;
			case "minimumDate": minimum = bound(v, Long.MIN_VALUE); break;
			case "maximumDate": maximum = bound(v, Long.MAX_VALUE); break;
			case "disabled": setEnabled(!"true".equals(v)); setAlpha("true".equals(v) ? 0.5f : 1f); break;
			case "accentColor": accent = v.isEmpty() ? 0 : Props.color(v, 0); break;
			case "textColor": setTextColor(v.isEmpty() ? 0xff1c1b1f : Props.color(v, 0xff1c1b1f)); break;
			default: break;
		}
	}
}
