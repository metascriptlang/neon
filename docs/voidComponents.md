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

Inventory baseline: Void `b27825480da4a4f34e2585bdd519dc58082854d2`, source tree
`9180aa3453ea4e1e288fb15cef45c4c6f60e0cef`. Export declarations of all 26 `.ms` modules
in each of `src/void2d/` and `src/void3d/` were inspected, with the constructor/binder,
resource and renderer paths cited below read directly. This is a source inventory, not a
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
| 2D-01 | `src/void2d/node.ms` Scene2D; `src/void2d/scene.ms` create/close/setScaleMode; `src/void2d/types.ms` Camera | Scene2D with camera, clear, design size, scale mode and default sampler values; missing | Camera pan/zoom/rotation moves scene but not HUD; scale-mode/resize behavior and sibling-scene isolation; `src/test/sceneCheck.ms` |
| 2D-02 | `src/void2d/node.ms` group/addChild/addChildAt/remove/dispose | 2D group component; missing. View is UI, not a substitute for raw group transforms | Nested transforms, keyed order/moves and retained NodeRef identity; `src/test/nodeCheck.ms`, `tests/integration/reparentFrame.ms` is the 3D move analogue only |
| 2D-03 | `src/void2d/node.ms` rect/setBackground/clearBackground/setBoxStyle; `src/void2d/boxStyle.ms` BoxStyle | Rect render component; View style projects the UI subset through its host. Both incomplete on current host | Rounded/per-edge/dashed borders, outer/inset shadow; reactive group↔paint promotion preserves children and handles, transparent paint emits nothing; `tests/integration/viewPaint.ms`, `src/test/coverageOracleCheck.ms` |
| 2D-04 | `src/void2d/node.ms` sprite/setImageStyle; `src/void2d/types.ms` Tile/TextureSource; `src/void2d/imageStyle.ms` ImageStyle | Sprite with Tile and image style; missing | Atlas regions, flipping/offsets, fit/crop, rounded/grayscale image and replaced texture; `src/test/tileCheck.ms`, `src/test/imageStyleCheck.ms` |
| 2D-05 | `src/void2d/node.ms` anim/animFrames; `src/void2d/scene.ms` tick | Anim with frames/fps and clock integration; missing | Frames advance on demand while playing; stop when not playing/unmounted; replacement policy must follow actual Void API rather than silently freeze a prop; `src/test/nodeCheck.ms` |
| 2D-06 | `src/void2d/node.ms` graphics/clear; `src/void2d/graphics.ms` GraphicsOpKind and exported drawing operations | Graphics component plus declarative geometry/operation inputs; missing, input design pending | All exported shape/fill/stroke/curve operations are reachable; order is retained, reactive edits rebuild only their owned geometry and do not accumulate old operations; `src/test/graphicsCheck.ms` |
| 2D-07 | `src/void2d/graphics.ms` gradient/pattern/textured operations; `src/void2d/gradient.ms` GradientSpace | Graphics inputs include gradients, stops, color-space/dither, patterns and textured shapes; missing | Linear/radial gradients, Oklab alternatives, slash/checker patterns, texture changes and overlap pixels; `src/test/gradientCheck.ms`, `src/test/graphicsCheck.ms` |
| 2D-08 | `src/void2d/node.ms` mask/scrollTo/scrollBy/setScrollBounds/scrollScope | Mask render component and scroll props; ScrollView remains UI over the host; missing raw mapping | Transformed clipping and scroll affect pixels and hit tests identically; bounds clamp, input over clipped content, nested scopes; `src/test/nodeCheck.ms`, `src/test/h2dOracleCheck.ms` |
| 2D-09 | `src/void2d/node.ms` scaleGrid | ScaleGrid with Tile and borders; missing | Resize preserves nine-slice edges and updates center without dropping texture alpha; `src/test/nodeCheck.ms`, `src/test/tileCheck.ms` |
| 2D-10 | `src/void2d/node.ms` underline/selection | Render decorations exposed directly or through text props, not omitted because Text also draws decorations; missing | Wavy/straight underline and selection neighbor geometry remain expressible/reactive; `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-11 | `src/void2d/node.ms` tileGroup/setTiles/setTile/setRange | TileGroup with cells and visible range; missing | Reactive single-cell edits, reshapes, ranges, transform/order/bounds and zero cells; `src/test/tileGroupCheck.ms` |
| 2D-12 | `src/void2d/node.ms` label and text binders; `src/void2d/textLayout.ms` TextStyle/TextRun/LineOptions | Label render component and Text UI projection. Existing Text surface only covers a subset | Font/spacing/alignment/wrap, runs/decorations, truncate/indent/force-width, shaping breaks, selection/cursor/blink; rendered layout and queries agree; `src/test/textLayoutCheck.ms`, `src/test/textMetricsCheck.ms`, `src/test/labelTextCheck.ms` |
| 2D-13 | `src/void2d/font.ms` Font/FontId/resolveFont; `src/void2d/face.ms` loadFace | Font values usable in JSX text props; loading helpers need no separate tag | Supported font descriptors/fallback/synthetic styles produce expected layout; requests Void refuses remain loud (do not promise a shaper it lacks); `src/test/fontCheck.ms`, `src/test/fontOracleCheck.ms` |
| 2D-14 | `src/void2d/node.ms` setPaint/setFilter/setColorMatrix; `src/void2d/types.ms` Filter/Smooth; `src/void2d/effect.ms` color-matrix helpers | Common paint/filter props on 2D components; missing outside legacy host's small style projection | Blend/alpha/color-add/key/matrix, smooth/wrap/no-overlap and blur/glow/drop-shadow preserve compositing and clipping; `src/test/effectCheck.ms`, `tests/integration/doorBlendModes.ms` |
| 2D-15 | `src/void2d/render.ms` hitTest/global queries and text geometry; `src/void2d/node.ms` localToGlobal/globalToLocal | Ref/query access and Neon event dispatch for render nodes; host integration incomplete | Press hits what is drawn; UTF-16 index/caret/line queries match text pixels; use Void geometry, not a second measurer/hit tester; `tests/platform/voidInput.test.ms`, `src/test/textMetricsCheck.ms` |

## 3D coverage

All scene-node entries include transforms, visibility, name, parent order/moves, error reporting
and cleanup. Renderer/preset selection is scene configuration, not app-authored GPU passes.
A resource is owned or borrowed explicitly; copying a handle is not retaining its resource.

| ID | Void source and symbol | Candidate JSX mapping / present gap | Required Neon evidence; reference consumer |
|---|---|---|---|
| 3D-01 | `src/void3d/scene.ms` Scene3D/create/closeScene/setAmbient | Scene3D owns scene/context and ambient values. Core exists, renderer/ambient surface missing | Scene/context close after descendants, lighting changes affect output and only the right scene; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-02 | `src/void3d/scene.ms` addGroup/setLocal/setVisible/setName/attach/insertBefore | Group exists for local transforms; name/visibility/move coverage incomplete | Nested reactive world poses, keyed reparent/order keep resource and pick ownership, invalid parent/cycle fails; `tests/integration/reparentFrame.ms`, `src/test/scene3dCheck.ms` |
| 3D-03 | `src/void3d/meshData.ms` MeshData; `src/void3d/draw.ms` addMeshData; `src/void3d/scene.ms` addMeshNode/setMeshOf | Mesh geometry and borrowed MeshId path exist; no actual upload/pixel acceptance | Existing indexed/nonindexed, normals/colors/UV and geometry-helper outputs all usable; reactive geometry/handle replacement balances pins and upload failures stay loud; `src/test/meshDataCheck.ms`, `tests/integration/perspectiveFrame.ms` |
| 3D-04 | `src/void3d/material.ms` Material/MaterialKind; `src/void3d/gpu3d.ms` ProgramKey; `src/void3d/draw.ms` addMaterial/writeUniforms | Material child of Mesh plus borrowed-material path; child/resource binding missing | Existing scene program keys and uniform blocks reachable, valid feature combinations accepted and invalid ones named; material replacement/cleanup balance ownership; `src/test/programKeyCheck.ms`, `tests/integration/unlitFrame.ms` |
| 3D-05 | `src/void3d/material.ms` passFor/phaseFor/layer; `src/void3d/passList.ms` collect/sortByLayer | Material render-state/kind/phase/layer props; missing beyond default lit material | Opaque/alpha-kill/alpha/additive/soft-add, culling/depth, transparency sort and layer ordering match Void; `tests/integration/alphaKill.ms`, `tests/integration/sceneOcclusion.ms`, `tests/integration/sortLayer.ms` |
| 3D-06 | `src/void3d/texture.ms` TextureData/TextureAlpha; `src/void3d/draw.ms` addTexture | Texture image/data/sampler binding in Material; missing | Authored data/image colors, filter/wrap/alpha, UVs, replacement, context loss and ownership; `src/test/textureCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-07 | `src/void3d/draw.ms` addTargetTexture; `src/void2d/scene.ms` drawTarget; `src/gpu/target.ms` RenderTarget | Texture containing View/Text/Pressable owns 2D scene and sampled target; missing | Same owner/context chain, resize/recreation/DPI invalidation, premultiplied material pairing, disposal and target no-self-sampling checks; `tests/integration/sceneTarget.ms`, `tests/integration/targetTexture.ms`, `tests/integration/targetOwner.ms` |
| 3D-08 | `src/void3d/camera.ms` Camera3D/fromWorld/resolve; `src/void3d/scene.ms` SceneCamera/addCameraNode/cameraOf | Camera3D selection exists; world-bound orientation/roll and camera mounting are not mapped | Perspective/orthographic, reactive selection/depth/projection, moving/rolled Group parent and supported pixel-art snap; `tests/integration/cameraRigFrame.ms`, `src/test/cameraCheck.ms` |
| 3D-09 | `src/void3d/scene.ms` LightInstance/addLightNode/setLightPower/collectLights | Light kind/value mount and reactive power/local pose exist; other supported writes must be mapped or reject explicitly | Directional/point behavior, ambient, priority/light limits, reactive power/pose, no silently frozen props; `tests/render/scene3d.test.ms`, `src/test/scene3dCheck.ms` |
| 3D-10 | `src/void3d/scene.ms` setPickable; `src/void3d/camera.ms` rayFromScreen; `src/void3d/pick.ms` PickHit/pickNearest | Group/Mesh press and pick ref/query; absent (do not advertise inert onPress) | Nearest visible hit, ancestor owner, culling/transforms and authored UV/null-UV; HUD wins, texture UV reaches UI handler; `src/test/pickCheck.ms`, `tests/integration/targetTexture.ms` |
| 3D-11 | `src/void3d/animation.ms` AnimationClock/ObjectAnimation/bindTracks/syncPose | ObjectAnimation driven by component-owned frame subscription; missing | Named tracks, linear/step sample, speed/pause/loop/frame control and transform-writer conflicts have explicit policy; stop at unmount; `src/test/animationCheck.ms` |
| 3D-12 | `src/void3d/animation.ms` MeshFrameAnimation/addBakedFrames/bindMeshFrames/syncMeshFrame | MeshFrameAnimation uses real resource pins and terminal close; missing | Supported baked-frame stepping, validation, binding/reparent survival, stale targets and release all offscreen frame holds; `src/test/animationCheck.ms`, `src/test/lifetimeCheck.ms` |
| 3D-13 | `src/void3d/particles.ms` ParticleEmitter/EmitterState/updateEmitter/writeInstances; `src/void3d/draw.ms` addStreamMesh/writeStream | ParticleEmitter plus streamed Mesh path; missing | Supported value/shape/state controls, deterministic seed, live instance updates/capacity, active/idle scheduling and disposal; `src/test/particlesCheck.ms`, `src/test/instanceStreamCheck.ms` |
| 3D-14 | `src/void3d/billboard.ms` BillboardInstance/AtlasTile/Anchor; `src/void3d/draw.ms` GpuMesh.billboards | Billboard instance input rendered through Mesh/material; missing | Texture atlas frame/anchor/color, ordered instances and resource ownership; `src/test/billboardCheck.ms`, `tests/integration/texturedFrame.ms` |
| 3D-15 | `src/void3d/gltf.ms` loadGltf/loadGlb/GltfData; `src/void3d/gltfScene.ms` GltfAssets/addGltfAssets/addGltfNodes | GltfData scene component, helpers decode bytes; missing | Authored hierarchy/transforms/material/texture and errors, borrowed versus owned assets, repeated mount and cleanup; `tests/integration/gltfFrame.ms`, `src/test/gltfMaterialCheck.ms` |
| 3D-16 | `src/void3d/forwardRenderer.ms` ForwardRenderer; `src/void3d/renderer.ms` Renderer | Scene renderer configuration and internal frame integration; missing | On-demand prepare→screen composition, camera/light blocks, frustum/pass lists and close/rebuild; `tests/integration/mixedFrame.ms`, `tests/integration/bothLayers.ms` |
| 3D-17 | `src/void3d/pixelArtRenderer.ms` PixelArtRenderer/PixelArtSettings/PixelArtLook; `src/void3d/palette.ms` PaletteLut; `src/void3d/blit.ms` LowResView | Pixel-art renderer/palette/look as scene configuration; missing | Low-resolution/snap, post-pass toggles, depth source, outline/fog/saturation/palette, reactive settings and resize; compare existing renderer semantics, not a new Neon effect engine; `src/test/rendererCheck.ms`, `tests/integration/targetPresetEpoch.ms` |

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
- Scene-to-area registration remains an open decision: recommend the existing `voidHostOf(host)`
  lookup instead of a new VoidArea/Host contract field. Coordinate its lifetime with the host owner.
- Geometry helpers can remain imperative **data construction**. Graphics operations mutate a
  live node, so a callback that makes the app perform those mutations is not the finished JSX
  surface. Decide a declarative operation input before claiming Graphics coverage.
- Material/Texture parent scope, ownership and replacement must be explicit. Keep the authored
  `<Mesh><Material><Texture><View>…</View></Texture></Material></Mesh>` path; resource handles
  remain available for intentional borrowing, not as a requirement to manually mount this path.
- Existing camera tests reject a transformed Group because the earlier Void could not represent it.
  Baseline Void can (`src/void3d/scene.ms` cameraOf; `src/void3d/camera.ms` fromWorld). Full coverage
  must map it, not preserve the old limitation indefinitely. Retain the camera test's lifecycle/
  selection coverage and evolve its old refusal in the camera-support slice, with pixel proof.
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
stack writes. A candidate is not a deployed compiler. Host/window migration and its open wake/
frame choices belong to `void-noderef-host`; this goal does not transfer that ownership.

Until those consumers run, no coverage row is runtime-accepted. Missing rows are Neon work,
not excuses to rename expressions, remove tests or invent capability beneath Void. On a blocked
row keep the original consumer/output and park the exact site at its existing owner; advance
only independent approved work. Any change of protected contract, new mechanism or ownership
requires the person's decision here, not a peer message.

Acceptance ledger entries must name the row IDs, Neon JSX test/example, command and exit code,
source tree, installed compiler/support and consumed Void baseline, backend and actual observed
pixels/events. Compare carried reds before landing. The final audit requires evidence for every
row above and the normal full Neon gate; a handful of demos, source grep or compile-only probe
cannot close full coverage.
