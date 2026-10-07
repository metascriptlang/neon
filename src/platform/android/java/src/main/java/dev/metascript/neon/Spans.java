package dev.metascript.neon;

import android.graphics.Typeface;
import android.text.Layout;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.AbsoluteSizeSpan;
import android.text.style.ForegroundColorSpan;
import android.text.style.StrikethroughSpan;
import android.text.style.StyleSpan;
import android.text.style.UnderlineSpan;
import android.view.View;
import android.widget.TextView;

// RN nested Text on Android: one TextView holds every run as spans. textSpans carries records
// split by 0x1e, fields by 0x1f: text, colour, size, bold, italic, underline, line-through, press tag.
public final class Spans {
	private Spans() {}

	static final class Press {
		final int tag;
		Press(int tag) { this.tag = tag; }
	}

	static void set(TextView label, String encoded) {
		SpannableStringBuilder out = new SpannableStringBuilder();
		int fallback = label.getCurrentTextColor();
		for (String record : encoded.split("\u001e", -1)) {
			String[] f = record.split("\u001f", -1);
			if (f.length < 8) continue;
			int start = out.length();
			out.append(f[0]);
			int end = out.length();
			if (end == start) continue;
			int flags = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE;
			out.setSpan(new ForegroundColorSpan(Props.color(f[1], fallback)), start, end, flags);
			float size = f[2].isEmpty() ? 17 : Float.parseFloat(f[2]);
			out.setSpan(new AbsoluteSizeSpan(Math.round(size), true), start, end, flags);
			boolean bold = "1".equals(f[3]);
			boolean italic = "1".equals(f[4]);
			int style = bold && italic ? Typeface.BOLD_ITALIC : bold ? Typeface.BOLD : italic ? Typeface.ITALIC : Typeface.NORMAL;
			out.setSpan(new StyleSpan(style), start, end, flags);
			if ("1".equals(f[5])) out.setSpan(new UnderlineSpan(), start, end, flags);
			if ("1".equals(f[6])) out.setSpan(new StrikethroughSpan(), start, end, flags);
			int tag = f[7].isEmpty() ? 0 : Integer.parseInt(f[7]);
			if (tag != 0) out.setSpan(new Press(tag), start, end, flags);
		}
		label.setText(out);
	}

	// The press tag of the span under a touch in the view's coordinates, else the view's own.
	static int tagAt(View view, float x, float y, int fallback) {
		if (!(view instanceof TextView)) return fallback;
		TextView label = (TextView)view;
		CharSequence text = label.getText();
		Layout layout = label.getLayout();
		if (!(text instanceof Spanned) || layout == null) return fallback;
		int line = layout.getLineForVertical(Math.round(y) - label.getTotalPaddingTop() + label.getScrollY());
		float along = x - label.getTotalPaddingLeft() + label.getScrollX();
		if (along < layout.getLineLeft(line) || along > layout.getLineRight(line)) return fallback;
		int offset = layout.getOffsetForHorizontal(line, along);
		Spanned spanned = (Spanned)text;
		for (Press press : spanned.getSpans(offset, Math.min(offset + 1, spanned.length()), Press.class)) {
			if (spanned.getSpanStart(press) <= offset && offset < spanned.getSpanEnd(press)) return press.tag;
		}
		return fallback;
	}
}
