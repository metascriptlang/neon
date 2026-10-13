# Project Generator — owned by Ion

The project generator is Ion's: `ion/tooling/generator/`, documented and measured in
`ion/docs/PROJECT-GENERATOR.md`. Ion owns the project description, graph resolution, the native
emitters (Xcode for macOS and iOS, Gradle for Android, a Visual Studio solution for Windows) and
packaging. Linux's shape is written there ("Windows and Linux: why this shape"); a web target is not
part of it. A Neon app is an entry an Ion project builds; Neon is a consumer and owns no emitter
(`VISION.md` "Three pieces").

This file keeps what Neon asked of the generator when it was designed here and Ion's doc does not
carry yet. Each item is a proposal to Ion, not a promise; `ion/docs/PROJECT-GENERATOR.md` "Current
boundary" says what exists.

## Plugins that mutate a typed graph

Ion's plugins contribute bundle identifiers only. The design Neon asked for is graph mutation as
the primary extension API, so no plugin parses or rewrites `project.pbxproj`, `Info.plist`,
`AndroidManifest.xml`, Gradle or vcxproj text:

```typescript
plugin function camera(project: Project): void {
	project.apple.addEntitlement("camera");
	project.android.addPermission("android.permission.CAMERA");
	project.addNativeModule("./native/camera");
}
```

with phases `configure → resolve dependencies → mutate graph → validate → beforeEmit → emit →
afterEmit → before/afterCompile → before/afterPackage`, and these rules:

1. Hooks declare inputs, outputs, target scope and ordering.
2. Every mutation records the plugin that made it.
3. Conflicting scalar mutations fail with both owners named (Ion already does this for bundle
   identifiers).
4. Collection mutations deduplicate by semantic identity, not file position.
5. Validation runs before an emitter writes a file; a clean generation is the correctness path.
6. `afterEmit` is an escape hatch, not the integration layer.
7. A platform-namespaced extension node lets a plugin reach a native concept the graph does not
   model yet; repeated demand promotes it to a typed API.

## Native capability modules

Native code is application source and lives outside generated directories: Swift, Objective-C,
Kotlin, Java, C, C++ or assets, plus a MetaScript plugin that declares how the module joins the
graph. It is the home for OS bindings, lifecycle subscribers, custom windows or surfaces,
extensions and widgets, SDK initialization, permissions, and services Neon or Void use.

## Developer workflow

`inspect` prints the resolved graph with plugin provenance; `diff` regenerates into a clean
location and compares with the current generated project, so an experiment made in the IDE is
visible before regeneration discards it. A generated project carries a marker naming the command,
inputs and tool versions that produced it, that regeneration replaces manual edits, and how to move
an experiment into a plugin or a native module.

## Full control without owning the templates

Applications do not fork the emitters' templates. Control comes from four surfaces: shared and
per-platform configuration, typed graph mutation, native capability modules, and build and package
hooks with declared inputs and outputs. When those cannot express a real platform feature, the
graph or hook API grows; asking every app to fork a template moves generator maintenance into
every app.

## References

[Expo Continuous Native Generation](https://docs.expo.dev/workflow/continuous-native-generation/)
for disposable native projects, autolinking and config plugins;
[Tuist generated projects](https://tuist.dev/en/docs/guides/get-started/generated-xcode-project) for a
typed manifest and a validated graph that emits a normal Xcode project. Expo's ownership model and
workflow, Tuist's project-as-code graph, MetaScript as the configuration language.

## Questions still open

1. Which Expo config-plugin semantics compose, and which `mods` ordering failures are excluded by
   construction?
2. How are plugin capabilities, filesystem access, environment reads and subprocesses declared and
   audited? (Ion: manifests are trusted programs today, with no sandbox.)
3. How does `diff` tell a harmless IDE-generated change from a customization that belongs in a
   plugin?
4. Which toolchain versions are pinned in a lock file, and which stay prerequisites a doctor command
   reports?
