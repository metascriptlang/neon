#pragma once
#include <cstdint>
#include <memory>
#include "composition.h"

// The control phase a switch reports its flip with, as src/platform/native/bridge.h numbers it.
enum { kSwitchValueChange = 4 };

// RNW SwitchComponentView.cpp at aedf6c5 on this seam: a track and a thumb in the view's visual, redrawn from the
// props and the pointer state. The bridge owns the pointer and the event, which follows `value` rather than the click.
class SwitchControl {
public:
	SwitchControl(ICompositionContext *context, IVisual *root);
	~SwitchControl();

	bool SetProp(const char *name, const char *value);
	void Layout(float width, float height, float scale);
	void SetHovered(bool on);
	void SetPressed(bool on);

	bool Value() const { return value; }
	bool Disabled() const { return disabled; }
	bool Hovered() const { return hovered; }

	static void Measure(float *width, float *height);

private:
	void Update();
	void DrawTrack(int32_t pixelWidth, int32_t pixelHeight, Color fill, Color stroke, float strokeThickness);

	ICompositionContext *context;
	IVisual *root, *track, *thumb;
	std::unique_ptr<IDrawingSurface> surface;
	bool value = false;
	bool disabled = false;
	bool hovered = false;
	bool pressed = false;
	bool hasThumbColor = false, hasOnColor = false, hasOffColor = false;
	Color thumbColor = {}, onColor = {}, offColor = {};
	float width = 0, height = 0, scale = 0;
	int32_t drawnWidth = 0, drawnHeight = 0;
	Color drawnFill = {}, drawnStroke = {};
	float drawnThickness = -1;
};
