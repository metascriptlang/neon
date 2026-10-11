package dev.metascript.neon;

import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.icu.util.LocaleData;
import android.icu.util.ULocale;
import android.os.BatteryManager;
import android.os.Build;
import android.os.LocaleList;
import android.text.TextUtils;
import android.text.format.DateFormat;
import android.view.HapticFeedbackConstants;
import android.view.View;
import java.text.DecimalFormatSymbols;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Currency;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

final class Device {
	private static final String FIELD = "\u001f";
	private static final String RECORD = "\u001e";
	private static final List<String> FAHRENHEIT = Arrays.asList("US", "BS", "BZ", "KY", "PW", "LR");

	private Device() {}

	static String call(Activity a, String name, String arg) {
		switch (name) {
			case "haptics.impact": return haptic(a, impact(arg));
			case "haptics.notification": return haptic(a, notification(arg));
			case "haptics.selection": return haptic(a, HapticFeedbackConstants.CLOCK_TICK);
			case "device.info": return info(a);
			case "device.battery": return battery(a);
			case "locale.info": return locales(a);
			default: throw new IllegalArgumentException("Neon App.call: unknown command " + name);
		}
	}

	private static int impact(String style) {
		switch (style) {
			case "light": return HapticFeedbackConstants.KEYBOARD_TAP;
			case "heavy": return HapticFeedbackConstants.LONG_PRESS;
			case "soft": return HapticFeedbackConstants.CLOCK_TICK;
			case "rigid": return HapticFeedbackConstants.CONTEXT_CLICK;
			default: return HapticFeedbackConstants.VIRTUAL_KEY;
		}
	}

	private static int notification(String type) {
		switch (type) {
			case "success": return Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.CONFIRM : HapticFeedbackConstants.VIRTUAL_KEY;
			case "error": return Build.VERSION.SDK_INT >= 30 ? HapticFeedbackConstants.REJECT : HapticFeedbackConstants.LONG_PRESS;
			default: return HapticFeedbackConstants.LONG_PRESS;
		}
	}

	private static String haptic(Activity a, int constant) {
		a.getWindow().getDecorView().performHapticFeedback(constant);
		return "";
	}

	private static boolean emulator() {
		return Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator")
			|| Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu")
			|| Build.MODEL.contains("Emulator") || Build.MODEL.contains("Android SDK built for")
			|| Build.PRODUCT.startsWith("sdk") || Build.PRODUCT.contains("emulator");
	}

	@SuppressWarnings("deprecation")
	private static String info(Activity a) {
		PackageManager packages = a.getPackageManager();
		String version = "";
		String build = "";
		try {
			PackageInfo info = packages.getPackageInfo(a.getPackageName(), 0);
			version = info.versionName == null ? "" : info.versionName;
			build = Build.VERSION.SDK_INT >= 28 ? Long.toString(info.getLongVersionCode()) : Integer.toString(info.versionCode);
		} catch (PackageManager.NameNotFoundException e) {
			throw new IllegalStateException("Neon DeviceInfo: the app's own package is not found", e);
		}
		ApplicationInfo application = a.getApplicationInfo();
		boolean tablet = a.getResources().getConfiguration().smallestScreenWidthDp >= 600;
		return String.join(FIELD, Build.BRAND, Build.MANUFACTURER, Build.MODEL, Build.BOARD, "Android",
			Build.VERSION.RELEASE, packages.getApplicationLabel(application).toString(), a.getPackageName(), version, build,
			emulator() ? "1" : "0", tablet ? "1" : "0");
	}

	private static String battery(Activity a) {
		BatteryManager manager = (BatteryManager) a.getSystemService(Context.BATTERY_SERVICE);
		int capacity = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY);
		String level = capacity < 0 || capacity > 100 ? "" : Double.toString(capacity / 100.0);
		return level + FIELD + (manager.isCharging() ? "1" : "0");
	}

	private static String measurement(Locale locale) {
		String region = locale.getCountry();
		if (region.isEmpty()) return "";
		if (Build.VERSION.SDK_INT >= 28) {
			LocaleData.MeasurementSystem system = LocaleData.getMeasurementSystem(ULocale.forLocale(locale));
			if (system == LocaleData.MeasurementSystem.US) return "us";
			if (system == LocaleData.MeasurementSystem.UK) return "uk";
			return "metric";
		}
		return region.equals("US") || region.equals("LR") || region.equals("MM") ? "us" : "metric";
	}

	private static String locale(Locale locale) {
		DecimalFormatSymbols symbols = DecimalFormatSymbols.getInstance(locale);
		String code = "";
		String symbol = "";
		if (!locale.getCountry().isEmpty()) {
			try {
				Currency currency = Currency.getInstance(locale);
				if (currency != null) {
					code = currency.getCurrencyCode();
					symbol = currency.getSymbol(locale);
				}
			} catch (IllegalArgumentException e) {
				code = "";
			}
		}
		boolean rtl = TextUtils.getLayoutDirectionFromLocale(locale) == View.LAYOUT_DIRECTION_RTL;
		String region = locale.getCountry();
		String temperature = region.isEmpty() ? "" : FAHRENHEIT.contains(region) ? "fahrenheit" : "celsius";
		return String.join(FIELD, locale.toLanguageTag(), locale.getLanguage(), locale.getScript(), region, rtl ? "rtl" : "ltr",
			String.valueOf(symbols.getDecimalSeparator()), String.valueOf(symbols.getGroupingSeparator()), measurement(locale),
			code, symbol, temperature);
	}

	private static String locales(Activity a) {
		List<String> records = new ArrayList<>();
		Calendar calendar = Calendar.getInstance();
		String type = Build.VERSION.SDK_INT >= 26 ? calendar.getCalendarType() : "gregory";
		records.add(String.join(FIELD, type, TimeZone.getDefault().getID(), DateFormat.is24HourFormat(a) ? "1" : "0",
			Integer.toString(calendar.getFirstDayOfWeek())));
		if (Build.VERSION.SDK_INT >= 24) {
			LocaleList list = LocaleList.getDefault();
			for (int i = 0; i < list.size(); i++) records.add(locale(list.get(i)));
		} else {
			records.add(locale(Locale.getDefault()));
		}
		return String.join(RECORD, records);
	}
}
