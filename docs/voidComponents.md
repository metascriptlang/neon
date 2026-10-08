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

## Current proof boundary

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

This slice does not yet attach to an area/frame. View/Text/Pressable/TextInput under
Scene2D therefore fail loudly instead of silently mounting into the HUD; their
camera-scoped UI mapping remains required, not removed from the goal. Full paint wins
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
| 2D-04 | `src/void2d/node.ms` sprite/setImageStyle; `src/void2d/types.ms` Tile/TextureSource; `src/void2d/imageStyle.ms` ImageStyle | Sprite Tile/retile/independent size/ImageStyle mapped; ObjectFit/payload lifecycle CPU-tested candidate. scene2dTile adds installed+r8 atlas UV/flip/offset/premultiplied snapshot and deferred borrowed Texture replacement/sibling/remount/disposal proof: two own pass, no upload/pixels. Two fresh-bounds queries fail in Void, parked at .inbox/void/2026-10-08-get-bounds-stale-before-frame.md; no manual sync workaround | Atlas regions, flipping/offsets, fit/crop, rounded/grayscale image and replaced texture; `src/test/tileCheck.ms`, `src/test/imageStyleCheck.ms` |
| 2D-05 | `src/void2d/node.ms` anim/animFrames; `src/void2d/scene.ms` tick | Anim dynamic frames/fps blocked on missing Void binders; request .inbox/void/2026-10-08-animation-frame-and-rate-binders.md (factory/reader only, reader copy measured). Frame integration also missing; no static frozen tag | Frames advance on demand while playing; stop when not playing/unmounted; replacement policy must follow actual Void API rather than silently freeze a prop; `src/test/nodeCheck.ms` |
| 2D-06 | `src/void2d/node.ms` graphics/clear; `src/void2d/graphics.ms` GraphicsOpKind and exported drawing operations | Graphics component plus typed op data in src/render/graphics.ms; installed CPU replay covers solid fills/strokes plus gradients/patterns and curve-helper points; isolated Metal submissions exercise triangle→rect and reactive gradient/pattern ranges/remount. Textures parked on .inbox/compiler/2026-10-08-match-alternative-discriminant-loses-narrowing.md; pixel coverage pending | All exported shape/fill/stroke/curve operations are reachable; order is retained, reactive edits rebuild only their owned geometry and do not accumulate old operations; `src/test/graphicsCheck.ms` |
| 2D-07 | `src/void2d/graphics.ms` gradient/pattern/textured operations; `src/void2d/gradient.ms` GradientSpace | Approved typed op-data replay maps existing gradient/stops/color-space and slash/checker helpers. Installed CPU shader-record/vertex parity and ordered reactive rebuild proven in scene2dGraphicsPaint.test.ms; Metal consumer submits five reactive ranges and zero while unmounted; gradient/pattern pixels and textured shapes pending | Linear/radial gradients, Oklab alternatives, slash/checker patterns, texture changes and overlap pixels; `src/test/gradientCheck.ms`, `src/test/graphicsCheck.ms` |
| 2D-08 | `src/void2d/node.ms` mask/scrollTo/scrollBy/setScrollBounds/scrollScope | Mask size/parenting/scrollX/scrollY/nullable scrollBounds mapped; clamp/resize/defaults/lifecycle CPU-tested on candidate; installed scene2dQuery also proves scroll-shifted hit geometry and every nested rotated/resized Mask clip before a frame. Actual clipping pixels/input dispatch remain pending. ScrollView remains UI over the host | Transformed clipping and scroll affect pixels and hit tests identically; bounds clamp, input over clipped content, nested scopes; `src/test/nodeCheck.ms`, `src/test/h2dOracleCheck.ms` |
| 2D-09 | `src/void2d/node.ms` scaleGrid | ScaleGrid Tile/four borders/optional size mapped; reactive content, defaults/retile, parent/siblings/remount/disposal CPU-tested on candidate; nine-slice pixels/texture alpha pending | Resize preserves nine-slice edges and updates center without dropping texture alpha; `src/test/nodeCheck.ms`, `src/test/tileCheck.ms` |
| 2D-10 | `src/void2d/node.ms` underline/selection | Underline/Selection direct geometry/color mapped; wave/neighbor reactivity/lifecycle/parent CPU-tests pass candidate. Full-Paint signal spread test parked on compiler C codegen; text-layout/pixels pending | Wavy/straight underline and selection neighbor geometry remain expressible/reactive; `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-11 | `src/void2d/node.ms` tileGroup/setTiles/setTile/setRange | TileGroup cells/first/count mapped; replacement/empty arrays, range/defaults, payload lifecycle/caller-data isolation/parent errors CPU-tested on candidate; packed output/bounds/pixels pending | Reactive single-cell edits, reshapes, ranges, transform/order/bounds and zero cells; `src/test/tileGroupCheck.ms` |
| 2D-12 | `src/void2d/node.ms` label and text binders; `src/void2d/textLayout.ms` TextStyle/TextRun/LineOptions | Label text/size/color/TextStyle plus textRuns/shapingBreaks/truncate/hangingIndent/forceWidth mapped. Four installed native cases prove snapshot/line/query/lifecycle controls plus selectionRange+selectionColor and cursorIndex+cursorColor/cursorBlinkTime; clear/reset/defaults and all four incomplete-pair failures close owners. Blink parameters use existing Void clock in CPU tests; Two additional installed cases use a real loaded face: Label agrees with Void glyph layout/metrics/caret/UTF-16 queries, reacts to borrowed font-ID/size/spacing/wrap/text replacement. Frame scheduling/decoration/raster/pixels remain pending; default asset path is still unreadable, tested face explicitly loaded via ordinary addFont helper. Text UI projection remains a subset | Font/spacing/alignment/wrap, runs/decorations, truncate/indent/force-width, shaping breaks, selection/cursor/blink; rendered layout and queries agree; `src/test/textLayoutCheck.ms`, `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-13 | `src/void2d/font.ms` Font/FontId/resolveFont; `src/void2d/face.ms` loadFace | Borrowed FontId through TextStyle tested with real Latin+CJK faces. Descriptor replacement/interning, synthetic bold/italic, kern=0, and all five SizeAdjust values keep node identity and match Void glyph face/size/advance/query metrics: scene2dFont3 own/317 total installed+candidate pass at tree 772ee1b748b4420bd56192f422bf1f93ba624cc1; ignoring font binder gives3 failures, restored source unchanged. Font loading/resolution stay ordinary APIs; glyph raster/atlas/pixels remain pending | Supported font descriptors/fallback/synthetic styles produce expected layout; requests Void refuses remain loud (do not promise a shaper it lacks); `src/test/fontCheck.ms`, `src/test/fontOracleCheck.ms` |
| 2D-14 | `src/void2d/node.ms` setPaint/setFilter/setColorMatrix; `src/void2d/types.ms` Filter/Smooth; `src/void2d/effect.ms` color-matrix helpers | Common Paint2D contract still blocked by installed enum/spread reds. Additional scene2dEffects cases cover all four FilterKind values, full snapshot replacement/defaults/sibling isolation/remount/disposal and independent matrix-row clear/reuse; installed and candidate 2 own/316 total pass at tree 226effdc733a0f0d8a10fa1bb0650813f82e6458. Removing filter/matrix binders gives 2/1 failures; restored source unchanged. Compositing/clipping/pixels pending | Blend/alpha/color-add/key/matrix, smooth/wrap/no-overlap and blur/glow/drop-shadow preserve compositing and clipping; `src/test/effectCheck.ms`, `tests/integration/doorBlendModes.ms` |
| 2D-15 | `src/void2d/render.ms` hitTest/global queries and text geometry; `src/void2d/node.ms` localToGlobal/globalToLocal | Ref uses Void query APIs; scene2dQuery2 own/316 total pass installed+candidate at tree 3b6c39c1ac32162c7b6f0e098ea7a89232f2e8cc. Before-frame transforms/inverse queries, inherited visibility, collapsed scale/zero size, scroll and nested rotated/resized Mask hit clips tested; ignoring local binder gives2 failures, restored source unchanged. No new hit tester. Separate scene2dTile Sprite/nested-Rect getBounds cases fail installed+r8 (316 pass/2 fail): public bounds read cached worlds before frame, while live localToGlobal/hitTest work. Plain Void repro plus Heaps Object.getBounds syncPos reference in .inbox/void/2026-10-08-get-bounds-stale-before-frame.md; owner fix pending, no caller sync. Camera/frame pixels, press dispatch and host integration remain incomplete | Press hits what is drawn; UTF-16 index/caret/line queries match text pixels; use Void geometry, not a second measurer/hit tester; `tests/platform/voidInput.test.ms`, `src/test/textMetricsCheck.ms` |

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
assertions. `msc run tests/device/scene3dGltf.ms` (source d57fd1f, verified installed525c8ba4f/Void d255,
Metal) builds64 modules then aborts134 during material creation, before any frame assertion.
Plain textureSlotMask(ProgramKey.of(Program.LitTextured)) and samplerSlotMask(UnlitTextured)
programs independently abort134 in door.c260/269: hardcoded D3D11 metadata descriptor is
null in this Metal build. Owner card
`.inbox/void/2026-10-08-shader-slot-metadata-d3d-descriptor-null-on-metal.md` holds reductions,
source evidence and parked sites. No shader/fallback/Void edit, no resource or frame proof.
Logs `/tmp/scene3d-gltf-device-c094.log`, `/tmp/void-{texture,sampler}-slotmask-metal.log`.
Initial mutable-output Vec/Span authoring errors and wrong enum-probe call/key type were
corrected before the measured abort; they are not compiler findings. Capture/input/idle
and actual Ion integration remain unverified.
Original16/Camera/Nodes importer reruns retain their7/1/1 known diagnostics; no source
land or current full gate. Native gate discovers new file; JS follows Void-only skip.

All scene-node entries include transforms, visibility, name, parent order/moves, error reporting
and cleanup. Renderer/preset selection is scene configuration, not app-authored GPU passes.
A resource is owned or borrowed explicitly; copying a handle is not retaining its resource.

| ID | Void source and symbol | Candidate JSX mapping / present gap | Required Neon evidence; reference consumer |
|---|---|---|---|
| 3D-01 | `src/void3d/scene.ms` Scene3D/create/closeScene/setAmbient | Scene3D owns scene/context; ambient prop calls setAmbient. Candidate CPU case proves signal/sibling/default isolation and cleanup; renderer/pixels/installed acceptance missing | Scene/context close after descendants, lighting changes affect output and only the right scene; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-02 | `src/void3d/scene.ms` addGroup/setLocal/setVisible/setName/attach/insertBefore | Group/Mesh/Light local controls plus visible/pickable/name mapped through Void binders; two candidate CPU cases prove signals/defaults/remount/cleanup. Keyed move/order and output/input remain pending | Nested reactive world poses, keyed reparent/order keep resource and pick ownership, invalid parent/cycle fails; `tests/integration/reparentFrame.ms`, `src/test/scene3dCheck.ms` |
| 3D-03 | `src/void3d/meshData.ms` MeshData; `src/void3d/draw.ms` addMeshData; `src/void3d/scene.ms` addMeshNode/setMeshOf | Mesh geometry and borrowed MeshId path exist; no actual upload/pixel acceptance | Existing indexed/nonindexed, normals/colors/UV and geometry-helper outputs all usable; reactive geometry/handle replacement balances pins and upload failures stay loud; `src/test/meshDataCheck.ms`, `tests/integration/perspectiveFrame.ms` |
| 3D-04 | `src/void3d/material.ms` Material/MaterialKind; `src/void3d/gpu3d.ms` ProgramKey; `src/void3d/draw.ms` addMaterial/writeUniforms | Material child/borrowed path blocked on missing Void material-node replacement binder; .inbox/void/2026-10-08-mesh-material-replacement-binder.md. Existing Mesh rejects updates rather than freezing | Existing scene program keys and uniform blocks reachable, valid feature combinations accepted and invalid ones named; material replacement/cleanup balance ownership; `src/test/programKeyCheck.ms`, `tests/integration/unlitFrame.ms` |
| 3D-05 | `src/void3d/material.ms` passFor/phaseFor/layer; `src/void3d/passList.ms` collect/sortByLayer | Full Material value/state/kind/phase/layer path pending safe material replacement binder; no raw slot mutation (uniform/texture ownership checked by Void) | Opaque/alpha-kill/alpha/additive/soft-add, culling/depth, transparency sort and layer ordering match Void; `tests/integration/alphaKill.ms`, `tests/integration/sceneOcclusion.ms`, `tests/integration/sortLayer.ms` |
| 3D-06 | `src/void3d/texture.ms` TextureData/TextureAlpha; `src/void3d/draw.ms` addTexture | Texture data/image/sampler APIs traced; nested material replacement blocked on same Void binder gap. No static-only tag or borrowed raw-view workaround | Authored data/image colors, filter/wrap/alpha, UVs, replacement, context loss and ownership; `src/test/textureCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-07 | `src/void3d/draw.ms` addTargetTexture; `src/void2d/scene.ms` drawTarget; `src/gpu/target.ms` RenderTarget | Texture-owned UI target path also needs host/frame owner integration and safe material rebinding; missing, not implemented via app mounting/frame glue | Same owner/context chain, resize/recreation/DPI invalidation, premultiplied material pairing, disposal and target no-self-sampling checks; `tests/integration/sceneTarget.ms`, `tests/integration/targetTexture.ms`, `tests/integration/targetOwner.ms` |
| 3D-08 | `src/void3d/camera.ms` Camera3D/fromWorld/resolve; `src/void3d/scene.ms` SceneCamera/addCameraNode/cameraOf | Camera3D binds a Void camera node; local yaw/pitch, parent translation/roll/scale and active fallback CPU-tested on candidate. handle.camera remains local request; frame must resolve Void.cameraOf. Installed/projection/pixels pending | Perspective/orthographic, reactive selection/depth/projection, moving/rolled Group parent and supported pixel-art snap; `tests/integration/cameraRigFrame.ms`, `src/test/cameraCheck.ms` |
| 3D-09 | `src/void3d/scene.ms` LightInstance/addLightNode/setLightPower/collectLights | Light kind/value mount and reactive power/local pose exist; kind/color/radius/priority changes already reject explicitly (not frozen). Missing Void binder route recorded at .inbox/void/2026-10-08-light-parameter-binders.md; no raw payload write or remount workaround | Directional/point behavior, ambient, priority/light limits, reactive power/pose, no silently frozen props; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-10 | `src/void3d/scene.ms` setPickable; `src/void3d/camera.ms` rayFromScreen; `src/void3d/pick.ms` PickHit/pickNearest | Group/Mesh/Light pickable flag mapped and CPU-tested candidate; press/pick query/input dispatch missing (no inert onPress advertised) | Nearest visible hit, ancestor owner, culling/transforms and authored UV/null-UV; HUD wins, texture UV reaches UI handler; `src/test/pickCheck.ms`, `tests/integration/targetTexture.ms` |
| 3D-11 | `src/void3d/animation.ms` AnimationClock/ObjectAnimation/bindTracks/syncPose | ObjectAnimation driven by component-owned frame subscription; missing | Named tracks, linear/step sample, speed/pause/loop/frame control and transform-writer conflicts have explicit policy; stop at unmount; `src/test/animationCheck.ms` |
| 3D-12 | `src/void3d/animation.ms` MeshFrameAnimation/addBakedFrames/bindMeshFrames/syncMeshFrame | MeshFrameAnimation uses real resource pins and terminal close; missing | Supported baked-frame stepping, validation, binding/reparent survival, stale targets and release all offscreen frame holds; `src/test/animationCheck.ms`, `src/test/lifetimeCheck.ms` |
| 3D-13 | `src/void3d/particles.ms` ParticleEmitter/EmitterState/updateEmitter/writeInstances; `src/void3d/draw.ms` addStreamMesh/writeStream | ParticleEmitter plus streamed Mesh path; missing | Supported value/shape/state controls, deterministic seed, live instance updates/capacity, active/idle scheduling and disposal; `src/test/particlesCheck.ms`, `src/test/instanceStreamCheck.ms` |
| 3D-14 | `src/void3d/billboard.ms` BillboardInstance/AtlasTile/Anchor; `src/void3d/draw.ms` GpuMesh.billboards | Typed BillboardInstance/atlas/anchor input still missing a chosen owned resource route. Void GpuMesh.billboards uses caller-owned EXTERNAL_GENERATION buffers (draw.ms addMesh/doomBuffersOf never rebuild/destroy them); its stride15 differs from the owned Particle stream stride8. Do not reuse addStreamMesh by reinterpreting layout or require app buffer/frame glue. Trace/ownership decision remains pending; no implementation or new renderer | Texture atlas frame/anchor/color, ordered instances and resource ownership; `src/test/billboardCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-15 | `src/void3d/gltf.ms` loadGltf/loadGlb/GltfData; `src/void3d/gltfScene.ms` GltfAssets/addGltfAssets/addGltfNodes | Gltf component backed by existing factories; stable wrapper, atomic group-only graph replacement/error rollback/remount/scope proven installed CPU. Decode stays API. Resource-bearing opt-in device consumer aborts in Void shader-slot metadata on Metal; .inbox/void/2026-10-08-shader-slot-metadata-d3d-descriptor-null-on-metal.md. Resource replacement/cleanup and rendered acceptance pending | Authored hierarchy/transforms/material/texture and errors, borrowed versus owned assets, repeated mount and cleanup; `tests/integration/gltfFrame.ms`, `src/test/gltfMaterialCheck.ms` |
| 3D-16 | `src/void3d/forwardRenderer.ms` ForwardRenderer; `src/void3d/renderer.ms` Renderer | Scene renderer configuration and internal frame integration; missing | On-demand prepare→screen composition, camera/light blocks, frustum/pass lists and close/rebuild; `tests/integration/mixedFrame.ms`, `tests/integration/bothLayers.ms` |
| 3D-17 | `src/void3d/pixelArtRenderer.ms` PixelArtRenderer/PixelArtSettings/PixelArtLook; `src/void3d/palette.ms` PaletteLut; `src/void3d/blit.ms` LowResView | Pixel-art renderer/palette/look as scene configuration; missing | Low-resolution/snap, post-pass toggles, depth source, outline/fog/saturation/palette, reactive settings and resize; compare existing renderer semantics, not a new Neon effect engine; `src/test/rendererCheck.ms`, `tests/integration/targetPresetEpoch.ms` |
| 3D-18 | `src/void3d/dirShadowMap.ms` DirShadowMap; `src/void3d/renderer.ms` attachShadow; `src/void3d/material.ms` ShadowCasting/withShadows | Directional shadow configuration plus material cast/receive settings; missing | Dynamic caster bounds, shadows-only/off/on, supported alpha-cutout casters, bias/opacity/size, receiver pixels and resource cleanup; `src/test/dirShadowCheck.ms`, `tests/integration/dirShadow.ms` |
| 3D-19 | `src/void3d/gpu3d.ms` withUvTransform/withBackTexture/withDissolve; `src/void3d/material.ms` movingDefaults/textureOf; `src/void3d/renderer.ms` setElapsedTime | Material moving-feature parameters and checked back/noise texture roles, frame time supplied internally; missing | UV transform/scroll and back-face UV/texture, dissolve threshold/edge, shadow/color consistency, float64 frame time, schedule only while a UV scrolls, texture holds survive replacement/loss; `tests/integration/movingMaterial.ms`, `src/test/programKeyCheck.ms`, `src/test/textureCheck.ms` |

## Shared acceptance

| ID | Ownership/mapping | Required evidence; reference consumer |
|---|---|---|
| X-01 | `<Void>` owns the area; scene renderer(s), Scene2D and HUD participate in one Ion-driven frame | Owner/context/theme cross the boundary; 3D then scene-2D then HUD draw order is explicit; no nested commit; one change gives one displayed frame; Windows scene/HUD observation; `tests/render/voidArea.test.ms`, Void `tests/integration/mixedFrame.ms`, `tests/integration/bothLayers.ms` |
| X-02 | Image/Tile/Texture source uses Void's texture owner, not a cached raw view; scene resources close in dependency order | Recreated target/image, GPU context loss, surface resize/DPI/clear invalidation and warmup use the current owners; clean scenes do not hide lost pixels; Void `tests/integration/deviceLoss.ms`, `tests/integration/deviceLoss3d.ms`, `tests/integration/viewTeardown.ms` |
| X-03 | One frame subscription for active clocks/emitters; idle scene sleeps; Neon owns input and dispatch | Anim/animation/cursor/emitter advance only while required, unmount removes callbacks, HUD-first picking and UI-in-texture dispatch work; no new Void window/event loop |

## Module disposition: no render family disappears in the gaps

Each baseline module is either covered above or remains a helper/internal implementation.
Being exported for tests or low-level drawing does not imply it needs its own JSX tag.

| Module group | Coverage or boundary |
|---|---|
| `src/void2d/node.ms`, `src/void2d/scene.ms`, `src/void2d/types.ms` | 2D-01–15; node and scene values/constructors/binders are the mapping source |
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
| `src/void3d/scene.ms`, `src/void3d/camera.ms` | 3D-01/02/08/09/10; scene-node/camera ownership |
| `src/void3d/meshData.ms`, `src/void3d/draw.ms` | 3D-03/04/06/07/13/14 and X-02; geometry and resource helpers need no raw GPU tags |
| `src/void3d/material.ms`, `src/void3d/gpu3d.ms`, `src/void3d/texture.ms` | 3D-04/05/06/07; program keys/values and checked resources, not pipeline/buffer commands |
| `src/void3d/animation.ms`, `src/void3d/particles.ms`, `src/void3d/billboard.ms` | 3D-11/12/13/14 and X-03 |
| `src/void3d/dirShadowMap.ms` | 3D-18; scene/material configuration owns a real shadow-map lifecycle; depth pass stays in Void |
| `src/void3d/gltf.ms`, `src/void3d/gltfDecode.ms`, `src/void3d/gltfScene.ms` | 3D-15; byte decode helper plus owned scene/assets |
| `src/void3d/forwardRenderer.ms`, `src/void3d/pixelArtRenderer.ms`, `src/void3d/palette.ms` | 3D-16/17; scene configuration with actual renderer lifetime |
| `src/void3d/renderer.ms`, `src/void3d/passList.ms`, `src/void3d/screenFx.ms`, `src/void3d/blit.ms` | 3D-05/16/17 and X-01; pass scheduling/screen meshes remain renderer internals, view mapping remains usable |
| `src/void3d/pick.ms`, `src/void3d/ray.ms`, `src/void3d/bounds.ms`, `src/void3d/frustum.ms` | 3D-10/16; math/query helpers, no parallel picking/culling implementation |
| `src/void3d/slots.ms`, `src/void3d/uniformPool.ms` | Resource implementation behind 3D-03–07/12 and X-02; ownership must be tested, allocator operations need no components |
| `src/gpu/texture.ms`, `src/gpu/target.ms`, `src/gpu/state.ms`, `src/assets/image.ms` | Cross-directory resource/value dependencies used by the rows; allocation/readback/passes/driver commands stay below JSX |

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
  remain refusals; do not promise skins, imported animation channels, morphs or arbitrary files
  the baseline decoder does not support (`src/void3d/gltf.ms` loadGltf/loadGlb).
  The person approved the GltfData policy: data plus GltfMaterialSetup, a stable owned wrapper
  Group, atomic imported-subtree replacement when data changes, and terminal cleanup using
  addGltfAssets/addGltfNodes/closeGltfAssets. CPU group-only graph implementation is now
  src/components/scene3d.ms Gltf; resource-bearing rendering remains pending.
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
needs user approval before implementation. No new GPU ownership mechanism shipped.

Acceptance ledger entries must name the row IDs, Neon JSX test/example, command and exit code,
source tree, installed compiler/support and consumed Void baseline, backend and actual observed
pixels/events. Compare carried reds before landing. The final audit requires evidence for every
row above and the normal full Neon gate; a handful of demos, source grep or compile-only probe
cannot close full coverage.
