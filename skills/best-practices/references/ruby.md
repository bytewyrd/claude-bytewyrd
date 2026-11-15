## Ruby

- _Ruby_: Pin Ruby version in `.ruby-version` and lock dependencies in `Gemfile.lock`; install via `mise` (or `rbenv` / `chruby`). Mixed Ruby installations across machines produce silent gem-load mismatches.
- _Ruby_: Run `bundle exec` for project commands (`bundle exec rake`, `bundle exec rspec`) — it pins binaries to the bundle. Direct `rspec` invocations pick up the system gem version and produce results that don't match CI.
- _Ruby_: Prefer keyword arguments over positional hashes for any method with more than two parameters. Keyword args are self-documenting at the call site and produce clear errors on missing/extra keys.
- _Ruby_: Treat `nil` checks as a smell. Ruby's null object pattern, `&.` (safe navigation), or `Array(maybe_nil_array)` produce more readable code than `if foo.nil? ...` ladders.
- _Ruby_: Run `rubocop` and `standard` (pick one) in CI. Both enforce style consistency that reviewers would otherwise spend energy on.
- _Ruby_: Use `rspec` or `minitest` consistently — don't mix. Each has its own conventions for fixtures, doubles, and matchers; mixing forces every contributor to context-switch between them.
- _Ruby_: Prefer immutable data classes (`Data.define`, structs frozen on creation) over mutable hashes for typed records. Mutability is the fastest path to spooky-action-at-a-distance bugs.
