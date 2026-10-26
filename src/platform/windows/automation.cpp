#include "automation.h"
#include <uiautomation.h>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#ifndef UIA_E_NOTSUPPORTED
#define UIA_E_NOTSUPPORTED ((HRESULT)0x80040204L)
#endif

namespace uia {
namespace {

HWND g_hwnd = nullptr;

std::wstring widen(const std::string &utf8) {
	if (utf8.empty()) return std::wstring();
	int length = MultiByteToWideChar(CP_UTF8, 0, utf8.data(), (int)utf8.size(), nullptr, 0);
	std::wstring wide((size_t)length, L'\0');
	MultiByteToWideChar(CP_UTF8, 0, utf8.data(), (int)utf8.size(), &wide[0], length);
	return wide;
}

bool hasToken(const std::string &state, const char *token) {
	size_t length = strlen(token), at = 0;
	while (at <= state.size()) {
		size_t end = state.find(',', at);
		if (end == std::string::npos) end = state.size();
		if (end - at == length && !state.compare(at, length, token)) return true;
		at = end + 1;
	}
	return false;
}

// "min,max,now,text" as primitives.ms accessibilityValueText writes it: the numbers rounded and empty when absent, the
// text last so its commas stay its own.
struct Range {
	bool numeric = false;
	double min = 0, max = 0, now = 0;
	std::string text;
};

Range parseValue(const std::string &value) {
	Range range;
	std::string field[3];
	size_t at = 0;
	for (int i = 0; i < 3; i++) {
		size_t end = value.find(',', at);
		if (end == std::string::npos) return range;
		field[i] = value.substr(at, end - at);
		at = end + 1;
	}
	range.text = value.substr(at);
	range.numeric = !field[0].empty() && !field[1].empty() && !field[2].empty();
	if (range.numeric) {
		range.min = atof(field[0].c_str());
		range.max = atof(field[1].c_str());
		range.now = atof(field[2].c_str());
	}
	return range;
}

// UiaHelpers.cpp:317-380 GetControlTypeFromString, the accessibilityRole table; an unknown name falls to Group as :378-379 does.
long controlTypeFromString(const std::string &role) {
	struct Entry { const char *name; long type; };
	static const Entry table[] = {
		{"adjustable", UIA_SliderControlTypeId}, {"group", UIA_GroupControlTypeId}, {"search", UIA_GroupControlTypeId},
		{"radiogroup", UIA_GroupControlTypeId}, {"timer", UIA_GroupControlTypeId}, {"", UIA_GroupControlTypeId},
		{"button", UIA_ButtonControlTypeId}, {"imagebutton", UIA_ButtonControlTypeId}, {"switch", UIA_ButtonControlTypeId},
		{"togglebutton", UIA_ButtonControlTypeId}, {"checkbox", UIA_CheckBoxControlTypeId}, {"combobox", UIA_ComboBoxControlTypeId},
		{"alert", UIA_TextControlTypeId}, {"header", UIA_TextControlTypeId}, {"summary", UIA_TextControlTypeId},
		{"text", UIA_TextControlTypeId}, {"image", UIA_ImageControlTypeId}, {"keyboardkey", UIA_CustomControlTypeId},
		{"link", UIA_HyperlinkControlTypeId}, {"list", UIA_ListControlTypeId}, {"listitem", UIA_ListItemControlTypeId},
		{"menu", UIA_MenuControlTypeId}, {"menubar", UIA_MenuBarControlTypeId}, {"menuitem", UIA_MenuItemControlTypeId},
		{"none", UIA_GroupControlTypeId}, {"progressbar", UIA_ProgressBarControlTypeId}, {"radio", UIA_RadioButtonControlTypeId},
		{"scrollbar", UIA_ScrollBarControlTypeId}, {"spinbutton", UIA_SpinnerControlTypeId}, {"splitbutton", UIA_SplitButtonControlTypeId},
		{"tab", UIA_TabItemControlTypeId}, {"tablist", UIA_TabControlTypeId}, {"textinput", UIA_EditControlTypeId},
		{"searchbox", UIA_EditControlTypeId}, {"toolbar", UIA_ToolBarControlTypeId}, {"tree", UIA_TreeControlTypeId},
		{"treeitem", UIA_TreeItemControlTypeId}, {"pane", UIA_PaneControlTypeId},
	};
	for (const Entry &entry : table) {
		if (role == entry.name) return entry.type;
	}
	return UIA_GroupControlTypeId;
}

// UiaHelpers.cpp:382-470 GetControlTypeFromRole, the `role` table over the lowercase ARIA names; a role it does not list is Group (:469).
long controlTypeFromRole(const std::string &role) {
	struct Entry { const char *name; long type; };
	static const Entry table[] = {
		{"alert", UIA_TextControlTypeId}, {"application", UIA_WindowControlTypeId}, {"button", UIA_ButtonControlTypeId},
		{"checkbox", UIA_CheckBoxControlTypeId}, {"columnheader", UIA_HeaderControlTypeId}, {"combobox", UIA_ComboBoxControlTypeId},
		{"document", UIA_DocumentControlTypeId}, {"heading", UIA_TextControlTypeId}, {"img", UIA_ImageControlTypeId},
		{"link", UIA_HyperlinkControlTypeId}, {"list", UIA_ListControlTypeId}, {"listitem", UIA_ListItemControlTypeId},
		{"menu", UIA_MenuControlTypeId}, {"menubar", UIA_MenuBarControlTypeId}, {"menuitem", UIA_MenuItemControlTypeId},
		{"progressbar", UIA_ProgressBarControlTypeId}, {"radio", UIA_RadioButtonControlTypeId}, {"rowheader", UIA_HeaderControlTypeId},
		{"scrollbar", UIA_ScrollBarControlTypeId}, {"searchbox", UIA_EditControlTypeId}, {"separator", UIA_SeparatorControlTypeId},
		{"slider", UIA_SliderControlTypeId}, {"spinbutton", UIA_SpinnerControlTypeId}, {"status", UIA_StatusBarControlTypeId},
		{"switch", UIA_ButtonControlTypeId}, {"tab", UIA_TabItemControlTypeId}, {"table", UIA_TableControlTypeId},
		{"tablist", UIA_TabControlTypeId}, {"tabpanel", UIA_TabControlTypeId}, {"timer", UIA_ButtonControlTypeId},
		{"toolbar", UIA_ToolBarControlTypeId}, {"tooltip", UIA_ToolTipControlTypeId}, {"tree", UIA_TreeControlTypeId},
		{"treegrid", UIA_TreeControlTypeId}, {"treeitem", UIA_TreeItemControlTypeId},
	};
	for (const Entry &entry : table) {
		if (role == entry.name) return entry.type;
	}
	return UIA_GroupControlTypeId;
}

bool roleSet(const Element &e) { return !e.role.empty() && e.role != "none"; }

// CompositionDynamicAutomationProvider.cpp:335-341; DefaultControlType is "switch" for SwitchComponentView.cpp:342,
// "text" for ParagraphComponentView.cpp:910, "textinput" for the text input, and "group" for a view (CompositionViewComponentView.cpp:1140).
long controlType(const Element &e) {
	if (roleSet(e)) return controlTypeFromRole(e.role);
	if (!e.ariaRole.empty()) return controlTypeFromString(e.ariaRole);
	if (e.isSwitch) return controlTypeFromString("switch");
	if (e.isInput) return controlTypeFromString("textinput");
	if (e.isImage) return controlTypeFromString("image");
	if (!e.text.empty()) return controlTypeFromString("text");
	return controlTypeFromString("group");
}

// :350-357: accessibilityLabel, else the default name, which a paragraph takes from its text (ParagraphComponentView.cpp:914).
std::wstring nameOf(const Element &e) { return e.label.empty() ? e.text : widen(e.label); }

bool disabled(const Element &e) { return hasToken(e.state, "disabled") || e.switchDisabled; }

bool focusable(const Element &e) { return e.isInput || (e.isSwitch && !e.switchDisabled); }

// :391-401 IsControlElement and :378-389 IsContentElement.
bool controlElement(const Element &e) {
	return e.accessible && (e.ariaRole != "none" || roleSet(e));
}

// :254-259 and :192-203: a switch, or a state that carries checked, mixed or unchecked.
bool togglable(const Element &e) {
	return e.isSwitch || hasToken(e.state, "checked") || hasToken(e.state, "unchecked") || hasToken(e.state, "mixed");
}

// :826-841 get_ToggleState over GetToggleState (UiaHelpers.cpp:637-646), and the switch's value without a checked state.
ToggleState toggleState(const Element &e) {
	if (hasToken(e.state, "mixed")) return ToggleState_Indeterminate;
	if (hasToken(e.state, "checked")) return ToggleState_On;
	if (hasToken(e.state, "unchecked")) return ToggleState_Off;
	return e.switchOn ? ToggleState_On : ToggleState_Off;
}

// :178-189 expandableControl, :855-873 get_ExpandCollapseState and UiaHelpers.cpp:530-536.
bool expandable(const Element &e) { return hasToken(e.state, "expanded") || hasToken(e.state, "collapsed"); }
ExpandCollapseState expandState(const Element &e) { return hasToken(e.state, "expanded") ? ExpandCollapseState_Expanded : ExpandCollapseState_Collapsed; }

// :240-251: a numeric accessibilityValue is a range, a text one (or a text input without numbers) is a value.
bool rangeValue(const Element &e) { return parseValue(e.value).numeric; }
bool textValue(const Element &e) { return !parseValue(e.value).text.empty() || (e.isInput && !parseValue(e.value).numeric); }
std::wstring valueText(const Element &e) { return e.isInput ? widen(e.inputText) : widen(parseValue(e.value).text); }

// UiaHelpers.cpp:257-264 GetLiveSetting.
long liveSetting(const Element &e) {
	if (e.live == "polite") return Polite;
	if (e.live == "assertive") return Assertive;
	return Off;
}

void setBstr(VARIANT *v, const std::wstring &s) {
	v->vt = VT_BSTR;
	v->bstrVal = SysAllocStringLen(s.data(), (UINT)s.size());
}

void setBool(VARIANT *v, bool b) {
	v->vt = VT_BOOL;
	v->boolVal = b ? VARIANT_TRUE : VARIANT_FALSE;
}

void setInt(VARIANT *v, long n) {
	v->vt = VT_I4;
	v->lVal = n;
}

// One value per property, for GetPropertyValue (:312-491) and for the old and new sides of a change event; false for a
// property the element does not answer.
bool property(const Element &e, PROPERTYID id, VARIANT *v) {
	VariantInit(v);
	switch (id) {
	case UIA_ControlTypePropertyId: setInt(v, controlType(e)); return true;
	case UIA_AutomationIdPropertyId: setBstr(v, widen(e.testId)); return true;
	case UIA_NamePropertyId: setBstr(v, nameOf(e)); return true;
	case UIA_IsKeyboardFocusablePropertyId: setBool(v, focusable(e)); return true;
	case UIA_HasKeyboardFocusPropertyId: setBool(v, e.focused); return true;
	case UIA_IsEnabledPropertyId: setBool(v, !disabled(e)); return true;
	case UIA_IsContentElementPropertyId:
	case UIA_IsControlElementPropertyId: setBool(v, controlElement(e)); return true;
	case UIA_HelpTextPropertyId: setBstr(v, widen(e.hint)); return true;
	case UIA_LiveSettingPropertyId: setInt(v, liveSetting(e)); return true;
	case UIA_ItemStatusPropertyId: setBstr(v, hasToken(e.state, "busy") ? L"Busy" : L""); return true;
	case UIA_ToggleToggleStatePropertyId:
		if (!togglable(e)) return false;
		setInt(v, toggleState(e));
		return true;
	case UIA_ExpandCollapseExpandCollapseStatePropertyId:
		if (!expandable(e)) return false;
		setInt(v, expandState(e));
		return true;
	case UIA_RangeValueValuePropertyId:
		if (!rangeValue(e)) return false;
		v->vt = VT_R8;
		v->dblVal = parseValue(e.value).now;
		return true;
	case UIA_ValueValuePropertyId:
		if (!textValue(e)) return false;
		setBstr(v, valueText(e));
		return true;
	}
	return false;
}

bool sameValue(const VARIANT &a, const VARIANT &b) {
	if (a.vt != b.vt) return false;
	switch (a.vt) {
	case VT_BSTR: return !wcscmp(a.bstrVal ? a.bstrVal : L"", b.bstrVal ? b.bstrVal : L"");
	case VT_BOOL: return a.boolVal == b.boolVal;
	case VT_I4: return a.lVal == b.lVal;
	case VT_R8: return a.dblVal == b.dblVal;
	}
	return true;
}

HRESULT rectOfRoot(HWND hwnd, UiaRect *rect) {
	if (!hwnd || !IsWindow(hwnd)) return UIA_E_ELEMENTNOTAVAILABLE;
	POINT point{0, 0};
	ClientToScreen(hwnd, &point);
	RECT client;
	GetClientRect(hwnd, &client);
	rect->left = point.x;
	rect->top = point.y;
	rect->width = client.right;
	rect->height = client.bottom;
	return S_OK;
}

SAFEARRAY *runtimeId(std::initializer_list<int> parts) {
	SAFEARRAY *array = SafeArrayCreateVector(VT_I4, 0, (ULONG)parts.size());
	if (!array) return nullptr;
	long i = 0;
	for (int part : parts) {
		SafeArrayPutElement(array, &i, &part);
		i++;
	}
	return array;
}

// CompositionRootAutomationProvider.cpp: the fragment root a window hosts.
class Root : public IRawElementProviderSimple, public IRawElementProviderFragment, public IRawElementProviderFragmentRoot {
public:
	explicit Root(HWND hwnd) : hwnd(hwnd) {}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override;
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG left = --refs;
		if (!left) delete this;
		return left;
	}

	HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *out) override {
		if (!out) return E_POINTER;
		*out = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID, IUnknown **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID id, VARIANT *out) override {
		if (!out) return E_POINTER;
		VariantInit(out);
		if (id == UIA_ControlTypePropertyId) setInt(out, UIA_GroupControlTypeId);
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
		if (!out) return E_POINTER;
		if (!IsWindow(hwnd)) return UIA_E_ELEMENTNOTAVAILABLE;
		UiaHostProviderFromHwnd(hwnd, out);
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override;
	HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
		if (!out) return E_POINTER;
		*out = runtimeId({UiaAppendRuntimeId, kRootId, 0});
		return *out ? S_OK : E_OUTOFMEMORY;
	}
	HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
		if (!out) return E_POINTER;
		return rectOfRoot(hwnd, out);
	}
	HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE SetFocus() override {
		::SetFocus(hwnd);
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
		if (!out) return E_POINTER;
		*out = this;
		AddRef();
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **out) override;
	HRESULT STDMETHODCALLTYPE GetFocus(IRawElementProviderFragment **out) override;

private:
	std::atomic<ULONG> refs{1};
	HWND hwnd;
};

// CompositionDynamicAutomationProvider.cpp: one view, answered from the host each time because the view may be gone.
class Node : public IRawElementProviderSimple,
	public IRawElementProviderFragment,
	public IInvokeProvider,
	public IToggleProvider,
	public IRangeValueProvider,
	public IValueProvider,
	public IExpandCollapseProvider {
public:
	explicit Node(int id) : id(id) {}

	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override;
	ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
	ULONG STDMETHODCALLTYPE Release() override {
		ULONG left = --refs;
		if (!left) delete this;
		return left;
	}

	HRESULT STDMETHODCALLTYPE get_ProviderOptions(ProviderOptions *out) override {
		if (!out) return E_POINTER;
		*out = (ProviderOptions)(ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading);
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE GetPatternProvider(PATTERNID pattern, IUnknown **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		IUnknown *found = nullptr;
		if (pattern == UIA_InvokePatternId && e.pressable) found = static_cast<IInvokeProvider *>(this);
		else if (pattern == UIA_RangeValuePatternId && rangeValue(e)) found = static_cast<IRangeValueProvider *>(this);
		else if (pattern == UIA_ValuePatternId && textValue(e)) found = static_cast<IValueProvider *>(this);
		else if (pattern == UIA_TogglePatternId && togglable(e)) found = static_cast<IToggleProvider *>(this);
		else if (pattern == UIA_ExpandCollapsePatternId && expandable(e)) found = static_cast<IExpandCollapseProvider *>(this);
		if (found) {
			*out = found;
			AddRef();
		}
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE GetPropertyValue(PROPERTYID property_, VARIANT *out) override {
		if (!out) return E_POINTER;
		VariantInit(out);
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		if (!property(e, property_, out)) VariantInit(out);
		return out->vt == VT_BSTR && !out->bstrVal ? E_OUTOFMEMORY : S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_HostRawElementProvider(IRawElementProviderSimple **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE Navigate(NavigateDirection direction, IRawElementProviderFragment **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		int next = uia::Navigate(id, (Direction)direction);
		if (next == kRootId) {
			*out = new Root(g_hwnd);
		} else if (next != 0) {
			*out = new Node(next);
		}
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE GetRuntimeId(SAFEARRAY **out) override {
		if (!out) return E_POINTER;
		*out = runtimeId({UiaAppendRuntimeId, id});
		return *out ? S_OK : E_OUTOFMEMORY;
	}
	// :88-123: the view's rectangle in its window plus the fragment root's origin on the screen.
	HRESULT STDMETHODCALLTYPE get_BoundingRectangle(UiaRect *out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		UiaRect origin;
		HRESULT hr = rectOfRoot(g_hwnd, &origin);
		if (FAILED(hr)) return hr;
		out->left = e.bounds.left + origin.left;
		out->top = e.bounds.top + origin.top;
		out->width = e.bounds.right - e.bounds.left;
		out->height = e.bounds.bottom - e.bounds.top;
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE GetEmbeddedFragmentRoots(SAFEARRAY **out) override {
		if (!out) return E_POINTER;
		*out = nullptr;
		return S_OK;
	}
	// :134 over UiaSetFocusHelper (UiaHelpers.cpp:149-166): E_FAIL when the view cannot take focus.
	HRESULT STDMETHODCALLTYPE SetFocus() override {
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		return uia::Focus(id) ? S_OK : E_FAIL;
	}
	HRESULT STDMETHODCALLTYPE get_FragmentRoot(IRawElementProviderFragmentRoot **out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e) || !g_hwnd) return UIA_E_ELEMENTNOTAVAILABLE;
		*out = new Root(g_hwnd);
		return S_OK;
	}

	// :503-524: the press a click makes, then the Invoked event.
	HRESULT STDMETHODCALLTYPE Invoke() override {
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		if (e.isSwitch && e.switchDisabled) return UIA_E_ELEMENTNOTENABLED;
		if (!uia::Invoke(id)) return UIA_E_INVALIDOPERATION;
		Node *node = new Node(id);
		UiaRaiseAutomationEvent(node, UIA_Invoke_InvokedEventId);
		node->Release();
		return S_OK;
	}

	HRESULT STDMETHODCALLTYPE get_ToggleState(ToggleState *out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		*out = toggleState(e);
		return S_OK;
	}
	// :844-853: the switch asks its handler for the opposite value, as a click does.
	HRESULT STDMETHODCALLTYPE Toggle() override {
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		if (disabled(e)) return UIA_E_ELEMENTNOTENABLED;
		return uia::Toggle(id) ? S_OK : UIA_E_INVALIDOPERATION;
	}

	// :759-824: read from accessibilityValue; SetValue only dispatches "setValue" (:814-824), the app writes the value back.
	HRESULT STDMETHODCALLTYPE get_Value(double *out) override { return range(out, &Range::now); }
	HRESULT STDMETHODCALLTYPE get_Maximum(double *out) override { return range(out, &Range::max); }
	HRESULT STDMETHODCALLTYPE get_Minimum(double *out) override { return range(out, &Range::min); }
	HRESULT STDMETHODCALLTYPE get_LargeChange(double *out) override { return unchanged(out); }
	HRESULT STDMETHODCALLTYPE get_SmallChange(double *out) override { return unchanged(out); }
	HRESULT STDMETHODCALLTYPE SetValue(double) override { return act("setValue"); }

	// :720-732 get_Value(BSTR) and :706-719 SetValue(LPCWSTR).
	HRESULT STDMETHODCALLTYPE get_Value(BSTR *out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		std::wstring text = valueText(e);
		*out = SysAllocStringLen(text.data(), (UINT)text.size());
		return *out || text.empty() ? S_OK : E_OUTOFMEMORY;
	}
	HRESULT STDMETHODCALLTYPE SetValue(LPCWSTR) override { return act("setValue"); }
	// :734-753: accessibilityState.readOnly, false when the state does not say.
	HRESULT STDMETHODCALLTYPE get_IsReadOnly(BOOL *out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		*out = hasToken(e.state, "readOnly");
		return S_OK;
	}

	// :855-892: the state reads from accessibilityState; Expand and Collapse dispatch the declared "expand"/"collapse".
	HRESULT STDMETHODCALLTYPE get_ExpandCollapseState(ExpandCollapseState *out) override {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		*out = expandState(e);
		return S_OK;
	}
	HRESULT STDMETHODCALLTYPE Expand() override { return act("expand"); }
	HRESULT STDMETHODCALLTYPE Collapse() override { return act("collapse"); }

private:
	// DispatchAccessibilityAction answers S_OK whether or not the view declared the action.
	HRESULT act(const char *name) {
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		uia::Action(id, name);
		return S_OK;
	}
	HRESULT range(double *out, double Range::*member) {
		if (!out) return E_POINTER;
		Element e;
		if (!Describe(id, &e)) return UIA_E_ELEMENTNOTAVAILABLE;
		Range parsed = parseValue(e.value);
		if (!parsed.numeric) return UIA_E_NOTSUPPORTED;
		*out = parsed.*member;
		return S_OK;
	}
	HRESULT unchanged(double *out) {
		if (!out) return E_POINTER;
		*out = 0;
		return S_OK;
	}

	std::atomic<ULONG> refs{1};
	int id;
};

HRESULT Root::QueryInterface(REFIID iid, void **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	if (iid == __uuidof(IUnknown) || iid == __uuidof(IRawElementProviderSimple)) *out = static_cast<IRawElementProviderSimple *>(this);
	else if (iid == __uuidof(IRawElementProviderFragment)) *out = static_cast<IRawElementProviderFragment *>(this);
	else if (iid == __uuidof(IRawElementProviderFragmentRoot)) *out = static_cast<IRawElementProviderFragmentRoot *>(this);
	else return E_NOINTERFACE;
	AddRef();
	return S_OK;
}

// :264-291: the root's first and last child are the top-level views.
HRESULT Root::Navigate(NavigateDirection direction, IRawElementProviderFragment **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	if (direction == NavigateDirection_FirstChild || direction == NavigateDirection_LastChild) {
		int child = uia::Navigate(kRootId, (Direction)direction);
		if (child) *out = new Node(child);
	}
	return S_OK;
}

// :201-227: a screen point into the window, to the deepest view under it.
HRESULT Root::ElementProviderFromPoint(double x, double y, IRawElementProviderFragment **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	POINT at{(LONG)x, (LONG)y};
	ScreenToClient(hwnd, &at);
	int found = ElementAt(at.x, at.y);
	if (found) *out = new Node(found);
	return S_OK;
}

// :229-254: the focused view, none when no view holds focus.
HRESULT Root::GetFocus(IRawElementProviderFragment **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	int focused = FocusedElement();
	if (focused) *out = new Node(focused);
	return S_OK;
}

HRESULT Node::QueryInterface(REFIID iid, void **out) {
	if (!out) return E_POINTER;
	*out = nullptr;
	if (iid == __uuidof(IUnknown) || iid == __uuidof(IRawElementProviderSimple)) *out = static_cast<IRawElementProviderSimple *>(this);
	else if (iid == __uuidof(IRawElementProviderFragment)) *out = static_cast<IRawElementProviderFragment *>(this);
	else if (iid == __uuidof(IInvokeProvider)) *out = static_cast<IInvokeProvider *>(this);
	else if (iid == __uuidof(IToggleProvider)) *out = static_cast<IToggleProvider *>(this);
	else if (iid == __uuidof(IRangeValueProvider)) *out = static_cast<IRangeValueProvider *>(this);
	else if (iid == __uuidof(IValueProvider)) *out = static_cast<IValueProvider *>(this);
	else if (iid == __uuidof(IExpandCollapseProvider)) *out = static_cast<IExpandCollapseProvider *>(this);
	else return E_NOINTERFACE;
	AddRef();
	return S_OK;
}

}

bool GetObject(HWND hwnd, WPARAM wParam, LPARAM lParam, LRESULT *result) {
	if (lParam != (LPARAM)UiaRootObjectId) return false;
	g_hwnd = hwnd;
	Root *root = new Root(hwnd);
	*result = UiaReturnRawElementProvider(hwnd, wParam, lParam, root);
	root->Release();
	return true;
}

bool Listening() { return UiaClientsAreListening(); }

void Disconnect(HWND hwnd) {
	UiaReturnRawElementProvider(hwnd, 0, 0, nullptr);
	if (g_hwnd == hwnd) g_hwnd = nullptr;
}

void PropertiesChanged(int id, const Element &before, const Element &after) {
	static const PROPERTYID watched[] = {
		UIA_NamePropertyId, UIA_HelpTextPropertyId, UIA_ControlTypePropertyId, UIA_IsEnabledPropertyId,
		UIA_IsKeyboardFocusablePropertyId, UIA_IsControlElementPropertyId, UIA_IsContentElementPropertyId,
		UIA_LiveSettingPropertyId, UIA_ItemStatusPropertyId, UIA_ToggleToggleStatePropertyId,
		UIA_ExpandCollapseExpandCollapseStatePropertyId, UIA_RangeValueValuePropertyId, UIA_ValueValuePropertyId,
	};
	for (PROPERTYID property_ : watched) {
		VARIANT was, now;
		bool hadOld = property(before, property_, &was);
		bool hasNew = property(after, property_, &now);
		if (hadOld && hasNew && !sameValue(was, now)) {
			Node *node = new Node(id);
			UiaRaiseAutomationPropertyChangedEvent(node, property_, was, now);
			node->Release();
		}
		VariantClear(&was);
		VariantClear(&now);
	}
}

// CompositionViewComponentView.cpp:415-435: HasKeyboardFocus, then the focus-changed event, on the view that got focus.
void FocusChanged(int id) {
	if (!id) return;
	Node *node = new Node(id);
	VARIANT was, now;
	setBool(&was, false);
	setBool(&now, true);
	UiaRaiseAutomationPropertyChangedEvent(node, UIA_HasKeyboardFocusPropertyId, was, now);
	UiaRaiseAutomationEvent(node, UIA_AutomationFocusChangedEventId);
	node->Release();
}

}
