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
| 2D-02 | `src/void2d/node.ms` group/addChild/addChildAt/remove/dispose | Group local/paint/order/filter/ownership plus optional size and nullable background mapped; promotion/demotion retain NodeRef/child/local, installed CPU-tested; keyed moves pending. View is not a raw group substitute | Nested transforms, keyed order/moves and retained NodeRef identity; `src/test/nodeCheck.ms`, `tests/integration/reparentFrame.ms` is the 3D move analogue only |
| 2D-03 | `src/void2d/node.ms` rect/setBackground/clearBackground/setBoxStyle; `src/void2d/boxStyle.ms` BoxStyle | Rect size/color/BoxStyle/core props mapped; Group background promotion/clear uses Void binders, style-slot release/reuse and full-Paint/matrix-row precedence CPU-tested installed; pixels pending. View style remains incomplete on current host | Rounded/per-edge/dashed borders, outer/inset shadow; reactive group↔paint promotion preserves children and handles, transparent paint emits nothing; `tests/integration/viewPaint.ms`, `src/test/coverageOracleCheck.ms` |
| 2D-04 | `src/void2d/node.ms` sprite/setImageStyle; `src/void2d/types.ms` Tile/TextureSource; `src/void2d/imageStyle.ms` ImageStyle | Sprite Tile/retile/independent size/ImageStyle mapped; all ObjectFit values and payload lifecycle CPU-tested on candidate, actual texture replacement/pixels pending | Atlas regions, flipping/offsets, fit/crop, rounded/grayscale image and replaced texture; `src/test/tileCheck.ms`, `src/test/imageStyleCheck.ms` |
| 2D-05 | `src/void2d/node.ms` anim/animFrames; `src/void2d/scene.ms` tick | Anim dynamic frames/fps blocked on missing Void binders; request .inbox/void/2026-10-08-animation-frame-and-rate-binders.md (factory/reader only, reader copy measured). Frame integration also missing; no static frozen tag | Frames advance on demand while playing; stop when not playing/unmounted; replacement policy must follow actual Void API rather than silently freeze a prop; `src/test/nodeCheck.ms` |
| 2D-06 | `src/void2d/node.ms` graphics/clear; `src/void2d/graphics.ms` GraphicsOpKind and exported drawing operations | Graphics requires approved declarative op-data/replay mechanism; current helpers mutate a live NodeRef. Proposal only, no implementation or coverage claim | All exported shape/fill/stroke/curve operations are reachable; order is retained, reactive edits rebuild only their owned geometry and do not accumulate old operations; `src/test/graphicsCheck.ms` |
| 2D-07 | `src/void2d/graphics.ms` gradient/pattern/textured operations; `src/void2d/gradient.ms` GradientSpace | Same pending op-data decision; include existing gradients/stops/color-space/dither/patterns/textured shapes, not packed GPU records | Linear/radial gradients, Oklab alternatives, slash/checker patterns, texture changes and overlap pixels; `src/test/gradientCheck.ms`, `src/test/graphicsCheck.ms` |
| 2D-08 | `src/void2d/node.ms` mask/scrollTo/scrollBy/setScrollBounds/scrollScope | Mask size/parenting/scrollX/scrollY/nullable scrollBounds mapped; clamp/resize/defaults/lifecycle CPU-tested on candidate, clipping/input/pixels pending. ScrollView remains UI over the host | Transformed clipping and scroll affect pixels and hit tests identically; bounds clamp, input over clipped content, nested scopes; `src/test/nodeCheck.ms`, `src/test/h2dOracleCheck.ms` |
| 2D-09 | `src/void2d/node.ms` scaleGrid | ScaleGrid Tile/four borders/optional size mapped; reactive content, defaults/retile, parent/siblings/remount/disposal CPU-tested on candidate; nine-slice pixels/texture alpha pending | Resize preserves nine-slice edges and updates center without dropping texture alpha; `src/test/nodeCheck.ms`, `src/test/tileCheck.ms` |
| 2D-10 | `src/void2d/node.ms` underline/selection | Underline/Selection direct geometry/color mapped; wave/neighbor reactivity/lifecycle/parent CPU-tests pass candidate. Full-Paint signal spread test parked on compiler C codegen; text-layout/pixels pending | Wavy/straight underline and selection neighbor geometry remain expressible/reactive; `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-11 | `src/void2d/node.ms` tileGroup/setTiles/setTile/setRange | TileGroup cells/first/count mapped; replacement/empty arrays, range/defaults, payload lifecycle/caller-data isolation/parent errors CPU-tested on candidate; packed output/bounds/pixels pending | Reactive single-cell edits, reshapes, ranges, transform/order/bounds and zero cells; `src/test/tileGroupCheck.ms` |
| 2D-12 | `src/void2d/node.ms` label and text binders; `src/void2d/textLayout.ms` TextStyle/TextRun/LineOptions | Label text/size/color/TextStyle plus textRuns/shapingBreaks/truncate/hangingIndent/forceWidth mapped. Four installed native cases prove snapshot/line/query/lifecycle controls plus selectionRange+selectionColor and cursorIndex+cursorColor/cursorBlinkTime; clear/reset/defaults and all four incomplete-pair failures close owners. Blink parameters use existing Void clock in CPU tests; Two additional installed cases use a real loaded face: Label agrees with Void glyph layout/metrics/caret/UTF-16 queries, reacts to borrowed font-ID/size/spacing/wrap/text replacement. Frame scheduling/decoration/raster/pixels remain pending; default asset path is still unreadable, tested face explicitly loaded via ordinary addFont helper. Text UI projection remains a subset | Font/spacing/alignment/wrap, runs/decorations, truncate/indent/force-width, shaping breaks, selection/cursor/blink; rendered layout and queries agree; `src/test/textLayoutCheck.ms`, `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-13 | `src/void2d/font.ms` Font/FontId/resolveFont; `src/void2d/face.ms` loadFace | Borrowed FontId through TextStyle tested installed with ../void/assets/font.ttf; ASCII face/metrics, reactive style and Unicode query parity proved. Loading helpers remain APIs; descriptor/fallback/synthetic-style and raster/pixel acceptance pending | Supported font descriptors/fallback/synthetic styles produce expected layout; requests Void refuses remain loud (do not promise a shaper it lacks); `src/test/fontCheck.ms`, `src/test/fontOracleCheck.ms` |
| 2D-14 | `src/void2d/node.ms` setPaint/setFilter/setColorMatrix; `src/void2d/types.ms` Filter/Smooth; `src/void2d/effect.ms` color-matrix helpers | Common Paint2D contract still blocked by installed enum/spread reds. Additional scene2dEffects cases cover all four FilterKind values, full snapshot replacement/defaults/sibling isolation/remount/disposal and independent matrix-row clear/reuse; installed and candidate 2 own/316 total pass at tree 226effdc733a0f0d8a10fa1bb0650813f82e6458. Removing filter/matrix binders gives 2/1 failures; restored source unchanged. Compositing/clipping/pixels pending | Blend/alpha/color-add/key/matrix, smooth/wrap/no-overlap and blur/glow/drop-shadow preserve compositing and clipping; `src/test/effectCheck.ms`, `tests/integration/doorBlendModes.ms` |
| 2D-15 | `src/void2d/render.ms` hitTest/global queries and text geometry; `src/void2d/node.ms` localToGlobal/globalToLocal | Ref/query access and Neon event dispatch for render nodes; host integration incomplete | Press hits what is drawn; UTF-16 index/caret/line queries match text pixels; use Void geometry, not a second measurer/hit tester; `tests/platform/voidInput.test.ms`, `src/test/textMetricsCheck.ms` |

## 3D coverage

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
| 3D-09 | `src/void3d/scene.ms` LightInstance/addLightNode/setLightPower/collectLights | Light kind/value mount and reactive power/local pose exist; other supported writes must be mapped or reject explicitly | Directional/point behavior, ambient, priority/light limits, reactive power/pose, no silently frozen props; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-10 | `src/void3d/scene.ms` setPickable; `src/void3d/camera.ms` rayFromScreen; `src/void3d/pick.ms` PickHit/pickNearest | Group/Mesh/Light pickable flag mapped and CPU-tested candidate; press/pick query/input dispatch missing (no inert onPress advertised) | Nearest visible hit, ancestor owner, culling/transforms and authored UV/null-UV; HUD wins, texture UV reaches UI handler; `src/test/pickCheck.ms`, `tests/integration/targetTexture.ms` |
| 3D-11 | `src/void3d/animation.ms` AnimationClock/ObjectAnimation/bindTracks/syncPose | ObjectAnimation driven by component-owned frame subscription; missing | Named tracks, linear/step sample, speed/pause/loop/frame control and transform-writer conflicts have explicit policy; stop at unmount; `src/test/animationCheck.ms` |
| 3D-12 | `src/void3d/animation.ms` MeshFrameAnimation/addBakedFrames/bindMeshFrames/syncMeshFrame | MeshFrameAnimation uses real resource pins and terminal close; missing | Supported baked-frame stepping, validation, binding/reparent survival, stale targets and release all offscreen frame holds; `src/test/animationCheck.ms`, `src/test/lifetimeCheck.ms` |
| 3D-13 | `src/void3d/particles.ms` ParticleEmitter/EmitterState/updateEmitter/writeInstances; `src/void3d/draw.ms` addStreamMesh/writeStream | ParticleEmitter plus streamed Mesh path; missing | Supported value/shape/state controls, deterministic seed, live instance updates/capacity, active/idle scheduling and disposal; `src/test/particlesCheck.ms`, `src/test/instanceStreamCheck.ms` |
| 3D-14 | `src/void3d/billboard.ms` BillboardInstance/AtlasTile/Anchor; `src/void3d/draw.ms` GpuMesh.billboards | Billboard instance input rendered through Mesh/material; missing | Texture atlas frame/anchor/color, ordered instances and resource ownership; `src/test/billboardCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-15 | `src/void3d/gltf.ms` loadGltf/loadGlb/GltfData; `src/void3d/gltfScene.ms` GltfAssets/addGltfAssets/addGltfNodes | GltfData scene component, helpers decode bytes; missing | Authored hierarchy/transforms/material/texture and errors, borrowed versus owned assets, repeated mount and cleanup; `tests/integration/gltfFrame.ms`, `src/test/gltfMaterialCheck.ms` |
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
  reusing the host owner's VoidNode tree/order/disposal mechanism over a second bridge;
  raw-kind/layout policy still requires the person's decision and the owner's land.
  On `812a97a`, an owned Label at `(42,17;30×20)` survives Yoga-only layout unchanged,
  but full `VoidHost.layout(100,100)` changes x to 0 through `flowText`. Probe used installed
  `0d83c4867`/Void `d255ffb`, newly allocated owned rows, no borrowed wrapper or host edits.
  Reuse must keep raw Label transforms out of UI text-flow as well as preserve layout domains.
  Raw-binder idle wake routing remains unmeasured; existing host onDirty wraps its own mutations.
- Geometry helpers can remain imperative **data construction**. Graphics operations mutate a
  live node, so a callback that makes the app perform those mutations is not the finished JSX
  surface. Decide a declarative operation input before claiming Graphics coverage.
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
- Material shader coverage is the scene programs/feature keys Void declares; custom shader compiler,
  registration/buffer/pass authoring is outside this goal (`src/void3d/gpu3d.ms` declares/drawnIn).
- Native existing backend proof is required. Browser JS/WebGPU, new mobile hosts and macOS embed
  driver work are not implied by JSX. No platform succeeds merely because the mock host does.

## Blockers and acceptance ledger

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
JS49 pass/0 fail; Chrome3 files pass, 30 own cases (DOM26/FlatList1/ScrollView3), checkout paths
verified, not the discarded foreign-port bundle. Against the `8a515a0` gate: four additional
native files pass; eight old native reds persist; `scene2dOrder.test.ms` adds one failed file/two
Neon runtime cases, not compiler reds. App expectation and DOM signature failures are closed.
The old reds remain platform void/voidInput/style migration, scene2d enum capture, Paint kind48,
original scene3d, camera caller-enum and nodes caller-NodeFlag. No Ion pixels/events, resource
replacement, idle/input or full-row acceptance follows from this gate; source land stays blocked.

Acceptance ledger entries must name the row IDs, Neon JSX test/example, command and exit code,
source tree, installed compiler/support and consumed Void baseline, backend and actual observed
pixels/events. Compare carried reds before landing. The final audit requires evidence for every
row above and the normal full Neon gate; a handful of demos, source grep or compile-only probe
cannot close full coverage.
