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
