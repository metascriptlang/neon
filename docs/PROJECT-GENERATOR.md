# Neon Project Generator

How Neon turns one versioned MetaScript project definition into disposable,
inspectable platform projects for Xcode, Gradle, and the web.

> This is a Neon feature, not a MetaScript compiler feature. MetaScript is the
> language used to define the project graph and its hooks; Neon owns the graph,
> validation, platform emitters, native integration, and developer workflow.

---

## The decision

Native IDE projects are **generated build artifacts**, not application source.

An app commits its Neon project definition, native modules, assets, and plugins.
Neon evaluates those inputs into a typed project graph, validates the graph, and
emits a complete project for the target platform. The emitted project can be
opened, read, debugged, profiled, and built with the platform's normal tools. It
can also be deleted and reproduced.

```text
neon.project.ms + plugins + native modules + assets
                         │
                         ▼
                Neon Project Graph
                         │
                    validate
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
          Xcode       Gradle       Web
        iOS/macOS     Android    JS/Wasm/WebGPU
```

Generated output is transparent but disposable. Editing it manually is useful
for investigation, but Neon does not promise to preserve that edit across the
next generation. A lasting customization must be expressed through the project
definition, a native capability module, or a generator hook.

There is no eject workflow in the baseline design.

---

## Why this fits Neon

Neon's application value lives in the MetaScript source, reactive runtime, Host
contract, and renderers. Xcode and Gradle are packaging and integration tools;
they should not become source artifacts that every application must maintain.

Void strengthens this split. A Neon application may use the same Void2D scene
and GPU renderer on the browser, macOS, iOS, Windows, Linux, and Android. Those
targets still differ in lifecycle, input and IME, accessibility, permissions,
signing, packaging, and system services, but they do not require separate copies
of the application or rendering architecture.

The Project Generator owns that platform shell and system-integration layer. It
does not own Neon reconciliation or Void rendering; see `RENDER-LAYERS.md`.

---

## Source of truth

Committed inputs:

```text
neon.project.ms             project declaration
src/                        Neon application source
native/                     app-owned native capability modules
assets/                     icons, fonts, launch assets, packaged data
plugins/                    app-local generator plugins when needed
neon.lock                   exact Neon/tool/plugin inputs
```

Generated outputs:

```text
.neon/native/apple/         Xcode projects and workspaces
.neon/native/android/       Gradle project
.neon/native/web/           browser entry, assets, workers, manifests
.neon/build/                compiled and packaged artifacts
```

The generated directories are gitignored by default. The exact layout is not a
public API until implementation work proves what the platform toolchains need.

Reproducibility means the same declared inputs produce the same project graph
and project structure. It does not promise bit-identical signed binaries across
different Xcode, SDK, signing, or operating-system environments.

---

## User-facing model

The smallest project should be declarative:

```typescript
export default defineProject({
	name: "NeonStudio",
	bundleId: "dev.neon.studio",
	platforms: [web, macos, ios],
	plugins: [collaboration(), fileAccess()]
});
```

Common configuration belongs in the shared graph. Platform-specific values are
explicit refinements, not unrelated project files:

```typescript
export default defineProject({
	name: "NeonStudio",
	bundleId: "dev.neon.studio",
	apple: {
		team: env("APPLE_TEAM"),
		minimumIos: "18.0",
		minimumMacos: "15.0"
	},
	android: {
		minimumSdk: 28
	}
});
```

Names and syntax above are directional, not yet API commitments.

---

## Project Graph

The **Neon Project Graph** is the stable boundary between app configuration and
platform file formats. Emitters consume the graph; plugins extend or mutate it.
No ordinary plugin should parse or rewrite `project.pbxproj`, `Info.plist`,
`AndroidManifest.xml`, or Gradle text.

The shared graph needs at least:

- application identity and versioning;
- targets, products, dependencies, and build configurations;
- sources, resources, generated files, and native modules;
- capabilities, permissions, and platform services;
- compiler, linker, and packaging inputs;
- signing intent without committing credentials;
- schemes/tasks used for run, test, profile, archive, and release;
- plugin provenance for every graph mutation.

Platform domains extend it:

```text
Project
├── AppleProject
│   ├── iOS target policies
│   ├── macOS target policies
│   ├── frameworks, capabilities, extensions, entitlements
│   └── schemes, build settings, signing inputs
├── AndroidProject
│   ├── modules, variants, dependencies
│   ├── permissions, manifest entries, resources
│   └── tasks, packaging, signing inputs
└── WebProject
    ├── JS/Wasm entry and workers
    ├── WebGPU/canvas shell
    └── assets, headers, manifest, service worker
```

iOS and macOS share `AppleProject`, dependency resolution, native-module
registration, Metal/Void integration, asset handling, and most build concepts.
Their target policies remain distinct where UIKit/AppKit, lifecycle, sandbox,
entitlements, or distribution differs.

---

## Plugins and hooks

The normal extension mechanism is a typed MetaScript plugin:

```typescript
plugin function camera(project: Project): void {
	project.apple.addEntitlement("camera");
	project.android.addPermission("android.permission.CAMERA");
	project.addNativeModule("./native/camera");
}
```

The generator should expose explicit phases:

```text
configure
    ↓
resolve dependencies
    ↓
mutate typed graph
    ↓
validate
    ↓
beforeEmit
    ↓
emit native project
    ↓
afterEmit
    ↓
beforeCompile / afterCompile
    ↓
beforePackage / afterPackage
```

Rules:

1. Graph mutation is the primary API.
2. Hooks declare their inputs, outputs, target scope, and ordering constraints.
3. Every mutation records which plugin produced it.
4. Conflicting scalar mutations fail with both owners named.
5. Collection mutations deduplicate by semantic identity, not file position.
6. Validation runs before an emitter writes platform files.
7. A clean generation is the correctness path; incremental generation is only
   an optimization.
8. `afterEmit` exists as an escape hatch, not as the recommended integration
   layer.

The graph must stay open to native concepts Neon has not modeled yet. A plugin
may attach a platform-namespaced extension node or generated source file without
forking the platform template. Repeated demand should promote that extension
into a typed first-class API.

---

## Native capability modules

Native code is application source and must live outside generated directories.
A module may contain Swift, Objective-C, Kotlin, Java, C, C++, or platform assets
plus a MetaScript plugin that declares how it joins the graph.

Modules are the normal home for:

- OS API bindings;
- lifecycle subscribers;
- custom windows or surfaces;
- app extensions, widgets, and background tasks;
- platform SDK initialization;
- permissions and entitlements;
- platform services used by Neon or Void.

This separates durable native behavior from disposable Xcode/Gradle plumbing.

---

## Developer workflow

Directional CLI:

```text
neon generate ios
neon generate android
neon open ios
neon open android
neon inspect ios
neon diff ios
neon build ios
neon run macos
neon clean native
```

`generate` materializes the native project without claiming it as source.
`open` generates if necessary, then opens the normal platform IDE. `inspect`
prints the resolved graph and plugin provenance. `diff` regenerates into a clean
temporary location and compares that result with the current generated project,
making manual IDE experiments visible before they are discarded.

The generated project should contain a prominent marker explaining:

- which command produced it;
- which inputs and tool versions produced it;
- that regeneration may replace manual edits;
- how to move a successful experiment into a plugin or native module.

---

## Full control without native-template ownership

Neon owns versioned platform emitters and their internal templates. Applications
do not override those templates as their primary customization mechanism.

Full control comes from four surfaces:

1. shared and platform-specific project configuration;
2. typed graph mutation through plugins;
3. arbitrary native source and asset generation through capability modules;
4. build and package hooks with declared inputs and outputs.

If those surfaces cannot express a real platform feature, the first response is
to extend the graph or hook API. Asking every application to fork a native
template would move generator maintenance back into application repositories and
defeat the feature.

---

## Non-goals

- MetaScript compiler directives do not become an Xcode or Gradle API.
- The generator does not implement Neon reconciliation or Void rendering.
- Generated native projects are not stable hand-edited source formats.
- Manual changes made in Xcode or Android Studio are not round-tripped into
  `neon.project.ms`.
- The first version does not reproduce every Expo, Tuist, Xcode, or Gradle
  capability.
- Cloud build, credentials hosting, and deployment services are separate product
  decisions.
- A custom user-owned native shell is not part of the baseline workflow.

---

## Reference designs

Two references define the direction without dictating Neon's implementation:

- [Expo Continuous Native Generation](https://docs.expo.dev/workflow/continuous-native-generation/)
  demonstrates disposable, inspectable native projects driven by app config,
  autolinking, native modules, and config plugins.
- [Tuist Generated Projects](https://tuist.dev/en/docs/guides/get-started/generated-xcode-project)
  demonstrates a typed project manifest and validated project graph that emits
  a normal Xcode project.

Neon takes Expo's ownership model and workflow, Tuist's project-as-code graph,
and MetaScript as the configuration and extension language. It should avoid
making text patches, template forks, or undeclared hook side effects the normal
path.

---

## Delivery sequence

Research and implementation should stay incremental:

1. Prove one minimal macOS project generated from a hard-coded graph, opened and
   built by Xcode.
2. Move that graph into `neon.project.ms`; prove clean regeneration produces no
   structural diff.
3. Extract shared `AppleProject`; emit both a macOS and iOS shell from it.
4. Add one typed plugin that contributes a native source file, framework, build
   setting, and entitlement; verify provenance and conflict diagnostics.
5. Add `inspect`, clean `diff`, and generated-project markers.
6. Define the Android graph from the same shared core and emit a minimal Gradle
   project.
7. Add WebProject only for packaging concerns the existing browser/Void pipeline
   cannot already express.

Each step needs a generated-project golden, a real toolchain build, and a clean
regeneration check. Do not begin with a universal schema for every platform.

---

## Questions for the next research session

1. Which Expo config-plugin semantics compose well, and which `mods`/ordering
   failures should Neon exclude by construction?
2. Which parts of Tuist's project graph and diagnostics are essential for a
   minimal Apple emitter?
3. Should MetaScript project files execute in the normal compile-time VM or a
   narrower deterministic generator runtime?
4. How are plugin capabilities, filesystem access, environment reads, and
   subprocesses declared and audited?
5. What is the smallest Apple shell contract around Void: surface, lifecycle,
   input/IME, accessibility, clipboard, files, and deep links?
6. Which Xcode structures must be modeled directly, and which can be delegated
   to Swift Package Manager or generated configuration files?
7. What is the Android equivalent of `AppleProject` without leaking Gradle's text
   representation into the shared graph?
8. How does `neon diff` distinguish a harmless Xcode-generated change from a
   customization that must be encoded in a plugin?
9. Which toolchain versions enter `neon.lock`, and which remain environment
   prerequisites reported by `neon doctor`?
10. Where should the Project Generator live in the repository once its first
    executable slice exists?

