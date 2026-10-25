# Void through Neon JSX

## Goal and baseline

Neon is to Void what React Three Fiber is to Three.js: JSX mounts Void's render concepts,
reactive props update them, and the owner tree releases them. This is coverage of Void's
render vocabulary, not a copy of Three.js's API or a second renderer.

Scope confirmed 2026-10-07: all existing void2d/void3d render concepts, including resources,
text, animation/effects, picking and composition. GPU commands, buffers and passes are not
JSX tags. Math, geometry construction and asset decoding remain ordinary Void helpers;
the app must not have to write mount builders or frame glue to make the component path work.
No new backend or feature absent from Void is required.

Inventory refreshed 2026-10-07: Void `d255ffb` (original inventory `b278254`), source tree
`7f61a6576e2cd03402d4bc65da4599e70db6e862`. The original 26 void2d and 26 void3d `.ms`
modules were inspected; the refresh adds `dirShadowMap.ms` and reads the changed material,
program-key and renderer paths. All 26 void2d and 27 void3d modules are accounted for below. This is a source inventory, not a
run of Void's gates. Recheck the inventory when the consumed Void changes; a new capability
must be accounted for explicitly, not silently excluded or declared implemented.

Void paths below are relative to its repository. Neon paths are relative to this one.
A **reference consumer** is existing Void code to follow, not evidence that Neon works.
Every row requires a Neon JSX consumer before it can be accepted. Component/prop assignments
in missing rows are candidate mappings; unchosen names and ownership details are not approvals.

## Current audit — 2026-10-15

The baseline inventory above is not a fresh inventory of consumed Void `f874af6a4`.
New layer/render-order/camera-layer and HDR/tone/bloom APIs remain mapping candidates,
not silently accepted coverage. No percentage or whole-row completion follows.

- Main `743c79c` host/ScrollView and Ion `1b3d40c` macOS prerequisites are consumed.
  Actual raw/UI operations now reuse `src/platform/void/host.ms`; area presentation,
  per-scene font/input/frame registration and real Ion acceptance remain absent.
- Frozen `2f27d19`/tree `24153969eaa7f724160b75bd0652cee4cdcf018d`, installed
  binary/support `15b93cbba`, Void `f874af6a4`, Yoga `ce52e2e`, Ion `1b3d40c`:
  `NO_COLOR=1 NEON_BROWSER_PORT=8734 bash tests/run.sh` exits1. Native143/8,
  JS119/4 with28 skipped; macros17, app target-runs6, refresh runs9,
  Chrome22 requested files/144 cases and edge3 scenario groups pass. Identical
  source/binary/BUILD/dependency HEADs before/after; no same-epoch main control.
  Raw log/scope: `/tmp/neon-void-audit-current-full-gate.{log,scope.json}`.
  This supersedes no historical epoch and proves neither pixels nor idle/input.
- Gate failures: native FlutterLists, Void host nullish union, FlatList macro capture,
  Graphics/GraphicsPaint computed-discriminant C move, Paint kind48, Tile's two
  fresh-bounds cases, and original16 Scene3D projection layout. JS FlutterLists,
  FlatList, native header reexport and new VoidRaw's unsupported pointer arithmetic.
  The latter is a runner omission, fixed by native-only selection in `d7108a3`;
  selection check changes only that file, not native discovery. No later whole-gate
  totals claimed. Compiler cards preserve expressions and remain owner work.
- Real textured Gltf: `msc run tests/device/scene3dGltf.ms` on `ffd54e0`/tree
  `092fa5fe228084e1de06f1f9ee1e54d35ad1e08e`, stable `15b93cbba`/Void `f874af6a4`,
  exits0:12 frames/5 meshes, invalid-root failure preservation, replacement,
  hide/remount and terminal GPU resource reclamation. Exact Gltf source files remain
  unchanged through `2f27d19`. Metadata probes return1/1; old Metal abort is resolved.
  CPU fixture has5 own/303 total cases including actual material/uniform rollback.
  These are resource/submission proofs, not observed pixels or Ion composition.
- Fresh host review found rollback/Row, raw text-paint inheritance and onLayout wake
  regressions. `a88943e` and `e8384d2` fix the latter two through existing host paths;
  new pins go322/1→323/0 and323/1→324/0, input importer330/0. Scopes record the
  respective precommit HEAD plus WIP, not retrospective committed executions.
  Independent native follow-up `5307a1f9` confirms only those two fixes. Raw rollback
  remains partial: detached Group children bypass wrapper/Yoga release. On `16d8a1f`/
  tree `cee747f46bb06642243def3ddece5857a38e74a0` plus recorded WIP, the new Order pin
  leaves321 pass/2 fail (detached cleanup and independent boundary reset). Intended
  descendant-removal loop then prevents runtime proof: three-line Group consumer
  check exceeds30s; removing only that loop checks133 modules. Stable compiler15;
  `/tmp/neon-void-audit-current-detached-{rollback-red,loop-consumer,loop-consumer-control}.scope.json`
  record exact source/BUILD/binary/deps. This is not a completed cleanup fix; owner
  card and parked sites are in `BUGS.md`. No helper/alias workaround.
- Initial ErrorBoundary reset is fixed in `a6eaf87` (committed tree
  `79cf887299ed1ce5e807b9c1c4ebc819a1fd4301`), through existing `batch` in
  `src/render/node.ms` `regionNode`. Only the bounded protected renderer fix was
  approved; Host/signal/JSX API and scheduler stay unchanged. Tests remain unbatched.
  `tests/render/errorBoundaryInitialReset.test.ms` retains the original first case
  byte-for-byte and adds nested siblings, repeated failure/reset and cleanup lifetimes.
  Native298/2→300/0, JS61/2→63/0; actual executions used `67d94e8`/
  tree `6f3b702e74a6b3ee13f3201947c3f1f7725fae5b` plus recorded WIP, stable15.
  Not postcommit executions: `/tmp/neon-void-audit-current-initial-reset-two-{red,green}-{c,js}.{log,scope.json}`.
  Review `2768976e` found no issue with this bounded publication fix. Reference:
  `~/projects/dom-expressions/packages/dom-expressions/src/universal.js` `insert`
  retains insertion state in the effect result; `~/projects/solid/packages/solid/src/reactive/signal.ts`
  `runComputation` guards result publication. Compatible invariant, not literal port.
- Affected verification on that same67d/WIP epoch: native30/30 and JS23/23 requested-file
  invocations, Chrome4 files/57 own cases pass. Preserved checker consumer still
  exceeds25s/exit124; all55 command scopes stable,54 exit0. Exact commands/identities/
  outputs: `out/region502cd25f/{initial,discovery,results}.json` and per-command logs/scopes.
  Parent checked scopes/current source tuple and review patch SHA256
  `d9138b7aea1769b0a8f4d9af70d81194941707b8d0b6b1092e9bec1f52aa9cc0` before commit.
  Identity covers tracked diff/index, binary SHA, BUILD and dependency HEADs, not
  recursive support/dependency working-tree hashes. No full-gate, main-control,
  raw rollback, GPU/pixels/Ion/input/idle acceptance follows. Original16/118 preserved.

## Historical proof boundary — through verified525

The following observations retain their historical source/toolchain identities;
they are not current status claims. The current audit above supersedes stale blockers.

`src/components/scene3d.ms` exports Scene3D, Group, Mesh, Light and Camera3D.
`src/components/primitives.ms` supplies Void/View/Text/Pressable/TextInput.
Existing does not mean accepted: the original 16-case `tests/render/scene3d.test.ms` and
Light JSX consumer remain before runtime on the installed compiler. Measurements and
candidate differences belong to `VISION.md` "Inside a Void area".

Raw 2D slice: `src/components/scene2d.ms` exports Scene2D, Group, Rect, Sprite,
Mask, Label, TileGroup, ScaleGrid, Underline and Selection, using Void NodeRef/binders
and Neon owners. Current twenty-six-case
`tests/render/scene2d.test.ms` runs natively on read-only compiler candidate r8
(binary sha256 prefix `356b1a0fd75d`, matching source/support `f65616348`) against
Void `d255ffb`: 26 own cases / 340 including imports (`2e19934`). This proves mapping, reactive
camera/geometry/text/paint/filter, matrix-row reuse/clear, remount/disposal and
invalid-parent rejection. Parent guards went red before restoration: raw text/tags
could leak into HUD, and a foreign scene scope could capture an outer 2D parent.
Empty text markers retain Neon's existing structural protocol; visible raw text
is rejected on both createText and setText, not silently placed in the HUD.

Installed binary/support `0d83c4867` still rejects this unchanged JSX at check:
13 enum-roundtrip errors (ObjectFit, ScaleMode, BlendMode, Smooth and VoidSpace members).
VoidArea/component importers pass on installed C and JS. The original 16-case
Scene3D contract remains red on candidate with one union-signal layout error;
its original Light consumer now runs and cleans up on candidate. Candidate results
are not deployed acceptance, full gate or pixels. Earlier five-case observations
were incorrectly labelled `8506eaf03` without checking BUILD at invocation; current
measurements above supersede that unpinned attribution.

At this historical epoch the slice did not attach to an area/frame and UI under
Scene2D failed loudly. Current same-host UI mapping above supersedes that refusal;
camera-scoped presentation still remains required. Full paint wins
over a Rect/Label color prop; Label size overrides the size in a supplied TextStyle.
Refs expose real Void scenes/NodeRefs for queries, not a substitute for missing
component/frame integration. colorMatrix uses Void's setColorMatrix data API;
paint updates preserve the node-owned matrix row and reject selection of another row,
following the unchanged-row invariant in Void node.ms:499–507. Clearing a matrix uses
Void's NO_COLOR_MATRIX value, not a resource-row assignment. Scene scaleMode/designW/
designH call setScaleMode; all six Void modes, partial/omitted design values, independent
scenes and disposal are checked against sceneViewMatrix on the candidate. This is CPU
view-transform proof, not viewport pixels. Rect.boxStyle/Sprite.imageStyle use Void
payload allocation/update/disposal; tests prove payload reuse after reactive edits and
remount. Sprite width/height override tile dimensions independently; omitted axes follow
retile. All five ObjectFit values are tested through JSX and Void fitImage geometry,
not rendered image pixels. Mask.scrollX/scrollY/scrollBounds map to Void's scroll
payload; one effect applies size, bounds, then requested offsets. Tests cover clamp on
resize, clearing/replacing bounds, omitted axes, negative unbounded offsets and payload
reuse/remount/disposal. TileGroup.cells/first/count use setTiles/setRange without a new
cell reconciler: replacement/empty cells, range/defaults, caller-data isolation, payload
reuse and named negative-range cleanup are tested. Packing/edit optimization stays in
Void; current data setter takes whole cell snapshots. ScaleGrid uses the native factory
and setContent, preserving Tile and all four independent borders; optional axes follow
tile dimensions. Retile, chosen size, defaults, siblings, remount and parent errors are
CPU-tested. Nine-slice packing/alpha/pixels still require renderer acceptance. Underline/Selection
map factory geometry through setContent and reactive color; straight/wavy height and
all selection-neighbor fields, remount/cleanup/parent errors pass on candidate.
A further Paint2D-signal precedence case is retained separately in native-only
`tests/render/scene2dPaint.test.ms`: installed/r8 stop at C codegen on the setter's
spread literal (unresolved type kind48). Reduced to a standalone union-argument
spread, C red/JS0.75; parked in compiler card
`2026-10-07-spread-literal-into-nullable-return-loses-spread.md`. The full gate still
includes that file, so 26 green is not all raw2D contracts green or runtime acceptance. Plain masks allocate no scroll payload. These are state/lifecycle
checks; transformed clipping, nested scopes and input/pixels remain unproved.

The host and Ion frame are still on Void's old API. Their migration belongs to
`void-noderef-host`, not to a parallel edit here. Existing host tests describe carried
behavior, not current pixel proof against this baseline.

## 2D coverage

All node entries include local transform/pivot, paint, visibility/order, reactive props,
valid-parent checks, subtree removal and disposal. Raw render nodes use coordinates;
Yoga lays out View UI, not a scene graph by accident. The 2D vocabulary must not make the
existing 3D Group tag silently switch meaning outside Scene3D.

| ID | Void source and symbol | Candidate JSX mapping / present gap | Required Neon evidence; reference consumer |
|---|---|---|---|
| 2D-01 | `src/void2d/node.ms` Scene2D; `src/void2d/scene.ms` create/close/setScaleMode; `src/void2d/types.ms` Camera | Scene2D camera/clear/default-smooth/scaleMode/designW/designH mapped; all six scale modes CPU-tested on candidate, frame missing | Camera pan/zoom/rotation moves scene but not HUD; scale-mode/resize behavior and sibling-scene isolation; `src/test/sceneCheck.ms` |
| 2D-02 | `src/void2d/node.ms` group/addChild/addChildAt/remove/dispose | Group local/paint/order/filter/ownership plus optional size and nullable background mapped; promotion/demotion retain NodeRef/child/local, installed CPU-tested; keyed reorder/insert-before have two runtime failures pinned in scene2dOrder.test.ms (BUGS.md). View is not a raw group substitute | Nested transforms, keyed order/moves and retained NodeRef identity; `src/test/nodeCheck.ms`, `tests/integration/reparentFrame.ms` is the 3D move analogue only |
| 2D-03 | `src/void2d/node.ms` rect/setBackground/clearBackground/setBoxStyle; `src/void2d/boxStyle.ms` BoxStyle | Rect size/color/BoxStyle/core props mapped; Group background promotion/clear uses Void binders, style-slot release/reuse and full-Paint/matrix-row precedence CPU-tested installed; pixels pending. View style remains incomplete on current host | Rounded/per-edge/dashed borders, outer/inset shadow; reactive group↔paint promotion preserves children and handles, transparent paint emits nothing; `tests/integration/viewPaint.ms`, `src/test/coverageOracleCheck.ms` |
| 2D-04 | `src/void2d/node.ms` sprite/setImageStyle; `src/void2d/types.ms` Tile/TextureSource; `src/void2d/imageStyle.ms` ImageStyle | Sprite Tile/retile/independent size/ImageStyle mapped; ObjectFit/payload lifecycle CPU-tested candidate. scene2dTile adds installed+r8 atlas UV/flip/offset/premultiplied snapshot and deferred borrowed Texture replacement/sibling/remount/disposal proof: two own pass, no upload/pixels. Fresh-bounds follow-up: unchanged `msc test --no-color tests/render/scene2dTile.test.ms` passes all4 own/320 total cases on Void `e67f617`, BUILD `177f04c27`, Neon tree `ea5f1e46560f3b118a28d556ac1af058e8822aca` plus recorded integration WIP. No caller sync; scopes in `out/current177Evidence/neon-void-audit-current-void-e67-tile.{log,scope.json}`. This is CPU query/lifetime proof, not pixels | Atlas regions, flipping/offsets, fit/crop, rounded/grayscale image and replaced texture; `src/test/tileCheck.ms`, `src/test/imageStyleCheck.ms` |
| 2D-05 | `src/void2d/node.ms` anim/animFrames; `src/void2d/scene.ms` tick; `src/void2d/animation.ms` uploadAnimation/frameTiles/animation | Anim frames/frameDelays/fps/speed/looping/paused/frame bind through Void setFrames/setFrameDelays/setFps and siblings on the scene-owned clock; `tests/render/scene2dAnimation.test.ms` covers replacement, demand sleep, remount, disposal and refusals before any binder mutates (337/337 installed ae54a85be). A decoded GIF sheet needs no tag of its own: Void's `animation` is `anim(frameTiles(sheet))` plus `setFrameDelays(sheet.delays)`, which Anim's `frames`/`frameDelays` bind; the sheet texture stays the caller's. No Neon test passes a sheet. Pixels pending | Frames advance on demand while playing; stop when not playing/unmounted; replacement policy must follow actual Void API rather than silently freeze a prop; `src/test/nodeCheck.ms` |
| 2D-06 | `src/void2d/node.ms` graphics/clear; `src/void2d/graphics.ms` GraphicsOpKind and exported drawing operations | Graphics component plus typed op data in src/render/graphics.ms; installed CPU replay covers solid fills/strokes plus gradients/patterns and curve-helper points; isolated Metal submissions exercise triangle→rect and reactive gradient/pattern ranges/remount. Borrowed textured fills replay too: `tests/render/scene2dGraphicsTexture.test.ms` (Tile UV snapshot, source replacement without closing sibling owners, refusal of mixed sources/alpha before geometry changes). Pixel coverage pending | All exported shape/fill/stroke/curve operations are reachable; order is retained, reactive edits rebuild only their owned geometry and do not accumulate old operations; `src/test/graphicsCheck.ms` |
| 2D-07 | `src/void2d/graphics.ms` gradient/pattern/textured operations; `src/void2d/gradient.ms` GradientSpace | Approved typed op-data replay maps existing gradient/stops/color-space and slash/checker helpers. Installed CPU shader-record/vertex parity and ordered reactive rebuild proven in scene2dGraphicsPaint.test.ms; Metal consumer submits five reactive ranges and zero while unmounted; gradient/pattern pixels and textured shapes pending | Linear/radial gradients, Oklab alternatives, slash/checker patterns, texture changes and overlap pixels; `src/test/gradientCheck.ms`, `src/test/graphicsCheck.ms` |
| 2D-08 | `src/void2d/node.ms` mask/scrollTo/scrollBy/setScrollBounds/scrollScope | Mask size/parenting/scrollX/scrollY/nullable scrollBounds mapped; clamp/resize/defaults/lifecycle CPU-tested on candidate; installed scene2dQuery also proves scroll-shifted hit geometry and every nested rotated/resized Mask clip before a frame. Actual clipping pixels/input dispatch remain pending. ScrollView remains UI over the host | Transformed clipping and scroll affect pixels and hit tests identically; bounds clamp, input over clipped content, nested scopes; `src/test/nodeCheck.ms`, `src/test/h2dOracleCheck.ms` |
| 2D-09 | `src/void2d/node.ms` scaleGrid | ScaleGrid Tile/four borders/optional size mapped; reactive content, defaults/retile, parent/siblings/remount/disposal CPU-tested on candidate; nine-slice pixels/texture alpha pending | Resize preserves nine-slice edges and updates center without dropping texture alpha; `src/test/nodeCheck.ms`, `src/test/tileCheck.ms` |
| 2D-10 | `src/void2d/node.ms` underline/selection | Underline/Selection direct geometry/color mapped; wave/neighbor reactivity/lifecycle/parent CPU-tests pass candidate. Full-Paint signal spread test parked on compiler C codegen; text-layout/pixels pending | Wavy/straight underline and selection neighbor geometry remain expressible/reactive; `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-11 | `src/void2d/node.ms` tileGroup/setTiles/setTile/setRange | TileGroup cells/first/count mapped; replacement/empty arrays, range/defaults, payload lifecycle/caller-data isolation/parent errors CPU-tested on candidate; packed output/bounds/pixels pending | Reactive single-cell edits, reshapes, ranges, transform/order/bounds and zero cells; `src/test/tileGroupCheck.ms` |
| 2D-12 | `src/void2d/node.ms` label and text binders; `src/void2d/textLayout.ms` TextStyle/TextRun/LineOptions; `src/void2d/textDirection.ms` TextDirection; `src/void2d/textOutline.ms` (built with `-d:voidTextOutline`); `src/void2d/bidi.ms`, `src/void2d/bidiLayout.ms`, `src/void2d/shaper.ms` | Label text/size/color/TextStyle plus textRuns/shapingBreaks/truncate/hangingIndent/forceWidth mapped. Four installed native cases prove snapshot/line/query/lifecycle controls plus selectionRange+selectionColor and cursorIndex+cursorColor/cursorBlinkTime; clear/reset/defaults and all four incomplete-pair failures close owners. Blink parameters use existing Void clock in CPU tests; Two additional installed cases use a real loaded face: Label agrees with Void glyph layout/metrics/caret/UTF-16 queries, reacts to borrowed font-ID/size/spacing/wrap/text replacement. Frame scheduling/decoration/raster/pixels remain pending; default asset path is still unreadable, tested face explicitly loaded via ordinary addFont helper. Text UI projection remains a subset. Label also binds `textDirection` (setTextDirection) and `outlineWidth`+`outlineColor` as a pair (setOutline); the outline draws only in a `-d:voidTextOutline` build. Bidi resolution and shaping run inside Void's layout, under these props | Font/spacing/alignment/wrap, runs/decorations, truncate/indent/force-width, shaping breaks, selection/cursor/blink; rendered layout and queries agree; `src/test/textLayoutCheck.ms`, `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-13 | `src/void2d/font.ms` Font/FontId/resolveFont; `src/void2d/face.ms` loadFace; build-switched glyph sources `src/void2d/textSdf.ms` (`-d:voidSdfText`), `src/void2d/spriteGlyph.ms` (`-d:voidSprites`, box drawing from U+2500), `src/void2d/glyphBoxes.ms` | Borrowed FontId through TextStyle tested with real Latin+CJK faces. Descriptor replacement/interning, synthetic bold/italic, kern=0, and all five SizeAdjust values keep node identity and match Void glyph face/size/advance/query metrics: scene2dFont3 own/317 total installed+candidate pass at tree 772ee1b748b4420bd56192f422bf1f93ba624cc1; ignoring font binder gives3 failures, restored source unchanged. Font loading/resolution stay ordinary APIs; glyph raster/atlas/pixels remain pending | Supported font descriptors/fallback/synthetic styles produce expected layout; requests Void refuses remain loud (do not promise a shaper it lacks); `src/test/fontCheck.ms`, `src/test/fontOracleCheck.ms` |
| 2D-14 | `src/void2d/node.ms` setPaint/setFilter/setColorMatrix; `src/void2d/types.ms` Filter/Smooth; `src/void2d/effect.ms` color-matrix helpers | Common Paint2D contract still blocked by installed enum/spread reds. Additional scene2dEffects cases cover all four FilterKind values, full snapshot replacement/defaults/sibling isolation/remount/disposal and independent matrix-row clear/reuse; installed and candidate 2 own/316 total pass at tree 226effdc733a0f0d8a10fa1bb0650813f82e6458. Removing filter/matrix binders gives 2/1 failures; restored source unchanged. Compositing/clipping/pixels pending | Blend/alpha/color-add/key/matrix, smooth/wrap/no-overlap and blur/glow/drop-shadow preserve compositing and clipping; `src/test/effectCheck.ms`, `tests/integration/doorBlendModes.ms` |
| 2D-15 | `src/void2d/render.ms` hitTest/global queries and text geometry; `src/void2d/node.ms` localToGlobal/globalToLocal | Ref uses Void query APIs; scene2dQuery2 own/316 total pass installed+candidate at tree 3b6c39c1ac32162c7b6f0e098ea7a89232f2e8cc. Before-frame transforms/inverse queries, inherited visibility, collapsed scale/zero size, scroll and nested rotated/resized Mask hit clips tested; ignoring local binder gives2 failures, restored source unchanged. No new hit tester. Separate `scene2dTile` Sprite/nested-Rect before-frame bounds now pass without caller sync; measured scope is in 2D-04. Void `render.ms` `liveWorld` follows Heaps `h2d/Object.hx` `getBounds`/`syncPos` at `25f9a88f`, without updating the renderer's cached worlds. Owner-reported limit: a Mask ancestor rotated since the last frame still chooses scrollScope from its cached world; not covered by this consumer. Press dispatch is built: Scene2D nodes take onPress/onPressIn/onPressOut/onLongPress/onHoverIn/onHoverOut through the layer's `hit` hook (`AreaLayer.hit`, `src/render/voidAreaHandle.ms`) and run Pressable's state machine (`src/components/pressability.ms`); the Void host gives a pointer to the area's own 2D handlers first, then to layers, top paint order first (`src/platform/void/host.ms` `topLayerTaking`); pins `tests/render/scene2dEvents.test.ms`, `tests/platform/voidPointer.test.ms`. Camera/frame pixels remain incomplete | Press hits what is drawn; UTF-16 index/caret/line queries match text pixels; use Void geometry, not a second measurer/hit tester; `tests/platform/voidInput.test.ms`, `src/test/textMetricsCheck.ms` |
| 2D-16 | `src/void2d/node.ms` icon/setIcon; `src/void2d/icon.ms` IconId/registerIcon; `src/void2d/svgMask.ms` (built with `-d:voidSvg`) | Icon binds id/width/height/color through Void icon/setIcon/setSize/setColor; without `-d:voidSvg` it refuses by name at mount. `tests/render/scene2dIcon.test.ms` holds the refusal case plus two `-d:voidSvg` cases (id replacement with hold transfer; size/tint identity and area wake); the gate runs the file without the define. Registration stays Void's `registerIcon`, not a prop. Pixels pending | Replaced id releases only its own hold, tint and size keep identity, refusal names the build define; `src/test/iconCheck.ms`, `src/test/iconOffCheck.ms`, `src/test/svgMaskCheck.ms` |
| 2D-17 | `src/void2d/profiler.ms`, `src/void2d/profilerOverlay.ms`, `src/void2d/frameMarks.ms` (built with `-d:voidProfiler`) | No component by design: the frame profiler is a build define, and void2d's scene draws its overlay itself. The Ion window collects `frameStats` and prints draw, dirty-to-present and input-latency percentiles at exit (`src/platform/ion/window.ms`); the sokol canvas host does not | A `-d:voidProfiler` window run prints the percentiles; a build without it carries none of this code; `src/test/profilerCheck.ms`, `src/test/profilerOverlayCheck.ms` |

Isolated primitive device525284e/tree784bd08887aa6a35bd17047c6d9ae16b134232a5:
`msc run tests/device/scene2dPrimitives.ms`, verified installed525c8ba4f/Void d255/Metal, exit0,
12 frames across four three-frame phases. Sole live raw node is respectively ScaleGrid,
TileGroup, Underline and Selection, each submits a draw with live vertex-buffer storage.
Changes within its phase prove Grid width64→80/borders, TileGroup visible count1→2 plus
cell scale1→2, straight→wavy underline width32→48/h2→6, and Selection width/neighbor
geometry. Retained node count/old-node disposal and terminal scene close are checked.
Forcing TileGroup count1 gives exit1/TileGroup cells, production source restored exactly
and restored run0. Logs `/tmp/scene2d-primitives-device-{c094,range-red}.log`.
White tiles only: no uploaded atlas/sampler/resource-lifetime evidence. No observed
nine-slice/wavy/neighbor pixels, input/idle/Ion claim. Initial missing int32 match wildcard
was an authoring error, corrected before the successful runs; not a compiler finding.

Styling extension30e5bd8/tree4b72827581bfc401e246ce9ef3f394455b93cc8d extends that same
opt-in consumer to21 frames (seven isolated three-frame phases). Verified installed525c8ba4f
BUILD/binary SHA start/end, Void d255, Metal: exit0. Added Rect BoxStyle radius/borders
and drop→inset shadow/dashed style, Sprite ImageStyle radius/grayscale/Contain→Cover,
and Group structural→background Rect promotion on the same node (zero draws before
promotion, positive afterward). Existing primitive phases remain. Turning ImageStyle's
effect into a one-time set produces exit1/ImageStyle fit/radius/grayscale; source restored
exactly and restored run0. `/tmp/neon-verified525-{styled-primitives,styled-image-red,
styled-primitives-restored}.{scope,log,exit}` records the epoch and outputs.
Data helpers use normal Void style APIs; no original JSX enum/spread or16-case consumer
was rewritten. Initial wrong DrawKind import was corrected, not a compiler finding.
White tiles only, no observed shadow/dash/grayscale/crop pixels, atlas upload or Ion claim.
No source or normal-gate input changes; the preceding58/10+48/1 full gate remains the
same normal input set, not evidence that this opt-in program runs through the CPU gate.

## 3D coverage

Gltf first slice d57fd1f/tree1a044e83a699d412415a046fe70b129c85682efc, verified installed525c8ba4f/Void
 d255: `msc test tests/render/scene3dGltf.test.ms` own3/301 total pass. Group-only fixtures
prove stable wrapper transform/ref, imported names/nonuniform pose, authored-child order,
replacement/remount/cleanup, named bad graph/setup/scope, and old subtree preservation on
failure. New factory subtrees are built synchronously under a staging Group; existing
insertBefore keeps the imported slot ahead of authored children, remove rolls back failures,
and closeGltfAssets ends factory holds. No second scene reconciler or raw side-table writes.
Omitting staging rollback or insertBefore separately fails one assertion (299/1 with the
then-two-case test), restored final301/0. Logs `/tmp/scene3d-gltf-{missing-red,c094,
no-rollback-red,no-order-red}.log`, `/tmp/scene3dGltf-gltf-import-c094.log`.
The fixtures have no meshes/materials/textures: do not infer GPU ownership, upload or
rendering from these CPU greens. Opt-in `tests/device/scene3dGltf.ms` now preserves a
five-mesh textured GLB consumer with intended failure/replacement/remount/terminal-resource
assertions. Void `0078865` reads the shader slot metadata of the compiled backend, which
ended the Metal abort in material creation. `msc run tests/device/scene3dGltf.ms` on Neon
main 6414c090, installed ae54a85be, Void 3edff8a, Metal: exit0, `PASS Gltf device: 12 frames,
5 meshes, failure/replacement/remount, closed GPU resources`; the logged
`REACTIVITY_HALTED ... InvalidData` is the test's deliberate failed import, caught and reset.
These are frame submissions and resource counts, not pixels. Capture/input/idle and actual
Ion integration remain unverified.
Original16/Camera/Nodes importer reruns retain their7/1/1 known diagnostics; no source
land or current full gate. Native gate discovers new file; JS follows Void-only skip.

Rows below describe the code of the void-endgame integration, tree `5cc571a3639f94f6505e64989c97fb86964b21c5`, and name the tests that pin it; pass counts are not recorded here, the gate run on that tree owns them.

All scene-node entries include transforms, visibility, name, parent order/moves, error reporting
and cleanup. Renderer/preset selection is scene configuration, not app-authored GPU passes.
A resource is owned or borrowed explicitly; copying a handle is not retaining its resource.

| ID | Void source and symbol | Candidate JSX mapping / present gap | Required Neon evidence; reference consumer |
|---|---|---|---|
| 3D-01 | `src/void3d/scene.ms` Scene3D/create/closeScene/setAmbient | Scene3D owns scene/context; ambient prop calls setAmbient. Candidate CPU case proves signal/sibling/default isolation and cleanup; renderer/pixels/installed acceptance missing | Scene/context close after descendants, lighting changes affect output and only the right scene; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-02 | `src/void3d/scene.ms` addGroup/setLocal/setVisible/setName/attach/insertBefore | Group/Mesh/Light local controls plus visible/pickable/name mapped through Void binders. 3D nodes mount through a Scene3D host (`src/components/scene3d/core.ms`): Show and keyed For keep JSX order in Void and a reorder moves the same nodes; content parked by Errored is hidden and returns with the visibility it had. Extension API: `useScene3D()`, `useSceneNode()`, the bind/own helpers exported from `src/components/scene3d.ms`, and `<Node id>`, which places an app-made node and gives it back on unmount without freeing it (REFERENCE RD-10). Pin `tests/render/scene3dHost.test.ms`. Output/input remain pending | Nested reactive world poses, keyed reparent/order keep resource and pick ownership, invalid parent/cycle fails; `tests/integration/reparentFrame.ms`, `src/test/scene3dCheck.ms` |
| 3D-03 | `src/void3d/meshData.ms` MeshData; `src/void3d/draw.ms` addMeshData; `src/void3d/scene.ms` addMeshNode/setMeshOf | Mesh `geometry` (MeshData) or borrowed `mesh` (MeshId), exactly one. Equal geometries in one Scene3D share one upload, counted per user: `tests/device/scene3dMeshShared.ms` (4 Meshes, 2 uploads, swap/unmount/remount balanced). No pixel acceptance | Existing indexed/nonindexed, normals/colors/UV and geometry-helper outputs all usable; reactive geometry/handle replacement balances pins and upload failures stay loud; `src/test/meshDataCheck.ms`, `tests/integration/perspectiveFrame.ms` |
| 3D-04 | `src/void3d/material.ms` Material/MaterialKind; `src/void3d/gpu3d.ms` ProgramKey; `src/void3d/draw.ms` addMaterial/writeUniforms | Mesh `material` is a borrowed MaterialId, reactive through Void setMaterialOf: replacement keeps node identity, balances pins, refuses stale/foreign ids and retries; omitted, Mesh uses the scene's shared default material. Pin `tests/render/scene3dMaterialBindings.test.ms`. `createMaterial(props) → Accessor<MaterialId>` gives a material owned by its component: value props (saturation, alphaKill, unlit `color`, metalness/roughness, emissive, uv, dissolve) are written in place, key and texture props make a new one and release the old; pins `tests/render/scene3dMaterial.test.ms`, `tests/device/scene3dMaterial.ms`. No `<Material>` tag; a lit material has no colour uniform in Void | Existing scene program keys and uniform blocks reachable, valid feature combinations accepted and invalid ones named; material replacement/cleanup balance ownership; `src/test/programKeyCheck.ms`, `tests/integration/unlitFrame.ms` |
| 3D-05 | `src/void3d/material.ms` passFor/phaseFor/layer; `src/void3d/passList.ms` collect/sortByLayer | Value/state/kind/phase/layer travel inside the app-built Material that Mesh borrows (3D-04); no Material tag or raw slot mutation | Opaque/alpha-kill/alpha/additive/soft-add, culling/depth, transparency sort and layer ordering match Void; `tests/integration/alphaKill.ms`, `tests/integration/sceneOcclusion.ms`, `tests/integration/sortLayer.ms` |
| 3D-06 | `src/void3d/texture.ms` TextureData/TextureAlpha; `src/void3d/draw.ms` addTexture | A texture reaches a Mesh through the app-built Material it borrows (3D-04); no Texture tag. RenderTexture (3D-07) owns its target texture | Authored data/image colors, filter/wrap/alpha, UVs, replacement, context loss and ownership; `src/test/textureCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-07 | `src/void3d/draw.ms` addTargetTexture; `src/void2d/scene.ms` drawTarget; `src/gpu/target.ms` RenderTarget | `<RenderTexture width height ref>` inside Scene3D owns a RenderTarget, its target texture and a premultiplied unlit material; one Scene2D child draws into it through the area target context (`src/platform/void/areaScope.ms`), only when it changed, and a sibling Mesh shows `handle.material`. `tests/device/renderTexture.ms` covers on-demand redraw, refusal, resize, remount and released GPU resources; context loss is not exercised there. Not built: View/Text UI in the texture, and UV-to-UI input | Same owner/context chain, resize/recreation/DPI invalidation, premultiplied material pairing, disposal and target no-self-sampling checks; `tests/integration/sceneTarget.ms`, `tests/integration/targetTexture.ms`, `tests/integration/targetOwner.ms` |
| 3D-08 | `src/void3d/camera.ms` Camera3D/fromWorld/resolve; `src/void3d/scene.ms` SceneCamera/addCameraNode/cameraOf | Camera3D binds a Void camera node; local yaw/pitch, parent translation/roll/scale and active fallback CPU-tested. With no camera marked `active`, the first mounted Camera3D without an `active` prop drives the scene (`active={false}` opts out); `tests/render/scene3dCamera.test.ms`. No `target`/look-at prop: waits on `~/metascript/.inbox/void/2026-10-22-look-at-rotation.md`. Pixels pending | Perspective/orthographic, reactive selection/depth/projection, moving/rolled Group parent and supported pixel-art snap; `tests/integration/cameraRigFrame.ms`, `src/test/cameraCheck.ms` |
| 3D-09 | `src/void3d/scene.ms` LightInstance/addLightNode/setLightPower/collectLights | Light kind/value mount and reactive power/local pose exist; color/radius/priority bind through Void setLightColor/setLightRadius/setLightPriority, and a kind change keeps its named refusal because Void fixes the kind; `tests/render/scene3dLightBindings.test.ms` (305/305 installed ae54a85be). Shadow settings sit on the Light (castShadow, shadowMapSize, shadowBias, shadowOpacity; 3D-18). Pixels pending. `<DirectionalLight>` and `<PointLight>` wrap Light with only the props their kind takes (`tests/macros/pointLightShadowRejected.ms`); no `<SpotLight>`: Void has no spot kind (`~/metascript/.inbox/void/2026-10-22-spot-light.md`) | Directional/point behavior, ambient, priority/light limits, reactive power/pose, no silently frozen props; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-10 | `src/void3d/scene.ms` setPickable; `src/void3d/camera.ms` rayFromScreen; `src/void3d/pick.ms` PickHit/pickNearest | Group/Mesh/Light pickable flag mapped. Mesh, Group and `<Node id>` take onPress/onPressIn/onPressOut/onLongPress/onHoverIn/onHoverOut with a `Pointer3DEvent` (node, point, distance from the near plane, ray, uv); Scene3D takes onPressMissed; rule and pins in docs/REFERENCE.md RD-9. `<OrbitControls>` (drei surface: orbit, pan, zoom, distance/polar limits, onChange) takes drags no node claims (`src/components/scene3d/orbitControls.ms`, `tests/render/scene3dOrbit.test.ms`). Not verified on device: long press, hover, orbit. Gltf nodes take no handlers yet; one pointer only (area events carry no pointer id) | Nearest visible hit, ancestor owner, culling/transforms and authored UV/null-UV; HUD wins, texture UV reaches UI handler; `src/test/pickCheck.ms`, `tests/integration/targetTexture.ms` |
| 3D-11 | `src/void3d/animation.ms` AnimationClock/ObjectAnimation/bindTracks/syncPose | `<ObjectAnimation animation paused speed looping frame>` poses its tracks at mount and advances on the per-area clock (`src/render/voidClock.ms` `useVoidClock`), which sleeps when nothing plays; a missing target fails through Errored and recovers on reset. Pins `tests/render/scene3dAnimation.test.ms`, `tests/render/voidClock.test.ms` | Named tracks, linear/step sample, speed/pause/loop/frame control and transform-writer conflicts have explicit policy; stop at unmount; `src/test/animationCheck.ms` |
| 3D-12 | `src/void3d/animation.ms` MeshFrameAnimation/addBakedFrames/bindMeshFrames/syncMeshFrame | `<MeshFrameAnimation target meshes fps>` steps the named mesh through borrowed frames on the same area clock, unpins them on unmount and refuses a target that is not a mesh; pin `tests/render/scene3dAnimation.test.ms` | Supported baked-frame stepping, validation, binding/reparent survival, stale targets and release all offscreen frame holds; `src/test/animationCheck.ms`, `src/test/lifetimeCheck.ms` |
| 3D-13 | `src/particles/effect.ms` EffectInstance/playEffect/stopEffect/updateEffect over `src/particles/asset.ms` ParticleEffect (a `ParticleSystemAsset` per system; from code, `importUnityPrefab` or `fromHeaps`); `src/void3d/particleWriter.ms` writeParticlePoints/writeParticles; `src/void3d/draw.ms` streamMesh/writeStream | `<Particles effect material frames playing paused speed seed>` plays a Void `ParticleEffect` as one `EffectInstance` under a group node, one stream mesh node per system sized to its `maxParticles`. Local or world simulation is the asset's `main.simulationSpace`, not a prop. `playing` is Play/Stop (Stop ends emission and lets particles die); `paused` freezes the simulation and the clock; `speed` scales frame time. Without `frames` a system streams `Program.Particle` points (view billboards only); with `frames` (one AtlasTile per sheet frame) it streams `ParticleVisual`. The effect steps on the per-area clock in the Scene3D frame hook and the clock sleeps once nothing plays or lives; refused assets name Void's error. Not driven yet: one material and one frames list serve every system, Mesh render mode and trails are not drawn, camera velocity is zero. Pins `tests/render/scene3dParticles.test.ms`, `tests/device/scene3dParticles.ms` | Unity-module simulation, determinism, writers and parity; `src/test/particleEffectCheck.ms`, `src/test/particleWriterCheck.ms`, `docs/PARTICLES.md` |
| 3D-14 | `src/void3d/billboard.ms` BillboardInstance/AtlasTile/Anchor; `src/void3d/draw.ms` GpuMesh.billboards | Not built. A Neon-owned instance buffer was built and dropped (`git show 363faea5`) because Neon may not own GPU streams (see "Billboard reference follow-up" below); waits on `~/metascript/.inbox/void/2026-10-22-owned-billboard-instance-stream.md` | Texture atlas frame/anchor/color, ordered instances and resource ownership; `src/test/billboardCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-15 | `src/void3d/gltf.ms` loadGltf/loadGlb/GltfData; `src/void3d/gltfScene.ms` GltfAssets/addGltfAssets/addGltfNodes | Gltf component backed by existing factories; stable wrapper, atomic group-only graph replacement/error rollback/remount/scope proven installed CPU. Decode stays API. Gltf takes exactly one of `setup` (it uploads its own assets) or borrowed `assets` (GltfAssets, mounted through addGltfBoundNodes, left to their owner, refused once closed or from another context); `graph` gives the current imported root and a find-by-name that follows reloads; children read the mount through `gltfScope` (GltfMount). Pins `tests/render/scene3dGltfAssets.test.ms`, `tests/device/scene3dGltfShared.ms` (3 mounts, 5 meshes uploaded once). Resource-bearing device consumer `tests/device/scene3dGltf.ms` passes on Metal: 12 frames, 5 meshes, failed-import rollback, replacement, remount and closed GPU resources. Rendered pixels pending | Authored hierarchy/transforms/material/texture and errors, borrowed versus owned assets, repeated mount and cleanup; `tests/integration/gltfFrame.ms`, `src/test/gltfMaterialCheck.ms` |
| 3D-16 | `src/void3d/forwardRenderer.ms` ForwardRenderer/create/createHdr/setBloom; `src/void3d/renderer.ms` Renderer/setToneMode/setExposure; `src/void3d/toneMap.ms`, `src/void3d/bloom.ms` | Neon `Scene3D` creates its `ForwardRenderer`, runs `prepareFrame` in its layer's prepare half and `drawOverScreen` in its draw half, and closes it on cleanup (`tests/render/scene3dArea.test.ms`). Scene3D props: `hdr` (fixed at mount; checks the device renders Rgba16f), `bloom` (needs hdr), `toneMapping`, `exposure` (a multiplier, written to Void as its log). Default curve is Linear without hdr and Filmic with hdr (REFERENCE RD-11). Pins `tests/render/scene3dLook.test.ms`, `tests/device/scene3dLook.ms`; forward outline is 3D-20 | On-demand prepare→screen composition, camera/light blocks, frustum/pass lists and close/rebuild; `tests/integration/mixedFrame.ms`, `tests/integration/bothLayers.ms` |
| 3D-17 | `src/void3d/pixelArtRenderer.ms` PixelArtRenderer/PixelArtSettings/PixelArtLook; `src/void3d/palette.ms` PaletteLut; `src/void3d/blit.ms` LowResView; `src/void3d/pixelArt3d.ms` (the preset's shader functions) | Pixel-art renderer/palette/look as scene configuration; missing | Low-resolution/snap, post-pass toggles, depth source, outline/fog/saturation/palette, reactive settings and resize; compare existing renderer semantics, not a new Neon effect engine; `src/test/rendererCheck.ms`, `tests/integration/targetPresetEpoch.ms` |
| 3D-18 | `src/void3d/dirShadowMap.ms` DirShadowMap; `src/void3d/renderer.ms` attachShadow; `src/void3d/material.ms` ShadowCasting/withShadows | One directional Light per Scene3D casts through one DirShadowMap (`castShadow`, `shadowMapSize`, `shadowBias`, `shadowOpacity` on Light; refused on a point light or without castShadow). Mesh `castShadow`/`receiveShadow` pick a shadow variant of the default material and are refused beside an app material, because Void has no per-node shadow flags (`.inbox/void/2026-10-22-per-node-shadow-cast-receive.md`). Pins `tests/render/scene3dLook.test.ms`, `tests/device/scene3dLook.ms` | Dynamic caster bounds, shadows-only/off/on, supported alpha-cutout casters, bias/opacity/size, receiver pixels and resource cleanup; `src/test/dirShadowCheck.ms`, `tests/integration/dirShadow.ms` |
| 3D-19 | `src/void3d/gpu3d.ms` withUvTransform/withBackTexture/withDissolve; `src/void3d/material.ms` movingDefaults/textureOf; `src/void3d/renderer.ms` setElapsedTime | Scene3D feeds frame time through setElapsedTime and keeps asking for frames while the renderer reads time (`renderer.core.readsTime`); the moving features themselves are set on the app-built Material (3D-04). Device check `tests/device/scene3dLook.ms` (uv scroll time); no CPU pin | UV transform/scroll and back-face UV/texture, dissolve threshold/edge, shadow/color consistency, float64 frame time, schedule only while a UV scrolls, texture holds survive replacement/loss; `tests/integration/movingMaterial.ms`, `src/test/programKeyCheck.ms`, `src/test/textureCheck.ms` |
| 3D-20 | `src/void3d/forwardOutline.ms` ForwardOutlineSettings/FORWARD_OUTLINE_BLOCKS; `src/void3d/forwardRenderer.ms` setOutlineBlend/setOutlineSettings | Scene3D `outlineBlend`/`outlineSettings` bind through Void's setters, validated by component name first; `tests/render/scene3dOutline.test.ms` (4 cases: block allocation once, reactive wake/disposal, refusals, capacity refusal through Errored and reset). Pixels pending | Outline blocks allocated once, disabled scenes reserve none, edge pixels match Void's own outline consumer; `src/test/forwardOutlineCheck.ms`, `tests/integration/forwardOutline.ms` |
| 3D-21 | `src/void3d/layers.ms` layerBit/layersEnable/…; `src/void3d/scene.ms` setLayers/setRenderOrder/setCameraLayers | Node `layers`/`renderOrder` and Camera3D `layers` bind through Void; `tests/render/scene3dLayers.test.ms` (4 cases: masks do not prune children, camera mask filters meshes and lights, fallback camera mask, wake only the owning area). The `layers.ms` bit helpers are plain functions an app calls, no component | Camera mask selects what draws and lights; renderOrder reaches the retained draw list; `src/test/layersCheck.ms`, `tests/integration/sortLayer.ms` |
| 3D-22 | `src/void3d/gltfPose.ms` GltfPose/bind/samplePose; `src/void3d/gltfCurve.ms` GltfCurve; `src/void3d/animationCompose.ms` AnimationCompose | `<Clip name playing speed loop weight fadeMs time ref>` inside Gltf plays one glTF animation on the area clock; clips under one Gltf compose by weight through AnimationCompose, and the `ClipHandle` (play/pause/stop/setWeight/crossfade) writes the same state as the props. A paused or finished scene sleeps; an unknown name fails through Errored; unmount restores the rest pose; clips follow a replaced Gltf. Pin `tests/render/scene3dClip.test.ms` | Named clip plays, pauses, loops and stops at unmount; the area sleeps while nothing plays; smooth versus exclusive TRS composition follows Void; `src/test/gltfPoseCheck.ms`, `src/test/gltfAnimationCheck.ms`, `src/test/animationComposeCheck.ms` |
| 3D-23 | `src/void3d/skinPose.ms`, `src/void3d/skinGeometry.ms`, `src/void3d/skinPalette.ms`, `src/void3d/skinPartition.ms`, `src/void3d/skinInfluences.ms` | Skinned meshes are built inside Void's addGltfAssets/addGltfNodes, which Gltf calls, and the scene syncs skin poses on refresh. A Clip drives the joints of a skinned glTF and the next refresh deforms its vertices: `tests/render/scene3dSkin.test.ms`. Picking against the deformed mesh is unverified | A skinned GLB mounts, deforms when a joint moves, picks against the deformed mesh and releases its palette; `src/test/skinSceneCheck.ms`, `src/test/gltfSkinCheck.ms` |
| 3D-24 | `src/void3d/meshLod.ms` MeshLod/select/MeshLodRanges | `<Lod radius thresholds cullingRatio? forcedLevel?>` shows the child level Void's MeshLod selects by projected size (Neon gathers radius, world scale, camera distance and projection from the Scene3D frame hook; no selection math in Neon), hides all levels when Void culls (`src/components/scene3d/lod.ms`); pin `tests/render/scene3dLod.test.ms`, no device run yet. `radius` is required; mesh-level index ranges are not mapped; projection recovery and a range setter wait on `~/metascript/.inbox/void/2026-10-22-mesh-lod-consumer-inputs.md` | Projected-size selection per camera, range switches without reupload, no change to draw-list ownership; `src/test/meshLodCheck.ms`, `tests/integration/meshLod.ms` |
| 3D-25 | `src/void3d/worldLabel.ms` WorldLabel/create/setLabelText/faceCamera/closeLabel | `<Text3D text size color textStyle outlineWidth outlineColor pixelsPerUnit anchor billboard>` draws a void2d label on a quad, redrawn on change and turned to the active camera when `billboard`; outline needs `-d:voidTextOutline`. Pins `tests/render/scene3dText.test.ms` (refusals), `tests/device/text3d.ms`. Known Void issue: `.inbox/void/2026-10-22-world-label-unposed-redraw-keeps-old-scale.md`. Labels use the window font the Void area carries (`AreaHub.font`; `tests/device/text3dFont.ms`); Void still loads its default font once at label creation (`~/metascript/.inbox/void/2026-10-22-world-label-create-takes-a-font.md`) | Reactive text/outline/tint redraw only on change, faces the active camera, closes its target and mesh on unmount; `src/test/worldLabelCheck.ms`, `tests/integration/worldLabel.ms` |

## Shared acceptance

Every Metal device program under `tests/device/` runs in the macOS gate (`tests/device/run.sh`, called from `tests/run.sh`; about 78 s warm), so a device consumer named in a row below is gate evidence, not an opt-in run. Earlier paragraphs that call one opt-in predate that wiring.

| ID | Ownership/mapping | Required evidence; reference consumer |
|---|---|---|
| X-01 | `<Void>` owns the area; scene renderer(s), Scene2D and HUD participate in one Ion-driven frame. On a host without a Void area `<Void fallback>` mounts its fallback, and without one an Error names the missing `voidArea` (`tests/render/voidArea.test.ms`). A layer's prepare or draw error reaches the Errored around the layer's owner; the area keeps drawing its other layers and the failed one waits for reset (`src/render/voidAreaHandle.ms` `LayerGuard`; `tests/render/voidArea.test.ms`, `tests/render/scene3dArea.test.ms`) | Owner/context/theme cross the boundary; Scene2D/Scene3D layers draw in the content's paint order (`tests/platform/voidLayerOrder.test.ms`); no nested commit; one change gives one displayed frame; Windows scene/HUD observation; `tests/render/voidArea.test.ms`, Void `tests/integration/mixedFrame.ms`, `tests/integration/bothLayers.ms` |
| X-02 | Image/Tile/Texture source uses Void's texture owner, not a cached raw view; scene resources close in dependency order | Recreated target/image, GPU context loss, surface resize/DPI/clear invalidation and warmup use the current owners; clean scenes do not hide lost pixels; Void `tests/integration/deviceLoss.ms`, `tests/integration/deviceLoss3d.ms`, `tests/integration/viewTeardown.ms` |
| X-03 | One frame subscription for active clocks/emitters; idle scene sleeps; Neon owns input and dispatch. Built: one clock per Void area (`src/render/voidClock.ms`) drives ObjectAnimation, MeshFrameAnimation, Clip, Scene2D Anim, Scene3D scrolling-material time, Particles and `useFrame((dt, time) => void)`; the area paints only while a subscriber is awake (`tests/render/voidClock.test.ms`, `tests/render/scene2dAnimation.test.ms`, `tests/render/scene3dParticles.test.ms`). Outside a Void area useFrame runs on one shared clock with the same owner-scoped contract and Errored routing (`tests/animation/frame.test.ms`). Lod, Particles, Text3D and RenderTexture run as Scene3D frame hooks before `refresh` (`src/components/scene3d/core.ms` `onBeforeRefresh`), safe against a hook unmounting mid-frame | Anim/animation/cursor/emitter advance only while required, unmount removes callbacks, HUD-first picking and UI-in-texture dispatch work; no new Void window/event loop |

## Module disposition: no render family disappears in the gaps

Each baseline module is either covered above or remains a helper/internal implementation.
Being exported for tests or low-level drawing does not imply it needs its own JSX tag.

| Module group | Coverage or boundary |
|---|---|
| `src/void2d/node.ms`, `src/void2d/scene.ms`, `src/void2d/types.ms` | 2D-01–16; node and scene values/constructors/binders are the mapping source |
| `src/void2d/graphics.ms`, `src/void2d/gradient.ms` | 2D-06/07; helpers still need a declarative Graphics consumer |
| `src/void2d/boxStyle.ms`, `src/void2d/imageStyle.ms` | 2D-03/04; value props, not allocations exposed to the app |
| `src/void2d/font.ms`, `src/void2d/face.ms` | 2D-13; font helpers/descriptors, loaded through Void |
| `src/void2d/textLayout.ms`, `src/void2d/labelText.ms` | 2D-12/15; text values/queries plus internal shaping cache |
| `src/void2d/grapheme.ms`, `src/void2d/lineBreak.ms` | Text internals behind 2D-12/15; not grapheme/line-break components |
| `src/void2d/effect.ms`, `src/void2d/filter.ms` | 2D-14; filter/color-matrix values, rendering stays Void's |
| `src/void2d/render.ms`, `src/void2d/draw.ms`, `src/void2d/displayList.ms` | X-01/02 and query/binder integration; no raw draw-command/display-list JSX |
| `src/void2d/instance.ms`, `src/void2d/instanceLayout.ms` | Renderer packing internals; TileGroup/Graphics acceptance covers output, not a new buffer API |
| `src/void2d/glyphAtlas.ms`, `src/void2d/textGamma.ms`, `src/void2d/sdf.ms`, `src/void2d/snap.ms` | Text/shape rendering internals; pixel proof covers output; no atlas/coverage/packing tags |
| `src/void2d/layout.ms` | Yoga bridge; raw scene transforms stay separate from UI layout |
| `src/void2d/message.ms` | Diagnostic callbacks, not a render object; no JSX tag |
| `src/void2d/animation.ms` | 2D-05; sheet upload helper, the node is Anim |
| `src/void2d/textDirection.ms`, `src/void2d/textOutline.ms`, `src/void2d/bidi.ms`, `src/void2d/bidiLayout.ms`, `src/void2d/shaper.ms` | 2D-12; direction and outline are Label props, bidi and shaping are layout internals |
| `src/void2d/textSdf.ms`, `src/void2d/spriteGlyph.ms`, `src/void2d/glyphBoxes.ms` | 2D-13; build-switched glyph sources and glyph boxes, no tags |
| `src/void2d/icon.ms`, `src/void2d/svgMask.ms` | 2D-16 |
| `src/void2d/profiler.ms`, `src/void2d/profilerOverlay.ms`, `src/void2d/profilerFont.ms`, `src/void2d/frameMarks.ms` | 2D-17; build-define diagnostics |
| `src/void3d/scene.ms`, `src/void3d/camera.ms` | 3D-01/02/08/09/10; scene-node/camera ownership |
| `src/void3d/meshData.ms`, `src/void3d/draw.ms` | 3D-03/04/06/07/13/14 and X-02; geometry and resource helpers need no raw GPU tags |
| `src/void3d/material.ms`, `src/void3d/gpu3d.ms`, `src/void3d/texture.ms` | 3D-04/05/06/07; program keys/values and checked resources, not pipeline/buffer commands |
| `src/void3d/animation.ms`, `src/particles/effect.ms`, `src/void3d/billboard.ms` | 3D-11/12/13/14 and X-03 |
| `src/particles/system.ms`, `src/particles/compiled.ms`, `src/particles/curve.ms`, `src/particles/shape.ms`, `src/particles/noise.ms`, `src/particles/collision.ms`, `src/particles/lights.ms`, `src/particles/trail.ms`, `src/particles/trailRing.ms`, `src/particles/unityPrefab.ms`, `src/void3d/particleMeshWriter.ms` | 3D-13; simulation internals and the prefab importer, reached through the asset |
| `src/void3d/gltfPose.ms`, `src/void3d/gltfCurve.ms`, `src/void3d/animationCompose.ms` | 3D-22 |
| `src/void3d/skinPose.ms`, `src/void3d/skinGeometry.ms`, `src/void3d/skinPalette.ms`, `src/void3d/skinPartition.ms`, `src/void3d/skinInfluences.ms` | 3D-23; built by gltfScene, no tags |
| `src/void3d/forwardOutline.ms`, `src/void3d/layers.ms` | 3D-20, 3D-21 |
| `src/void3d/meshLod.ms`, `src/void3d/worldLabel.ms` | 3D-24, 3D-25 |
| `src/void3d/bloom.ms`, `src/void3d/toneMap.ms`, `src/void3d/post3d.ms`, `src/void3d/pixelArt3d.ms` | 3D-16/17; renderer passes and their shader functions, configured as scene props, never authored |
| `src/void3d/dirShadowMap.ms` | 3D-18; scene/material configuration owns a real shadow-map lifecycle; depth pass stays in Void |
| `src/void3d/gltf.ms`, `src/void3d/gltfDecode.ms`, `src/void3d/gltfScene.ms` | 3D-15; byte decode helper plus owned scene/assets |
| `src/void3d/forwardRenderer.ms`, `src/void3d/pixelArtRenderer.ms`, `src/void3d/palette.ms` | 3D-16/17; scene configuration with actual renderer lifetime |
| `src/void3d/renderer.ms`, `src/void3d/passList.ms`, `src/void3d/screenFx.ms`, `src/void3d/blit.ms` | 3D-05/16/17 and X-01; pass scheduling/screen meshes remain renderer internals, view mapping remains usable |
| `src/void3d/pick.ms`, `src/void3d/ray.ms`, `src/void3d/bounds.ms`, `src/void3d/frustum.ms` | 3D-10/16; math/query helpers, no parallel picking/culling implementation |
| `src/void3d/slots.ms`, `src/void3d/uniformPool.ms` | Resource implementation behind 3D-03–07/12 and X-02; ownership must be tested, allocator operations need no components |
| `src/gpu/texture.ms`, `src/gpu/target.ms`, `src/gpu/state.ms`, `src/assets/image.ms` | Cross-directory resource/value dependencies used by the rows; allocation/readback/passes/driver commands stay below JSX |
| `src/gpu/` (door, draw, pipeline), `src/shader/`, `src/math/`, `src/sokol/` | Below the binding, as WebGL sits under R3F: the device door, pipelines, the shader DSL, math and the platform drivers are what Void's scene modules call, and no Neon component addresses them |

## Boundaries and design checkpoints

- Follow the original Void names/model, not Three.js aliases. For missing 2D/resource/animation
  mappings, choose the smallest surface that expresses the row before implementing it. No opaque
  catch-all component or imperative ref callback is accepted as coverage of an otherwise missing row.
- Scene-to-area registration approved by the person 2026-10-07: use the existing area registry/
  `voidHostOf(host)` lookup, no new VoidArea/Host contract field. Coordinate lifetime with the
  host owner; null-off-Void lookup remains integration work, not current lookup behavior.
- Raw tree ordering is a Neon runtime gap (`BUGS.md`, `scene2dOrder.test.ms`). Prefer
  reusing the host owner's VoidNode tree/order/disposal mechanism over a second bridge.
  The person approved this same-host direction: UI participates in Yoga; raw nodes do not
  participate in Yoga or flowText; updates must wake a frame. Host/window ownership stays
  with void-noderef-host; implementation and the owner's land remain pending.
  On `812a97a`, an owned Label at `(42,17;30×20)` survives Yoga-only layout unchanged,
  but full `VoidHost.layout(100,100)` changes x to 0 through `flowText`. Probe used installed
  `0d83c4867`/Void `d255ffb`, newly allocated owned rows, no borrowed wrapper or host edits.
  Reuse must keep raw Label transforms out of UI text-flow as well as preserve layout domains.
  Raw-binder idle wake routing remains unmeasured; existing host onDirty wraps its own mutations.
- Geometry helpers can remain imperative **data construction**. Graphics operations mutate a
  live node, so a callback that makes the app perform those mutations is not the finished JSX
  surface. The person approved typed op-data snapshots/replay: preserve operation order,
  rebuild only owned geometry on edits, and do not accumulate prior operations. No Graphics
  coverage is claimed until implemented and exercised.
- Material/Texture parent scope, ownership and replacement must be explicit. Keep the authored
  `<Mesh><Material><Texture><View>…</View></Texture></Material></Mesh>` path; resource handles
  remain available for intentional borrowing, not as a requirement to manually mount this path.
- Camera binding now uses Void addCameraNode/setCameraOf/setActiveCamera and cameraOf/fromWorld.
  Original sixteen-case contract retains selection/lifecycle/projection inputs, evolves the old
  parent refusal into world-pose assertions and accounts for real camera nodes. Three additional
  native camera cases pass candidate; original contract still stops at the projection-signal
  compiler error. Parent-roll CPU proof is not pixel/frame acceptance.
- Light and animation props that lack a safe binder need explicit replacement/update design. A
  frozen prop is not compatibility. Animation and a reactive transform cannot silently overwrite
  each other; determine writer ownership before implementation.
- glTF coverage means the loader's existing subset, not Three.js's full importer. Its own refusals
  remain refusals; skins and animation channels are read (3D-22, 3D-23), but do not promise morphs or arbitrary files
  the baseline decoder does not support (`src/void3d/gltf.ms` loadGltf/loadGlb).
  The person approved the GltfData policy: data plus GltfMaterialSetup, a stable owned wrapper
  Group, atomic imported-subtree replacement when data changes, and terminal cleanup using
  addGltfAssets/addGltfNodes/closeGltfAssets. CPU group-only graph implementation is now
  `src/components/scene3d/gltf.ms` Gltf; resource-bearing rendering remains pending.
- R3F supports the adapter/object-linking direction, not a universal single-host requirement:
  at react-three-fiber d604b18, core/reconciler.tsx handleContainerEffects updates actual engine
  links and utils.tsx invalidateInstance requests frames. Drei bf6f4ad web/Html.tsx uses a
  separate ReactDOM root; core/RenderTexture.tsx uses a scene/portal/FBO and UV event mapping.
  Same-host raw/UI is Neon's choice because both domains use Void; scene/texture roots remain
  distinct where needed. This is reference-source evidence, not Neon runtime acceptance.
- Material shader coverage is the scene programs/feature keys Void declares; custom shader compiler,
  registration/buffer/pass authoring is outside this goal (`src/void3d/gpu3d.ms` declares/drawnIn).
- Native existing backend proof is required. Browser JS/WebGPU, new mobile hosts and macOS embed
  driver work are not implied by JSX. No platform succeeds merely because the mock host does.

## Blockers and acceptance ledger

Current installed binary/support is c0949e9f2; prior full-gate results retain their0d83 scope.
On unchanged Neon439e3e9/Void d255ffb, Effects failed7 with `NodeFlag` not assignable to
`BitSet<NodeFlag>`, even after restoring the Graphics prototype: not a Graphics regression.
The flags type did not just change: std/meta/node.ms Node.flags was already BitSet at0d83
(and migration648f5b431). Old0d83 meta/bridge.ms valueToNode accepted StaticStorage by ordinal;
e8bf07bac changed it to set membership and3316d4e01 added parser-flag validation. Neon's
singleton-enum writer was obsolete. Direct enum→BitSet assignment fails on r8 and c094;
explicit incl prints `static true sem false` on both. Nim compiler/astdef.nim TNodeFlags
likewise models a set; no language mechanism or JSX meaning changed.
The person conditionally approved the protected-file correction after this trace.
Fix eb12e2a/treeec9ea791a6c0b16d140319d19101ab9f9136c035 constructs the single-member set.
On c094/Void d255, `msc test tests/render/{emit,element,scene2dEffects}.test.ms`: own62/13/2
pass (total360/311/316); emit+element JS own62/13 pass (total123/74), macros17/apps4 pass.
Logs `/tmp/neon-{emit,element,effects}-meta-flag*-c094.log`,
`/tmp/neon-{macros,apps}-meta-flag-c094.log`, `/tmp/meta-flag-{type,set}-{c094,r8}.log`.
No source land/full-current-gate or Graphics runtime acceptance follows from this fix.

First Graphics slice9816f51/tree5dd8f62838a6983c7d2b3d928db2fe26b92366de reuses renderNode
ownership and existing Void helpers; src/render/graphics.ms is the finite operation surface.
`msc test tests/render/scene2dGraphics.test.ms` on c094/Void d255 passes2 own/316 total:
ordered geometry replay, replace/empty without accumulation, caller-point isolation,
retained identity, cleanup/remount and missing-scope refusal. Removing clear gives1 new
failure (315 pass/1 fail); restored run316/0. No GPU/pixel, texture or whole2D-06 acceptance.
Installed importer checks: Background/Effects/Font/Query/Text green; main Scene2D retains13
caller-enum errors, Paint retains unresolved kind48, Order and Tile each retain2 runtime
failures. First importer batch timed out during Font; resumed serial background batch
finished, Font317/0. Logs `/tmp/scene2d*-graphics-import-c094.log`,
`/tmp/scene2d-graphics-no-clear-red.log`, `/tmp/neon-graphics-importers-c094.log`.
The normal native gate includes this new file; JS skip follows the existing Void-only lane.
Remaining baseline operations must be added before claiming Graphics coverage.

Solid expansion3e2df0c/treeb9d89014e26099bd4e966e4eddd65265a3c8f477: installed c094/Void d255,
`msc test tests/render/scene2dGraphics.test.ms` own3/317 total pass. Each additional solid
operation matches direct Void vertex output after a reactive edit; quadBezier/cubicBezier
stay data helpers feeding points. Deliberately adding1 to stroke width gives1 failure
(316/1), restored317/0. Logs `/tmp/scene2d-graphics-solid-c094.log`,
`/tmp/scene2d-graphics-width-red.log`. No gradient/pattern/texture claim.
Isolated opt-in Metal consumer e365e5b/tree9bed14eab72c259e453ef5540fbef51951b99efc:
`msc run tests/device/scene2dGraphics.ms`, c094/Void d255, exit0/12 frames. One retained
Graphics changes triangle3 vertices/x20 to roundedRect(radius0)6 vertices/x80; prepare
rebuilds mesh, each frame submits exactly one draw with live vertex-buffer storage and
terminal scene close. Offset roundedRect x by1 gives exit1/geometry replacement, source
restored exactly and restored run0. Logs `/tmp/scene2d-graphics-device-c094.log`,
`/tmp/scene2d-graphics-device-shift-red.log`. This isolates Graphics submission, not observed
pixels or GPU-buffer terminal reclamation. No Ion/input/idle/whole-row acceptance.

Gradient/pattern expansion f253f25/tree d536ea50b09e495a0f14ac97ffb2658ec9b47e12:
installed c094/Void d255, `msc test tests/render/scene2dGraphicsPaint.test.ms` own1/315
pass. Eleven helpers match direct Void vertices and every shader-record float after each
fresh signal snapshot extends the ordered prefix; empty replay clears both arrays.
Replacing the supplied rect-stop space with Oklab fails one record assertion (314/1),
restored315/0. Logs `/tmp/graphics-paint-{missing-red,space-red,c094}.log` and
`/tmp/scene2dGraphicsPaint-graphics-paint-c094.log`. The first mutation run timed out with
no output/process left; completed rerun supplies the red, not that timeout.
Serial importer checks: Graphics317, Background316, Effects316, Font317, Query316,
Text318 pass; Order314/2, Tile316/2, mainScene2D13 caller-enum diagnostics and
Paintkind48 remain the same known reds. Logs `/tmp/*-graphics-paint-c094.log`.
`msc run tests/device/scene2dGraphics.ms` repeats the existing solid-only12-frame Metal
consumer successfully with the expanded union (`/tmp/graphics-paint-solid-device-c094.log`).
This CPU-only f253f25 measurement makes no gradient/pattern device or pixel claim; no current full gate or source land.

Subsequent device proof1455a4b/treeb16101c53def7ed8770b31a679c70b05c707b880:
`msc run tests/device/scene2dGraphicsPaint.ms`, verified installed525c8ba4f/Void d255/Metal, exit0,
12 frames. One retained Graphics has five ranges: two linear gradients (stops/Oklab),
radial Oklab, slash and checker. Frame5 changes stop/space, radius12→20, spacing7→11,
cell4→8; vertex floats504→600 and shader records match before prepare. Each visible
frame submits exactly5 draws with live vertex-buffer storage; unmount7/8 submits0,
remount9 uses current values/fresh node and terminal scene closes. Forcing rect middle
0.25 gives exit1/reactive shader records, source restored exactly to committed production
and restored run0. Logs `/tmp/scene2d-graphics-paint-device-{c094,middle-red}.log`.
This proves Metal submissions, not observed gradient/pattern pixels, idle scheduling,
input, UI composition or Ion acceptance. Common GPU buffer reclamation is not asserted.

Filter-family device3b60654/tree041fed10ad90328018666f2b3e31949775cd4553 extends
`tests/device/scene2d.ms`:12 frames, retained filtered Rect under Mask plus real-font Label
and scene camera. Blur→Glow→DropShadow→None, radius2→3/glow gain1→2 and shadow offsets
4→8 are checked; active effects submit with live targets, glyph page positive, terminal
scene closes and targets zero. Verified installed525c8ba4f start/end BUILD+binary SHA,
Void d255/Metal: exit0. Replacing filter effect with one-time set gives exit1/filter
family payload, restored source exactly/restored0. Logs/scopes
`/tmp/neon-verified525-{filter-families,filter-family-red,filter-family-restored}.*`.
The default assets/font.ttf still logs Unreadable; this consumer uses explicit readable
../void/assets/font.ttf and proves positive glyph storage/metrics, not fallback success.
No observed blur/glow/shadow pixels, input/idle/Ion claim. No normal-gate/source change.

Candidate freshness: owner ended the standing r8 hold and began rebasing the compiler
worktree onto main (peer message after this installed-only run). msc-n2s-r8 still exists
but now reads changing rebased std/runtime: do not reuse it for new comparisons. Historical
r8 measurements retain their recorded old source/support identity; await a newly named,
owner-verified candidate before any further candidate check.

Texture validation attempt (uncommitted implementation): Void `render.ms` DrawKind.Graphics
uses geometry.source/alphaPremultiplied for every Mesh range; gradient/pattern ranges use
view0/false. `types.ms` TextureSource.sameAs supplies identity. Consequently textured mesh
operations must share one source/alpha state, while independent gradient/pattern ranges
can interleave. `node.ms` clear resets source/alpha as well as geometry/records; Texture
remains caller-owned. No multi-view renderer or retained GPU-resource counter was added.
The original grouped textured match arm cannot read op.tile on installed c094 (native/JS),
reduced to two/three-tag union probes; separate-tag probe prints7/9 and equivalent TS strict
passes. This is a compiler finding, not a request to alias/cast or split shipped arms.
See `.inbox/compiler/2026-10-08-match-alternative-discriminant-loses-narrowing.md`.
`tests/render/scene2dGraphicsTexture.parked.ms` keeps intended tests outside the gate;
`out/graphicsTextureBlocked/graphics.ms` holds the failed prototype, not production truth.
Production graphics.ms restored exactly to f253f25 and Paint315/0 rerun; no texture
mapping, upload, lifetime runtime or new refusal acceptance claimed from the compile-red.

Installed c094/Void d255/source f1f0e17 remeasurement after the flag correction:
`msc test tests/render/scene3d.test.ms` retains all16 cases but exits1 before runtime with
7 actual diagnostics: six caller-enum failures (LightKind/Program/Phase) and the original
CameraProjection signal-layout refusal. Camera exits1 with VoidSpace_Scene2D (one actual
error); Nodes exits1 with LightKind_Point (one actual error). The old hundreds of flag
errors and previous NodeFlag collision do not recur here, but no original16 acceptance.
Logs `/tmp/{scene3d,scene3dCamera,scene3dNodes}-post-flag-c094.log`; existing enum/signal
cards updated, no aliases/casts/rewritten JSX. `msc run tests/device/scene2dTexture.ms`
still exits1 on captured Result.value after the original success branch, now measured on
c094 post-flag fix (`/tmp/scene2d-texture-device-post-flag-c094.log`); no upload occurred.

Compiler owners already recorded in `BUGS.md`/`VISION.md` keep the original macro/enum cases;
`2026-10-04-string-literal-union-signal-rejects-its-function-layout.md` also owns the reduced
CameraProjection signal diagnostic. Void's existing const-array migration note owns findByName's
stack writes (changed to `let` at refreshed Void `d255ffb`; consumer remeasurement pending).
A candidate is not a deployed compiler. The person approved starting `void-noderef-host`:
its owner is now migrating the host, not editing the Ion window yet. macOS embed/frame
prerequisites remain with their owners; this goal does not transfer that ownership.

Until those consumers run, no coverage row is runtime-accepted. Missing rows are Neon work,
not excuses to rename expressions, remove tests or invent capability beneath Void. On a blocked
row keep the original consumer/output and park the exact site at its existing owner; advance
only independent approved work. Any change of protected contract, new mechanism or ownership
requires the person's decision here, not a peer message.

Full installed gate on source/test tree `226effdc733a0f0d8a10fa1bb0650813f82e6458`
(`0aac7e9`; later docs-only commits leave that checked scope unchanged):
`NEON_BROWSER_PORT=8734 bash tests/run.sh` exits 1 with installed binary/support `0d83c4867`,
Void `d255ffb`, native C + Node JS + actual Chrome. Macros17 and apps4 pass; native54 pass/9 fail;
JS48 pass/1 fail; Chrome3 files pass, 30 own cases (DOM26/FlatList1/ScrollView3), checkout paths
verified, not the discarded foreign-port bundle. Against the `8a515a0` gate: four additional
native files pass; eight old native reds persist; `scene2dOrder.test.ms` adds one failed file/two
Neon runtime cases, not compiler reds. App expectation and DOM signature failures are closed.
The old reds remain platform void/voidInput/style migration, scene2d enum capture, Paint kind48,
original scene3d, camera caller-enum and nodes caller-NodeFlag. No Ion pixels/events, resource
replacement, idle/input or full-row acceptance follows from this gate; source land stays blocked.

Correction to the earlier JS49/0 report: both retained full-gate logs already contain
`native.test.ms` → `SyntaxError: Export 'YGAlignAuto' is not defined in module`. JS was48/1,
not green. The root is the existing compiler card
`2026-09-30-js-header-enum-reexport-exports-undefined-member.md`; unchanged Yoga ce52e2e,
not a new Sprite/source regression.

Device consumer at `558a056` / tree `b7a23e5abec3fa9df64c3c0ed4230eecd899c6c7`:
`msc run tests/device/scene2d.ms`, installed0d83c4867/Void d255ffb/macOS Metal, exit0.
An existing Void window/test-driver submits12 frames of JSX Scene2D/Rect, keeps one Rect,
checks signal x20→80 and one draw per frame, then closes the owned scene. Prepare dimensions
are logical framebuffer/DPI (physical384×256, DPI2), not UI layout sizes. Ignoring Neon’s
local binder produces exit1/`consumer lost its reactive Rect`; restored source diff empty,
restored run exits0. Logs `/tmp/scene2d-device-{consumer-installed,ignored-local-red}.log`.
This exercises a real device, not pixel readback: Screen Capture preflight is false and no
permission request/change or screenshot was attempted. No Ion/idle/input/window-owner
integration acceptance follows. The frame glue is deliberately in this test-driver, not a
new app requirement or shipped renderer; this standalone `.ms` is an opt-in windowed run,
not a hidden GUI launch from the CPU gate. Initial probe import/DPI errors were authoring
errors corrected before these measurements. Driver failures exit explicitly rather than
throw through Cocoa’s frame callback.

Device extension at `d77f6fe` / tree `5b4dbc5bc6a37bc245072b9e52e9ccccbe98ee6f`:
`msc run tests/device/scene2d.ms`, installed0d83/Void d255/macOS Metal exits0 for12 frames:
retained Rect x20→80, Scene2D camera x0→4, blur radius2→3, real filter target allocated,
nonzero draw submission, terminal scene close returns renderTargetsAlive to0. Ignoring
camera binder or filter binder separately gives exit1; both restored exactly and run exits0.
Logs `/tmp/scene2d-device-camera-filter-installed.log` and
`/tmp/scene2d-device-ignored-{camera,filter}-red.log`. This extends the same opt-in fixture;
no observed pixels, Ion/window-owner integration, idle or input acceptance added.

Real-font device extension at `6f3be5f` / tree
`0a4ed894035b9e71eac54965627d9d97f7ed8560`, same installed0d83/Void d255/Metal:
`msc run tests/device/scene2d.ms` exits0,12 frames, retained Label textAg→Neon/size14→18,
positive glyph layout width and live glyph page, alongside Rect/camera/blur/target cleanup.
Explicit font is `../void/assets/font.ttf`; unconfigured default assets/font.ttf still emits
Unreadable, so no default-font support claim. Existing typed font-loading helper is the same
ordinary API idiom as scene2dFont.test.ms; it does not rewrite the parked Texture Result JSX.
Ignoring TextStyle's supplied font gives exit1/`lost its reactive real-font Label`; source
restored exactly and run exits0. Logs `/tmp/scene2d-device-label-installed.log` and
`/tmp/scene2d-device-ignored-font-red.log`. Glyph/device evidence is not observed pixel proof
or Ion acceptance. Font atlas lifetime remains Void-owned, not a new Neon resource policy.

Mask device extension at `8b3342d` / tree `0322c11781d7b5c0365421783b608a973ffd26c5`:
`msc run tests/device/scene2d.ms`, same installed0d83/Void d255/Metal, exit0/12 frames.
Rect and Label now mount under one retained Mask; width96→128 and scrollX0→24 bind before
prepare, with existing camera/blur/glyph submission and terminal filter-target cleanup.
Ignoring scrollTo gives exit1/`lost its reactive Mask size or scroll`; restored source diff
empty and restored run0. Logs `/tmp/scene2d-device-mask-installed.log` and
`/tmp/scene2d-device-ignored-scroll-red.log`. No manual bounds sync, source host edit or new
clip mechanism. Submission checks do not establish pixel clipping, picking or Ion acceptance.

Texture device consumer at `29e1e4b` / tree `9455241fab0c26d7e390fa8bfe1494d342b421bd`:
`msc run tests/device/scene2dTexture.ms` rejects before emission on installed0d83 and r8:
const successful upload Result `a` loses its `.value` proof inside the JSX reader. The original
`tile(a.value, 2.0, 2.0)` remains parked; no uploaded Sprite/frame/replacement claim follows.
Plain no-Neon reduction out/resultConstCapture.ms rejects on installed C/JS and r8 C;
direct field access prints7, equivalent TypeScript passes strict checking. Added as a sibling
variant to `2026-10-07-captured-const-nullable-struct-loses-narrowing.md`, without assuming
shared root; no getter/cast substitution. This opt-in `.ms` is not a new CPU-gate red.

Prior atlas full installed gate: `NEON_BROWSER_PORT=8734 bash tests/run.sh`, commit `8d4e361`,
tree `442ff190e91c01a8b238b6811ef1d3107c3b1aaa`, installed binary/support `0d83c4867`,
Void `d255ffb`, exit1. Macros17/apps4 pass; native55 pass/10 fail; JS48 pass/1 fail;
Chrome3 files/30 own cases pass with this checkout's paths verified. Against the corrected
0aac gate: Query adds one passing native file, scene2dTile adds one failed native file/two
Void fresh-bounds cases; the eight old native reds, two Neon order cases and header-enum JS
red are unchanged. Targeted native.test JS rerun reproduces the same SyntaxError. Font's
expanded three-case descriptor suite is included. Logs are
`/tmp/neon-void-scene3d-installed-gate-atlas.{log,exit,scope}`; no source land or pixel claim.

Latest full gate: source049281c/tree370fd11cecef57859a3553c0bb42fee0286d4905,
installed binary/support525c8ba4f (BUILD2026-10-08T09:54:47+07:00), Void d255ffb,
port8734, exit1. Native58 pass/10 fail (+3 passing files versus atlas: Graphics,
GraphicsPaint, Gltf; same10 failed files); JS48/1 unchanged; macros17/apps4 and own
Chrome3/30 pass (dom26/flatList1/scrollView3, own checkout paths verified).
Native reds: platform/{void,voidInput}, style/style, render/{scene2d,scene2dOrder,
scene2dPaint,scene2dTile,scene3d,scene3dCamera,scene3dNodes}. Original expressions/cases
preserved. Runtime reds are still two raw order and two fresh-bounds cases. JS header
YGAlignAuto reexport still red. Gate artifacts retain their initial misleading filename:
`/tmp/neon-void-scene3d-c094-gate.{scope,log,exit}`; scope, not filename, is authoritative.
No source land, original16 runtime, resource/pixel/input/idle/Ion acceptance follows.

Provenance correction: d57fd1f/7aa2e5a/1455a4b/525284e reports initially assumed c094
without capturing BUILD per command; installed msc was synced again before those runs.
Do not use the old `*-c094` filenames as compiler evidence. Verified525 reruns at source
049281c capture BUILD and binary SHA at start/end: both stable for each invocation.
Gltf CPU3/301 passes; GraphicsPaint and Primitives12-frame device consumers pass,
both binder mutations exit1 and restored runs0; Gltf device and plain texture/sampler
metadata probes remain134. `/tmp/neon-verified525-*.{scope,log,exit}` holds these exact
new measurements, not a retroactive claim about uncaptured command provenance.

Billboard reference follow-up (read-only during the gate): Heaps h3d/parts/Particles.hx
386–393 allocates its packed CPU vertices, draws and disposes the transient buffer inside
the renderer; the app does not supply buffer/frame glue. Void draw.ms527–618 owns an
8-float Particle stream and refuses a second GPU write within one frame; Billboard's
15-float external stream cannot safely use it unchanged. A future owned Billboard route
must address both stride/layout and frame-coalesced uploads/context recovery; policy
needs user approval before implementation. **NEW MECHANISM — proposed, not approved:**
Void-owned15-float Billboard snapshots with renderer-side once-per-frame upload coalescing,
context-loss rebuild and terminal buffer release, reusing the existing DrawContext stream
lifetime. It can regress Particle8 layout/capacity, update-once enforcement and context
recovery; it must be implemented/proven by its Void owner, never as a Neon buffer/frame
workaround. Recommendation is to request that owned resource API, not demand app buffers
or reinterpret15 as8. No new GPU ownership mechanism shipped.

The earlier owner-prerequisite report is superseded: main743c79c's VoidNode/ScrollView,
Voidf874af6a4's macOS embed and Ion1b3d40c's layer events are consumed. Actual Neon
scene registration/frame/font/input integration remains unimplemented, not an unlanded
host-owner prerequisite. Raw-kind work belongs this arc; no unrelated ownership,
no-gate or push permission follows from peer reports. Metal submissions still cannot
close scene/HUD/texture-UI/pick/idle acceptance.

Acceptance ledger entries must name the row IDs, Neon JSX test/example, command and exit code,
source tree, installed compiler/support and consumed Void baseline, backend and actual observed
pixels/events. Compare carried reds before landing. The final audit requires evidence for every
row above and the normal full Neon gate; a handful of demos, source grep or compile-only probe
cannot close full coverage.
