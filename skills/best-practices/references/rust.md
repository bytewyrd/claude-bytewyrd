## Rust

- _Rust_: Do not manage the Rust toolchain with mise — use `rust-toolchain.toml` + rustup instead. mise has a cargo PATH conflict that breaks toolchain resolution.
- _Rust_: Use `thiserror` for error types in library crates, `anyhow` in binary/application crates. Mixing them forces consumers to unwrap opaque errors.
- _Rust_: `cargo check` is significantly faster than `cargo build` for iteration — use it to validate compilation without producing artifacts.
- _Rust_: Prefer `Result<T, E>` over `panic!` for any error a caller might reasonably handle. `panic!` is for broken invariants (programmer error); `Result` is for runtime conditions (network, IO, parse).
- _Rust_: Make illegal states unrepresentable with enums — model "loading | loaded(T) | failed(E)" as one enum with three variants, not three booleans plus an `Option<T>` and an `Option<E>`.
- _Rust_: Lifetimes flow with ownership; if elision struggles, the structure is wrong, not the annotations. Reach for `Arc`/`Rc` only when shared ownership is genuinely required, not as a borrow-checker escape hatch.
- _Rust_: Use `#[derive(Debug)]` on every public type. Debug output is what shows up in error messages and logs — types without it cripple operability.
- _Rust_: For async work, prefer `tokio` and instrument long-running futures with `tracing::Instrument` so spans propagate across `.await` points. Untraced async code is invisible in production.
- _Rust_: Run `cargo clippy --workspace -- -D warnings` and `cargo fmt --all --check` in CI. Clippy catches real bugs (`needless_collect`, `redundant_clone`); fmt removes the entire class of style PR comments.
- _Rust_: Use `cargo deny` (or `cargo audit`) in CI to flag advisories, banned licenses, and duplicate dependencies. Each is a security or supply-chain signal you want to see immediately.
