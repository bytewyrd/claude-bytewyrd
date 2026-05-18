# Best Practices

## Where do entries live, and why?

This file is the **per-project accumulator**. It holds non-obvious learnings extracted from this
project's sessions (via `/best-practices-extract`). Both *generalizable* and *project-specific*
entries live here, separated by section:

- **Thematic sections** (`## Testing`, `## Architecture`, `## Documentation`, etc.) hold
  generalizable entries — they passed the three portability questions in `TRIAGE-AND-LIFT.md`
  and could theoretically ship to any project that uses the matching stack. They are *eligible*
  for promotion to the global pool.
- **`## Project-Specific`** holds entries that failed any portability question. They are
  valuable to this project (gotchas, internal conventions, project-name-specific quirks) but
  do not transfer. They are never promoted.

| File | Scope | Source | Path of entries from here |
|---|---|---|---|
| `docs/BEST_PRACTICES.md` (this file) | Per-project | Session extraction | Generalizable entries may be promoted to `~/.claude/BEST_PRACTICES.md` via `/best-practices-extract`'s per-entry prompt |
| `~/.claude/BEST_PRACTICES.md` | Cross-project | User statement OR project promotion | `/best-practices-sync` lifts vetted subset into bootstrap content (plugin-author only) |
| `skills/sync/SKILL.md` (bootstrap content, plugin-internal) | Distributed | `/best-practices-sync` from global pool | Renders here, in every new project's starter `docs/BEST_PRACTICES.md`, at `/sync` time |

Format: _Category_: Concise statement (1–2 sentences max).

Use `/best-practices-extract` at the end of a session to add new entries. Generalizable entries
can be opted into the global pool via the per-entry prompt in that same flow.

## Pitfall

- _Pitfall_: `git add .` fails at repo root in Claude Code sandbox sessions because the sandbox creates null-device character files (`.bash_profile`, `.bashrc`, `.gitconfig`, etc.) that aren't real files. Use explicit paths: `git add src/ docs/ CLAUDE.md .claude/` etc.
- _Pitfall_: Bash `mkdir`/`cp` may fail in Claude Code sandbox sessions due to write restrictions. The Write file tool often bypasses those restrictions — prefer it over Bash for creating files in restricted directories.

## Workflow

- _Workflow_: Claude Code agents should never start long-running processes (dev servers, test watchers, build watchers) — always ask the user to run these in a separate terminal.
- _Workflow_: Run `git fetch --all` at the start of every session before creating branches or worktrees to avoid working from stale refs.
- _Workflow_: Before pushing any change, run the full quality gate locally (fmt check, linter, tests) — not just the step you touched. The pre-push hook enforces this, but run it yourself first so failures are found before the hook fires.
- _Workflow_: Keep PRs small and focused on a single concern. Large PRs are harder to review, harder to revert, and hide bugs in unrelated diffs.
- _Workflow_: Commit messages should describe the WHY, not the WHAT. The diff already shows what changed; the message should explain why the change was necessary.
- _Workflow_: README.md is a user-facing landing page — not a developer guide. It answers: what is this, why should I care, how does it work, how do I get started. Build commands, test steps, and setup instructions belong in CONTRIBUTING.md.

## Claude Code

- _Claude Code_: Gather actual error output and logs before diagnosing a problem — don't assume a cause from symptoms. State hypotheses explicitly ("I think X might be causing Y") rather than compressing them into stated facts.
- _Claude Code_: Verify subagent outputs before reporting success. An agent's summary describes what it intended to do, not necessarily what it did — check the actual file changes or command output.
- _Claude Code_: Prefer specialized agents (rust-engineer, python-pro, frontend-developer, etc.) for language- and domain-specific work. They have narrower prompts and better defaults for their domain.

## Code Design

- _Code Design_: A module named `utils`, `helpers`, or `misc` is a textbook example of coincidental cohesion — the weakest type on Constantine's scale, where members are grouped by convenience rather than shared purpose. Every function that ends up there belongs in a domain-aligned module; if you cannot name the module after a concept, the abstraction is missing, not the catch-all.
- _Code Design_: Apply "Parse, Don't Validate" (Alexis King, 2019): convert raw input into a typed value that structurally encodes its validity constraints, so downstream code cannot use unvalidated data. When enrichment requires external context, make it a separate `resolve(context)` step — keeping parsing pure and dependency-free, and making the enrichment dependencies explicit at the call site.

## Code Style

- _Code Style_: Optimize code for humans first. Group logically related statements with a blank line between distinct phases (setup, execution, output). A blank line costs nothing and saves the next reader from mentally parsing what belongs together.

## Architecture

- _Architecture_: Use structured tracing from day one (`tracing` in Rust, OpenTelemetry-compatible libraries elsewhere) — adding spans retroactively is far more painful than instrumenting as you write. Initialize binaries with a runtime env-filter; put spans on functions that perform I/O or cross subsystem boundaries (`#[instrument]` in Rust, `trace.startActiveSpan` in JS/TS); and never use `println!` / `console.log` for diagnostics in production code.
- _Architecture_: Design at the boundary level first — define what crosses a boundary (data formats, error contracts, interfaces) before writing implementation. Changing a boundary is expensive; changing internals is cheap.
- _Architecture_: Separate domain logic from infrastructure from day one. Business rules must not import database drivers, HTTP clients, or framework types. This boundary makes unit testing cheap and technology migrations possible.
- _Architecture_: Single Responsibility — a module/struct/class has one reason to change. Two reasons (e.g., "user persistence" and "user authorization") means two collaborators should split the work, not one monolith.
- _Architecture_: Open/Closed — extend behavior through new types or strategies, not by editing branches in the existing path. Adding a new payment provider should add a file, not add a `case` to a switch in five files.
- _Architecture_: Liskov Substitution — a subtype must accept everything its supertype accepts and produce nothing its supertype wouldn't. Violating this turns "polymorphism" into "if statement spread across types."
- _Architecture_: Interface Segregation — clients depend on the methods they actually use, not a kitchen-sink interface. A 20-method interface that callers use 3 of is 17 methods of false coupling.
- _Architecture_: Dependency Inversion — high-level policy depends on abstractions; low-level mechanism implements them. The abstraction lives with the policy (it captures what the policy needs), not with the mechanism (which would invert the dependency the wrong way).
- _Architecture_: Favor composition over inheritance even in OO languages. Inheritance ties two types together at compile time; composition lets you swap collaborators in tests, at runtime, or per environment.
- _Architecture_: Prefer boring technology that the whole team can reason about over sophisticated patterns that only their author understands. Complexity is a liability unless it solves an equally complex problem.
- _Architecture_: Make illegal states unrepresentable. If a value can only be in one of three modes, model that as a sum type (enum / tagged union / sealed class) rather than three booleans, of which seven of the eight combinations are bugs waiting to happen.
- _Architecture_: Module boundaries follow change axes. Code that changes together belongs together; code that changes for different reasons belongs apart. Folders organized by technical layer (`controllers/`, `services/`, `models/`) often violate this — group by feature first, by layer second.
- _Architecture_: A module's public API is a contract; its internals are not. Mark internals as such (private modules / unexported names / `internal/` directory) and resist the pressure to widen the API surface for one-off needs.
- _Architecture_: Direction of dependency flows from outer (concrete: HTTP, DB, queue) to inner (abstract: domain logic). Domain code never imports adapter code; adapters import the ports the domain defines. This is what hexagonal / clean / onion architecture all boil down to.
- _Architecture_: Keep coupling explicit and directional — draw the dependency graph and verify it is a DAG. Circular dependencies are a sign that boundaries are wrong, not that more interfaces are needed.
- _Architecture_: Cross-cutting concerns (logging, metrics, auth) belong at the edge, not threaded through domain calls. The domain says what happened; middleware/decorators/aspects observe it.
- _Architecture_: When a third-party library leaks into a domain type, wrap it. Importing `mongodb::ObjectId` into your `User` struct couples your domain to that driver — when you migrate, every call site changes. A thin adapter type insulates you.

## Testing

- _Testing_: Tests are non-negotiable — a feature without tests is incomplete. The question is not *whether* to test but *at what level*: pure logic gets unit tests, subsystem boundaries get integration tests, full user flows get end-to-end tests.
- _Testing_: Practice TDD on pure logic — Red (failing test that captures the requirement) → Green (smallest change that passes) → Refactor (improve structure with the test as a safety net). The cycle prevents over-engineering: code exists only to pass a stated test, not to satisfy an imagined future.
- _Testing_: TDD-produced tests are documentation of intended usage. Because the test is written before the implementation, it must show how a caller invokes the component — its shape, inputs, and outputs — making the test a worked example a reader can study to understand the design. This is especially valuable when discussing architectural decisions, because the tests demonstrate the interface in action rather than describing it abstractly.
- _Testing_: TDD applies cleanly to algorithmic and decision-logic code (parsers, business rules, state machines). For integration plumbing — code whose entire job is to wire HTTP handlers to a service or shuttle bytes between systems — exercise it via a small integration test that uses the real wire format, not unit tests with mocks of every collaborator.
- _Testing_: Default to the testing pyramid: many fast unit tests of pure logic, fewer integration tests of subsystem boundaries, fewest end-to-end tests of full user flows. Inverting the pyramid (mostly e2e) makes the suite slow, flaky, and expensive to debug.
- _Testing_: Use property-based testing (`proptest` in Rust, `fast-check` in TS, `hypothesis` in Python) for code with algebraic invariants — round-tripping serializers, idempotent operations, sort/parse/normalize functions. Hand-written cases miss adversarial inputs that generators surface in seconds.
- _Testing_: Mock at architectural boundaries (network, filesystem, clock, randomness), not at module boundaries inside your own code. Mocking your own collaborators couples tests to implementation details and makes refactoring expensive.
- _Testing_: A flaky test is a broken test — quarantine or fix it the same day, never the same week. Flaky tests train the team to ignore CI failures, which lets a real failure slip through unnoticed.

## Documentation

- _Documentation_: Documentation is a first-class deliverable, not a chore. A feature that ships without docs is incomplete in the same way as one without tests — the code may run, but no one outside its author can use, review, or evolve it confidently.
- _Documentation_: Three audiences, three files: `README.md` (users — what is this and how do I run it), `docs/CONTRIBUTING.md` (developers — how do I work on it), `docs/ARCHITECTURE.md` (system designers — how is it built and why). Mixing audiences forces every reader through irrelevant content.
- _Documentation_: Write docs for the *next* developer (often you in six months), not for the current one. Explain *why* a decision was made, not just what was decided — the diff already shows the what.
- _Documentation_: Keep docs adjacent to the code they describe. Library-level docs in module headers (`//!` in Rust, `/** */` package docs in Java/TS); function-level docs on the function. Out-of-band docs drift; in-tree docs travel with the code.
- _Documentation_: Examples are the highest-density docs. A working example beats a paragraph of prose — copy-paste-ability is what real users need. Keep examples in `examples/` and run them in CI so they cannot rot silently.
- _Documentation_: Code comments explain *why* and *what for*, not *what*. The code already shows what it does; a comment that paraphrases the code adds noise. A comment that captures the constraint, the trade-off, or the reason for an apparent contradiction is gold.
- _Documentation_: Architecture decision records (ADRs / RFCs) are how you preserve the *why* across years. When you reverse a past decision, link the new RFC to the old one — the historical context is part of the explanation.
- _Documentation_: Open source project icon pattern: a standalone square SVG icon + markdown `<h1>` is the dominant convention for developer CLI tools; the icon reuses as GitHub org avatar, npm icon, and favicon — a wordmark SVG is too wide for those contexts and name changes require SVG edits rather than a one-line markdown update.
- _Documentation_: `<img align="absmiddle">` inside an `<h1>` vertically aligns an icon with heading text in GitHub-rendered markdown without table layout markup.
- _Documentation_: Plugin/integration icon trademark: when an icon would naturally evoke a platform's trademarked mark, create a geometrically inspired original rather than reproducing the trademark — common practice in plugin ecosystems, avoids IP risk.
- _Documentation_: Surface org-vs-product distinction prominently in the hero and a dedicated section — not buried in Non-Goals. "Anyone can use this" buried in Non-Goals is effectively invisible to readers who skim.

## Security

- _Security_: Never expose tokens, credentials, or secrets in committed code, in client-side bundles, or in logs. Pull secrets from a secret manager at runtime; redact known-secret keys from log output unconditionally.
- _Security_: Validate input at the boundary, then trust it inside. A request enters validation once (at the HTTP layer, message boundary, etc.) and emerges as a typed domain value — no defensive re-validation throughout the stack, no reaching back to "what was the raw string."
- _Security_: Run with the lowest privilege required. Service accounts get the narrowest IAM role; container processes run as non-root; database users get only the schemas they need. Privileges are a one-way ratchet — easy to grant, painful to revoke.
- _Security_: Pin and audit dependencies. Lockfiles (`Cargo.lock`, `bun.lockb`, `go.sum`, `uv.lock`) commit the exact versions you tested; an automated audit step (`cargo audit`, `bun audit`, `govulncheck`, `pip-audit`) catches CVEs in CI rather than in the wild.
- _Security_: Treat AuthN and AuthZ as separate concerns. Authentication answers "who is this"; authorization answers "may they do this". Conflating them is how systems end up with `if user.is_admin` checks scattered through business logic.

## Error Handling

- _Error Handling_: Distinguish recoverable errors (return them) from programmer errors (panic / abort). A failed network call is recoverable; a violated invariant inside your own code is not — recovering from it produces zombie state.
- _Error Handling_: Errors carry context. The error returned three layers up should tell the operator what the system was trying to do, what failed, and what input was involved — not just the leaf cause. `anyhow::Context`, error wrapping, `Error.cause`, all serve the same goal.
- _Error Handling_: Errors should be observable before they are user-visible. Structured logs and metrics catch the error trend (rising 500s, retry exhaustion) before the user reports the symptom.
- _Error Handling_: Retries belong at the edge of an idempotent operation. Wrapping a non-idempotent call in retry logic doubles the transactions and corrupts state. If the operation isn't idempotent, make it idempotent (request IDs, conditional updates) before retrying.

<!--lang:rust-start-->
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
<!--lang:rust-end-->

<!--lang:js-start-->
## JavaScript / TypeScript

- _JS/TS_: Use `bun` as the JS/TS runtime and package manager — it replaces `node` + `npm`/`yarn`/`pnpm` with a single fast tool. Day-to-day commands: `bun install` for dependencies, `bun run <script>` for package scripts, `bun test` for tests, `bun <file.ts>` to execute TypeScript directly without a separate build step.
- _JS/TS_: Use `bun install --frozen-lockfile` in CI to catch accidental lockfile drift. Without this flag, bun silently updates the lockfile on install and masks dependency mismatches.
- _JS/TS_: Enable `"strict": true` in `tsconfig.json` from day one. Retrofitting strict TypeScript into a loose codebase is far more expensive than writing strict types up front.
- _JS/TS_: Treat `any` as a code smell, not an escape hatch. If the type genuinely is unknown at the boundary, use `unknown` and narrow it with a type guard — `unknown` forces the narrowing; `any` silently disables every check downstream.
- _JS/TS_: Validate external data at the boundary with a schema library (`zod`, `valibot`, `arktype`). The TypeScript type system has no presence at runtime; without runtime validation, your typed function will happily process malformed JSON until it crashes deep in the call stack.
- _JS/TS_: Prefer named exports over default exports. Default exports break tree-shaking heuristics, fight refactor tools (default symbols are renamed inconsistently across files), and lose the export name in the import statement.
- _JS/TS_: Use ESM (`import`/`export`) throughout the codebase, not a CommonJS/ESM mix. Mixing the two creates dual-package hazards and inconsistent module resolution.
- _JS/TS_: Configure path aliases in `tsconfig.json` (`@/foo`) and bundler config together. Using one without the other ships code that compiles but cannot resolve at runtime.
- _JS/TS_: Prefer `Date.now()` and explicit timezone handling (e.g., `Intl.DateTimeFormat`) over `new Date(string)` parsing. JavaScript date parsing is locale-dependent and silently wrong for ambiguous formats.
- _JS/TS_: Use `eslint` with `@typescript-eslint` rules and run it in CI. Pair it with `prettier` (formatting only — let eslint handle correctness rules).
<!--lang:js-end-->

<!--lang:python-start-->
## Python

- _Python_: Add type annotations as you write code, not after. Retrofitting types into untyped Python is slow and often reveals design issues that are costly to fix late.
- _Python_: Use `uv` for dependency management (`mise.toml` pins the Python version; `uv sync` manages the venv). Mixing pip, venv, and pyenv leads to environment drift across machines.
<!--lang:python-end-->

<!--lang:go-start-->
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
<!--lang:go-end-->

<!--lang:svelte-start-->
## Svelte

- _Svelte_: Use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`) for new components. Runes are explicit about reactivity boundaries; the legacy `let` + `$:` pattern works but obscures whether a value is reactive or not.
- _Svelte_: `$effect` is for side effects (DOM, network, timers), not for deriving values. If you find yourself writing `$effect(() => { derived = a + b })`, replace it with `let derived = $derived(a + b)` — the compiler builds a smaller, more correct dependency graph.
- _Svelte_: Co-locate component-scoped styles in `<style>` blocks; reach for global stylesheets only for tokens (color/spacing variables) and resets. Scoped styles let you delete a component without orphaning its CSS.
- _Svelte_: Use SvelteKit's load functions (`+page.ts`, `+page.server.ts`) for data fetching, not `onMount`. Load functions run during SSR, integrate with the router's loading state, and avoid the "blank page → flash of content" pattern.
- _Svelte_: Type `$props` explicitly with a `Props` interface. Untyped props lose autocomplete in consumers and silently accept misspelled prop names.
- _Svelte_: Prefer the `bind:` directive over manual two-way state plumbing for form inputs and component-shared state. Custom plumbing reinvents what `bind:value` already does and gets it wrong on edge cases (composition events, paste, etc.).
- _Svelte_: Server-only code goes in `+*.server.ts` files; never import server modules from client code. The bundler can usually catch this, but a server import inside a `$lib` shared module sneaks past — check both ends of every shared module.
<!--lang:svelte-end-->

<!--lang:ruby-start-->
## Ruby

- _Ruby_: Pin Ruby version in `.ruby-version` and lock dependencies in `Gemfile.lock`; install via `mise` (or `rbenv` / `chruby`). Mixed Ruby installations across machines produce silent gem-load mismatches.
- _Ruby_: Run `bundle exec` for project commands (`bundle exec rake`, `bundle exec rspec`) — it pins binaries to the bundle. Direct `rspec` invocations pick up the system gem version and produce results that don't match CI.
- _Ruby_: Prefer keyword arguments over positional hashes for any method with more than two parameters. Keyword args are self-documenting at the call site and produce clear errors on missing/extra keys.
- _Ruby_: Treat `nil` checks as a smell. Ruby's null object pattern, `&.` (safe navigation), or `Array(maybe_nil_array)` produce more readable code than `if foo.nil? ...` ladders.
- _Ruby_: Run `rubocop` and `standard` (pick one) in CI. Both enforce style consistency that reviewers would otherwise spend energy on.
- _Ruby_: Use `rspec` or `minitest` consistently — don't mix. Each has its own conventions for fixtures, doubles, and matchers; mixing forces every contributor to context-switch between them.
- _Ruby_: Prefer immutable data classes (`Data.define`, structs frozen on creation) over mutable hashes for typed records. Mutability is the fastest path to spooky-action-at-a-distance bugs.
<!--lang:ruby-end-->

<!--lang:rails-start-->
## Rails

- _Rails_: Fat controllers and fat models are both anti-patterns. Push business logic into plain Ruby objects (services, form objects, query objects) under `app/services/`, `app/queries/`, etc. The model owns persistence; the controller owns request/response shape; the rest is its own concern.
- _Rails_: Use strong parameters at the controller boundary, but parse them into a typed object (form object, dry-struct, ActiveModel) before passing to services. Services that take raw params couple to the HTTP shape.
- _Rails_: Database migrations are append-only history. Never edit a merged migration; add a new one. Rolling back in production is risky enough that you want an explicit reverse migration, not a silent "rerun this".
- _Rails_: Use `find_each` (or `in_batches`) for any query over more than a few hundred records. `User.all.each` loads the entire table into memory and OOMs the dyno on first real-world data.
- _Rails_: Wrap multi-record writes in `ActiveRecord::Base.transaction`. Without one, a partial failure (network blip on the second `INSERT`, validation error on the fifth row) leaves the database in a state nobody designed for.
- _Rails_: Background jobs are at-least-once by default — make them idempotent. The worker that received a job once will receive it twice when the queue retries; if the job mutates state without a unique-key guard, you've created duplicates.
- _Rails_: Use `bin/rails credentials:edit --environment <env>` for secrets in committed config; never commit secrets in plaintext. The Rails master key goes in your secret manager and into the deploy pipeline as an env var.
- _Rails_: Eager-load associations in any list view (`includes(:author, :tags)`). N+1 queries pass tests on three rows and crash on three thousand. Add `bullet` (or the `prosopite` gem) in development so they fail loudly during development.
- _Rails_: Prefer `where.missing(:association)` and Active Record query methods over raw SQL. When raw SQL is necessary, sanitize with bind parameters — never interpolate strings into a query.
<!--lang:rails-end-->

<!--lang:k8s-start-->
## Kubernetes / CUE / kapply

- _K8s/CUE_: Render manifests with CUE, not Helm templating or YAML anchors. CUE constraints catch invalid shapes (missing `resources.limits`, malformed selectors) at build time; Helm catches them at apply time, sometimes after partial application has already happened.
- _K8s/CUE_: Pipeline shape is `cue export --out yaml -e resources ./k8s/clusters/<env> | kapply -n <env> -`. CUE produces the desired stream; kapply tracks the inventory and prunes anything that left the desired set. Never apply YAML directly with `kubectl apply` from a render — you lose the prune story.
- _kapply_: kapply tracks the applied set in a ConfigMap inventory and refuses to run on an empty input stream — that guard is what prevents an accidental "prune everything" when the render layer fails or emits nothing. Do not work around it; fix the render.
- _kapply_: kapply exit codes have meaning: `0` = no changes, `2` = changes applied successfully, `1` = error/conflict. Deploy scripts should treat both `0` and `2` as success and only fail on `1`.
- _kapply_: kapply uses server-side apply with `force-conflicts` and a per-distribution field manager. If two distributions try to manage the same field, kapply refuses to take over — fix ownership in CUE rather than working around the conflict.
- _K8s/CUE_: Pin the API version of every manifest (`apiVersion: apps/v1`, not the latest implicit). Cluster upgrades occasionally remove old API versions; pinning surfaces the migration as a CUE compile error rather than a silent runtime regression.
- _K8s_: Set `resources.requests` and `resources.limits` on every container. Without requests, the scheduler treats the pod as best-effort; without limits, a noisy neighbor can starve the node.
- _K8s_: Use `readinessProbe` and `livenessProbe` thoughtfully — readiness gates traffic, liveness restarts pods. A liveness probe that's too aggressive on a slow-starting service crashes a healthy pod; a readiness probe missing on a slow-starting service routes traffic to a not-ready container.
- _K8s_: Don't set `spec.replicas` on a Deployment that has an HPA — they fight. Either set replicas (no HPA) or set HPA bounds (no static replicas).
- _K8s_: Run with the lowest privilege necessary: drop all capabilities except those required, run as non-root, set `readOnlyRootFilesystem: true` where the workload allows. PodSecurityPolicy / Pod Security Admission catches the rest.
- _K8s_: Namespace everything. The default namespace is fine for one-off tools; production workloads belong in named namespaces so RBAC, NetworkPolicies, and resource quotas can be applied.
- _kapply_: Use `kapply verify` after a deploy to confirm every inventoried resource is still present and stamped. A passing deploy that subsequently drifts (manual edit, garbage collector reaping a parent) is invisible without the verify pass.
<!--lang:k8s-end-->

<!--lang:terraform-start-->
## Terraform / Terragrunt

- _Terraform_: Pin provider versions in every module (`required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }`). An unpinned provider can change resource schema between plan and apply, producing destructive diffs nobody asked for.
- _Terraform_: Pin Terraform itself with `required_version = ">= 1.6.0, < 2.0.0"` in every module. Across-major upgrades deprecate behavior; pinning forces a deliberate upgrade path.
- _Terraform_: Remote state with locking is non-negotiable for any shared environment. S3 + DynamoDB or GCS + native locks. Local state is fine for a single-author personal stack and disastrous for a team.
- _Terraform_: Run `terraform plan` in CI on every PR and require the plan output as a review artifact. A merged PR whose plan was never inspected is a merge to production by-accident.
- _Terraform_: Treat `terraform apply` as a privileged operation. Apply happens through CI on a protected branch, never from a developer's laptop in a shared environment.
- _Terragrunt_: Use Terragrunt to orchestrate multiple Terraform modules with shared inputs. The DRY pattern (`terragrunt.hcl` per environment, generating provider/backend blocks) is what Terragrunt is for; treat the per-env files as configuration, not code.
- _Terragrunt_: Run `terragrunt run-all plan` from the root only when you genuinely need to plan everything. For day-to-day work, `cd` into the affected module and run `terragrunt plan` there — it's faster and the blast radius is one module.
- _Terraform_: Module inputs must be typed (`variable "x" { type = string }`). An untyped variable accepts anything and surfaces type errors deep in the resource block instead of at the boundary.
- _Terraform_: Don't use `null_resource` + `local-exec` to glue together what providers can do natively. Glue scripts have no dependency graph, no idempotency, and no rollback — they're the easiest way to make a deterministic system non-deterministic.
- _Terraform_: Tag every resource with a standard set (owner, environment, cost-center, managed-by-terraform=true). Tags are the only path from "what is this resource?" to an answer the cost-management and audit teams can use.
- _Terraform_: Run `tflint` and `tfsec` (or `checkov`) in CI. tflint catches style and provider-specific issues; tfsec/checkov catches security misconfigurations (public S3 buckets, unencrypted volumes) before they're applied.
- _Terraform_: Refactor with `moved` blocks, not `terraform state rm` + `terraform import`. `moved` is reversible, declarative, and reviewable; manual state surgery is none of those.
<!--lang:terraform-end-->

## Project-Specific

Entries below describe rules and gotchas specific to this codebase. They are not promoted to the global pool by `/best-practices-sync` and they are not transferable to other projects. Do not move entries into or out of this section without re-triaging — see [`skills/best-practices-extract/TRIAGE-AND-LIFT.md`](../skills/best-practices-extract/TRIAGE-AND-LIFT.md) (path resolves inside the bytewyrd plugin checkout; in a consumer project the file lives at `.claude/plugins/bytewyrd/skills/best-practices-extract/TRIAGE-AND-LIFT.md`).

(none yet — entries are added by `/best-practices-extract` when a learning fails the portability triage)
