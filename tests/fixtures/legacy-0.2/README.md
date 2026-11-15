# Legacy 0.2.x fixtures

Each directory here is one case of consumer-sim's step S18 (RFC `2026-11-09-scaffold-and-drift`, B4): a repository that `/sync` 0.2.x set up, holding the artifacts of one `legacy-*` drift code.

- `repo/` holds the case's files under inert names, so they act on nothing in this repository. Each path segment that starts with `dot-` stands for one that starts with `.`, and each file name carries a `.in` suffix. For example, `repo/dot-github/workflows/ci.yml.in` is the case's `.github/workflows/ci.yml`. Real names would matter here: a `.gitignore` changes what git ignores in its subtree, a `CLAUDE.md` is loaded as context, and a `*.md` file is link-checked.
- `expected` lists the findings drift reports for the case, one `<severity>  <path>  <code>` line each, in output order.
- `port.py` is the case's scripted port, which applies the B3 fix. consumer-sim runs `python port.py before REPO STATE PLUGIN` before committing the fixes and running `scaffold --apply`, and `python port.py after REPO STATE PLUGIN` once AGENTS.md exists. STATE is a directory the two phases share, and PLUGIN is the plugin's directory. `_port.py` holds the helpers the ports share.

After the port, drift exits 0.
