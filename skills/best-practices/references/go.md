## Go

- _Go_: Handle every error explicitly — assigning to `_` is almost always a latent bug. If an error genuinely can't happen, document why with a comment rather than silently discarding it.
- _Go_: Run `go vet ./...` and `golangci-lint run` before pushing. `go vet` catches common correctness issues; `golangci-lint` catches style and performance issues that reviewers would flag.
- _Go_: Pass `context.Context` as the first argument to any function that does I/O, blocks, or might cancel. Goroutines without a context are zombies waiting to leak; once you forget the context at one layer, every layer above forgets it too.
- _Go_: Wrap errors with `fmt.Errorf("doing X: %w", err)` so callers can `errors.Is` / `errors.As` up the chain. Bare `return err` loses the call-site context that operators need to debug.
- _Go_: Prefer small interfaces defined where they are used (consumer-side), not where they are implemented. The standard library's `io.Reader` works because every consumer can declare its own narrow read-only need.
- _Go_: Avoid empty interfaces (`interface{}` / `any`) at API boundaries. They turn the type system off. If you need a sum type, use a sealed interface (unexported method) or a tagged struct.
- _Go_: Run goroutines with explicit lifetime control — `errgroup.Group`, `sync.WaitGroup`, or a context-cancelled worker pool. Naked `go func() { ... }()` calls are how production hangs and panics with no stack you can find.
- _Go_: Build for the linker — keep packages small and the dependency graph shallow. Cyclic imports are forbidden by the compiler; near-cyclic imports (A → B → C → A-via-interface) signal a missing third package.
- _Go_: Use table-driven tests for any function with multiple input shapes. The pattern (`for _, tc := range cases { t.Run(tc.name, ...) }`) makes adding a case a one-line change and surfaces coverage gaps visually.
