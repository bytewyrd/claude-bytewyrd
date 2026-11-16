## Svelte

- _Svelte_: Use Svelte 5 runes (`$state`, `$derived`, `$effect`, `$props`) for new components. Runes are explicit about reactivity boundaries; the legacy `let` + `$:` pattern works but obscures whether a value is reactive or not.
- _Svelte_: `$effect` is for side effects (DOM, network, timers), not for deriving values. If you find yourself writing `$effect(() => { derived = a + b })`, replace it with `let derived = $derived(a + b)` — the compiler builds a smaller, more correct dependency graph.
- _Svelte_: Co-locate component-scoped styles in `<style>` blocks; reach for global stylesheets only for tokens (color/spacing variables) and resets. Scoped styles let you delete a component without orphaning its CSS.
- _Svelte_: Use SvelteKit's load functions (`+page.ts`, `+page.server.ts`) for data fetching, not `onMount`. Load functions run during SSR, integrate with the router's loading state, and avoid the "blank page → flash of content" pattern.
- _Svelte_: Type `$props` explicitly with a `Props` interface. Untyped props lose autocomplete in consumers and silently accept misspelled prop names.
- _Svelte_: Prefer the `bind:` directive over manual two-way state plumbing for form inputs and component-shared state. Custom plumbing reinvents what `bind:value` already does and gets it wrong on edge cases (composition events, paste, etc.).
- _Svelte_: Server-only code goes in `+*.server.ts` files; never import server modules from client code. The bundler can usually catch this, but a server import inside a `$lib` shared module sneaks past — check both ends of every shared module.
