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
