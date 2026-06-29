# Neon - Cross-Platform UI Framework in MetaScript

> TypeScript Syntax + Compile-Time Macros + Fine-Grained Reactivity + Native Performance

Neon is a cross-platform reactive UI framework built with MetaScript, targeting native (C backend) and web (JavaScript backend) platforms.

## Quick Start

```bash
# Build the framework
msc run build.ms build c          # Build for C backend
msc run build.ms build js         # Build for JavaScript backend

# Run example
msc run --target=raiser examples/counter.ms

# Run tests
msc run build.ms test
```

## Project Structure

```
src/
├── core/        # Reactive primitives (signal, effect, memo)
├── macros/      # Compile-time DSL transformations
├── platform/    # Platform-specific renderers
├── yoga/        # Layout engine bindings
└── starter/     # Example components

examples/        # Usage examples
tests/           # Test suite
```

## Architecture

- **Reactive Core**: Solid.js-inspired signals with automatic dependency tracking
- **Macro System**: Compile-time UI DSL transformation
- **Multi-Backend**: C (native) and JavaScript (web) from single codebase
- **Zero-Cost**: Compile-time optimizations, no runtime overhead

## Documentation

- [CLAUDE.md](./CLAUDE.md) - Development guide
- [docs/nim.md](./docs/nim.md) - Original Neon (Nim) reference
- [docs/metascript.md](./docs/metascript.md) - MetaScript capabilities

## Status

🚧 **In Development** - Phase 1: Reactive Core

See [CLAUDE.md](./CLAUDE.md) for roadmap and contribution guidelines.

## License

MIT
