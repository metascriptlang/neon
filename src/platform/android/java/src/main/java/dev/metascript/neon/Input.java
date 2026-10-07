package dev.metascript.neon;

import android.content.Context;
import android.text.Editable;
import android.text.InputFilter;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;

public final class Input extends EditText {
	private int tag;
	private boolean writing;
	private boolean multiline;
	private boolean secure;
	private boolean autoFocus;
	private boolean blurOnSubmit = true;
	private String keyboardType = "default";
	private String capitalize = "sentences";
	private boolean autoCorrect = true;

	public Input(Context context) {
		super(context);
		setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
		applyInputType();
		addTextChangedListener(new TextWatcher() {
			@Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
			@Override public void onTextChanged(CharSequence s, int start, int before, int count) {}
			@Override public void afterTextChanged(Editable s) {
				if (!writing && tag != 0) Props.control(tag, 0, s.toString(), 0, 0);
			}
		});
		setOnFocusChangeListener((view, focused) -> {
			if (tag != 0) Props.control(tag, focused ? 1 : 2, getText().toString(), 0, 0);
		});
		setOnEditorActionListener((view, action, event) -> {
			if (multiline && event != null) return false;
			if (event != null && event.getAction() != KeyEvent.ACTION_DOWN) return true;
			if (tag != 0) Props.control(tag, 3, getText().toString(), 0, 0);
			if (blurOnSubmit && !multiline) setFocused(false);
			return true;
		});
	}

	public void setNeonTag(int value) { tag = value; }

	public void setFocused(boolean focused) {
		InputMethodManager manager = (InputMethodManager)getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
		if (focused) {
			setFocusableInTouchMode(true);
			requestFocus();
			manager.showSoftInput(this, InputMethodManager.SHOW_IMPLICIT);
		} else if (isFocused()) {
			manager.hideSoftInputFromWindow(getWindowToken(), 0);
			clearFocus();
		}
	}

	@Override protected void onAttachedToWindow() {
		super.onAttachedToWindow();
		if (autoFocus) post(() -> setFocused(true));
	}

	private void applyInputType() {
		int type;
		switch (keyboardType) {
			case "numeric": case "number-pad": type = InputType.TYPE_CLASS_NUMBER; break;
			case "decimal-pad": type = InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL; break;
			case "phone-pad": type = InputType.TYPE_CLASS_PHONE; break;
			case "email-address": type = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS; break;
			case "url": type = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI; break;
			default: type = InputType.TYPE_CLASS_TEXT; break;
		}
		if ((type & InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT) {
			if (secure) type |= InputType.TYPE_TEXT_VARIATION_PASSWORD;
			if (multiline) type |= InputType.TYPE_TEXT_FLAG_MULTI_LINE;
			if (!autoCorrect) type |= InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
			switch (capitalize) {
				case "characters": type |= InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS; break;
				case "words": type |= InputType.TYPE_TEXT_FLAG_CAP_WORDS; break;
				case "sentences": type |= InputType.TYPE_TEXT_FLAG_CAP_SENTENCES; break;
				default: break;
			}
		} else if (secure && (type & InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_NUMBER) {
			type |= InputType.TYPE_NUMBER_VARIATION_PASSWORD;
		}
		int start = getSelectionStart();
		int end = getSelectionEnd();
		setInputType(type);
		setSingleLine(!multiline);
		if (start >= 0 && end >= 0 && end <= length()) setSelection(start, end);
	}

	private static int imeAction(String value) {
		switch (value) {
			case "go": return EditorInfo.IME_ACTION_GO;
			case "next": return EditorInfo.IME_ACTION_NEXT;
			case "search": return EditorInfo.IME_ACTION_SEARCH;
			case "send": return EditorInfo.IME_ACTION_SEND;
			default: return EditorInfo.IME_ACTION_DONE;
		}
	}

	public void setProp(String name, String value) {
		boolean yes = "true".equals(value);
		switch (name) {
			case "value":
				if (!value.equals(getText().toString())) {
					writing = true;
					setText(value);
					setSelection(length());
					writing = false;
				}
				break;
			case "defaultValue":
				if (length() == 0) { writing = true; setText(value); writing = false; }
				break;
			case "placeholder": setHint(value); break;
			case "placeholderTextColor": setHintTextColor(Props.color(value, 0xff888888)); break;
			case "editable": setEnabled(value.isEmpty() || yes); break;
			case "secureTextEntry": secure = yes; applyInputType(); break;
			case "multiline": multiline = yes; applyInputType(); break;
			case "keyboardType": keyboardType = value.isEmpty() ? "default" : value; applyInputType(); break;
			case "autoCapitalize": capitalize = value.isEmpty() ? "sentences" : value; applyInputType(); break;
			case "autoCorrect": autoCorrect = value.isEmpty() || yes; applyInputType(); break;
			case "returnKeyType": setImeOptions(imeAction(value)); break;
			case "blurOnSubmit": blurOnSubmit = value.isEmpty() || yes; break;
			case "autoFocus": autoFocus = yes; if (yes && isAttachedToWindow()) post(() -> setFocused(true)); break;
			case "maxLength":
				setFilters(value.isEmpty() ? new InputFilter[0] : new InputFilter[] { new InputFilter.LengthFilter(Integer.parseInt(value)) });
				break;
			default: break;
		}
	}
}
