#pragma once
#include <windows.h>
#include <cstdint>
#include <string>

// UI Automation for the Windows host, after react-native-windows Composition at aedf6c5
// (CompositionRootAutomationProvider.cpp, CompositionDynamicAutomationProvider.cpp). automation.cpp owns the COM
// providers and the mapping from Neon's accessibility attributes to UIA; the host implements the functions below over
// its view tree. A view is named by an id that is never 0 and never reused while the view lives; kRootId is the
// container every top-level view hangs from.
namespace uia {

constexpr int kRootId = 1;

// The values niSetProp received for one view and the state the control keeps, as the wire encodes them.
struct Element {
	std::string label, hint, role, ariaRole, state, value, live, testId;
	std::wstring text;
	std::string inputText;
	bool accessible = false;
	bool pressable = false;
	bool isSwitch = false;
	bool switchOn = false;
	bool switchDisabled = false;
	bool isInput = false;
	bool isImage = false;
	bool focused = false;
	RECT bounds = {};
};

enum Direction { kParent, kNextSibling, kPreviousSibling, kFirstChild, kLastChild };

bool Describe(int id, Element *out);
int Navigate(int id, Direction direction);
int ElementAt(int pixelX, int pixelY);
int FocusedElement();
bool Invoke(int id);
bool Action(int id, const char *name);
bool Toggle(int id);
bool Focus(int id);

// Answers WM_GETOBJECT for the root object id; false leaves the message to the window proc.
bool GetObject(HWND hwnd, WPARAM wParam, LPARAM lParam, LRESULT *result);
void Disconnect(HWND hwnd);
bool Listening();

// Raise what changed between two descriptions of one view, for the UIA properties RNW raises
// (CompositionViewComponentView.cpp:860-938, SwitchComponentView.cpp:85).
void PropertiesChanged(int id, const Element &before, const Element &after);
void FocusChanged(int id);

}
