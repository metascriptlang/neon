import { stickyTranslation } from "../../../src/components/list/sticky";

test "RN ScrollViewStickyHeader.js:201-223 normal header starts at its layout position" {
	assert stickyTranslation(100.0, 40.0, 300.0, 0.0, 500.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 99.5, 500.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 100.0, 500.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 100.5, 500.0, false) === 0.5;
	assert stickyTranslation(100.0, 40.0, 300.0, 150.0, 500.0, false) === 50.0;
}

test "RN ScrollViewStickyHeader.js:216-219 normal collision stops at the next header" {
	assert stickyTranslation(100.0, 40.0, 300.0, 259.5, 500.0, false) === 159.5;
	assert stickyTranslation(100.0, 40.0, 300.0, 260.0, 500.0, false) === 160.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 260.5, 500.0, false) === 160.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 900.0, 500.0, false) === 160.0;
}

test "RN ScrollViewStickyHeader.js:217-219 normal collision equal to layout prevents sticking" {
	assert stickyTranslation(100.0, 40.0, 140.0, 99.0, 500.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 140.0, 100.0, 500.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 140.0, 500.0, 500.0, false) === 0.0;
}

test "RN ScrollViewStickyHeader.js:214-223 last normal header sticks without a successor" {
	assert stickyTranslation(100.0, 40.0, null, 150.0, 500.0, false) === 50.0;
	assert stickyTranslation(100.0, 40.0, null, 10000.0, 500.0, false) === 9900.0;
}

test "RN ScrollViewStickyHeader.js:214-223 missing next measurement leaves normal translation uncapped" {
	assert stickyTranslation(100.0, 40.0, null, 500.0, 500.0, false) === 400.0;
	assert stickyTranslation(100.0, 40.0, 0.0, 500.0, 500.0, false) === 400.0;
}

test "RN ScrollViewStickyHeader.js:216-223 overlapping normal headers do not create a negative cap" {
	assert stickyTranslation(100.0, 40.0, 139.5, 500.0, 500.0, false) === 400.0;
	assert stickyTranslation(100.0, 40.0, 90.0, 500.0, 500.0, false) === 400.0;
}

test "RN ScrollViewStickyHeader.js:181-199 inverted headers in the initial viewport never stick" {
	assert stickyTranslation(100.0, 40.0, 1000.0, 1000.0, 300.0, true) === 0.0;
	assert stickyTranslation(260.0, 40.0, 1000.0, 1000.0, 300.0, true) === 0.0;
}

test "RN ScrollViewStickyHeader.js:182-187 inverted header starts at the viewport bottom" {
	assert stickyTranslation(500.0, 40.0, null, 0.0, 300.0, true) === 0.0;
	assert stickyTranslation(500.0, 40.0, null, 239.5, 300.0, true) === 0.0;
	assert stickyTranslation(500.0, 40.0, null, 240.0, 300.0, true) === 0.0;
	assert stickyTranslation(500.0, 40.0, null, 240.5, 300.0, true) === 0.5;
	assert stickyTranslation(500.0, 40.0, null, 300.0, 300.0, true) === 60.0;
}

test "RN ScrollViewStickyHeader.js:190-197 inverted collision stops further translation" {
	assert stickyTranslation(500.0, 40.0, 1000.0, 659.5, 300.0, true) === 419.5;
	assert stickyTranslation(500.0, 40.0, 1000.0, 660.0, 300.0, true) === 420.0;
	assert stickyTranslation(500.0, 40.0, 1000.0, 660.5, 300.0, true) === 420.0;
	assert stickyTranslation(500.0, 40.0, 1000.0, 2000.0, 300.0, true) === 420.0;
}

test "RN ScrollViewStickyHeader.js:190-198 inverted equality and overlap leave translation uncapped" {
	assert stickyTranslation(500.0, 40.0, 580.0, 1000.0, 300.0, true) === 760.0;
	assert stickyTranslation(500.0, 40.0, 579.5, 1000.0, 300.0, true) === 760.0;
}

test "RN ScrollViewStickyHeader.js:188-198 last or unmeasured inverted successor leaves translation uncapped" {
	assert stickyTranslation(500.0, 40.0, null, 10000.0, 300.0, true) === 9760.0;
	assert stickyTranslation(500.0, 40.0, 0.0, 10000.0, 300.0, true) === 9760.0;
}

test "RN ScrollViewStickyHeader.js:162-163 negative overscroll never translates a header" {
	assert stickyTranslation(0.0, 40.0, null, -0.25, 300.0, false) === 0.0;
	assert stickyTranslation(100.0, 40.0, 300.0, -50.0, 300.0, false) === 0.0;
	assert stickyTranslation(-20.0, 40.0, null, -10.0, 300.0, false) === 0.0;
	assert stickyTranslation(500.0, 40.0, null, -50.0, 300.0, true) === 0.0;
}

test "RN ScrollViewStickyHeader.js:182-219 fractional geometry is not rounded" {
	assert stickyTranslation(100.25, 40.5, 300.75, 100.5, 500.0, false) === 0.25;
	assert stickyTranslation(100.25, 40.5, 300.75, 900.0, 500.0, false) === 160.0;
	assert stickyTranslation(500.25, 40.5, 1000.75, 241.0, 300.25, true) === 0.5;
	assert stickyTranslation(500.25, 40.5, 1000.75, 2000.0, 300.25, true) === 419.5;
}

test "RN ScrollViewStickyHeader.js:182-198 viewport resize recalculates inverted sticking" {
	assert stickyTranslation(500.0, 40.0, null, 300.0, 300.0, true) === 60.0;
	assert stickyTranslation(500.0, 40.0, null, 300.0, 400.0, true) === 160.0;
	assert stickyTranslation(500.0, 40.0, null, 300.0, 540.0, true) === 0.0;
	assert stickyTranslation(500.0, 40.0, null, 300.0, 600.0, true) === 0.0;
	assert stickyTranslation(500.0, 40.0, 1000.0, 700.0, 300.0, true) === 420.0;
	assert stickyTranslation(500.0, 40.0, 1000.0, 700.0, 400.0, true) === 420.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 150.0, 300.0, false) === 50.0;
	assert stickyTranslation(100.0, 40.0, 300.0, 150.0, 600.0, false) === 50.0;
}
