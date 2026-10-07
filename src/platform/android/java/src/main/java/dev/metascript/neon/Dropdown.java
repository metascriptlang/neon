package dev.metascript.neon;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Spinner;
import android.widget.TextView;
import java.util.ArrayList;
import java.util.List;

final class Dropdown extends Spinner implements Control {
	private int tag;
	private int selected = -1;
	private int color = 0;
	private boolean writing;
	private final List<String> labels = new ArrayList<>();
	private final ArrayAdapter<String> adapter;

	Dropdown(Context context) {
		super(context, Spinner.MODE_DROPDOWN);
		adapter = new ArrayAdapter<String>(context, android.R.layout.simple_spinner_item, labels) {
			@Override public View getView(int position, View convert, ViewGroup parent) {
				View view = super.getView(position, convert, parent);
				if (color != 0 && view instanceof TextView) ((TextView)view).setTextColor(color);
				return view;
			}
		};
		adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
		setAdapter(adapter);
		setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
			@Override public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
				if (writing || tag == 0 || position == selected) return;
				Props.control(tag, 4, Integer.toString(position), 0, 0);
			}
			@Override public void onNothingSelected(AdapterView<?> parent) {}
		});
	}

	@Override public void setNeonTag(int value) { tag = value; }

	@Override protected void onMeasure(int widthSpec, int heightSpec) {
		super.onMeasure(widthSpec, heightSpec);
		if (Controls.intrinsicQuery(widthSpec, heightSpec)) setMeasuredDimension(0, getMeasuredHeight());
	}

	private void select() {
		if (selected < 0 || selected >= labels.size()) return;
		writing = true;
		setSelection(selected, false);
		writing = false;
	}

	@Override public void setProp(String name, String v) {
		switch (name) {
			case "items":
				labels.clear();
				if (!v.isEmpty()) {
					for (String record : v.split("\u001e", -1)) {
						int cut = record.indexOf('\u001f');
						labels.add(cut < 0 ? record : record.substring(0, cut));
					}
				}
				adapter.notifyDataSetChanged();
				select();
				break;
			case "selectedIndex":
				try { selected = Integer.parseInt(v); } catch (NumberFormatException e) { selected = -1; }
				select();
				break;
			case "prompt": setPrompt(v); break;
			case "disabled": setEnabled(!"true".equals(v)); break;
			case "color": color = v.isEmpty() ? 0 : Props.color(v, 0); adapter.notifyDataSetChanged(); break;
			default: break;
		}
	}
}
