## Installation

bytewyrd depends on three plugins from Anthropic's official marketplace: `github`, `context7` and `code-review`. Claude Code doesn't load bytewyrd unless all three are installed and enabled. The `claude plugin` commands never register the official marketplace themselves, so add it first. User scope is the default — install once per machine, active in every project you open:

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add bytewyrd/claude-bytewyrd
claude plugin install bytewyrd@bytewyrd
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official
```

If the official marketplace is already registered, the first command changes nothing. Installing bytewyrd also installs its three dependencies. The last three commands install them yourself too, so that updates keep them resolved. The plugins load the next time you start Claude Code, or when you run `/reload-plugins` in a session that is already open.

`--scope user` is the default and writes the enable-flag to `~/.claude/settings.json`, making the plugin available in every project you open.

To follow a branch or tag instead of `main`, add `#<ref>` to the bytewyrd marketplace source:

```bash
claude plugin marketplace add bytewyrd/claude-bytewyrd#<ref>
```

Without a pin you track `main`. The plugin has no version number, so every new commit on `main` is an update.

To enable the plugin for everyone who works in one repository, install it at project scope instead:

```bash
claude plugin install bytewyrd@bytewyrd --scope project
```

This records the plugin in the repository's `.claude/settings.json`. Committing that file turns the plugin on for your collaborators, but it doesn't install the plugin for them: each collaborator runs the same command once per clone. See [Choose an install scope](https://code.claude.com/docs/en/plugins/install#choose-an-install-scope) in the Claude Code docs, and [Team-wide enforcement](#team-wide-enforcement-optional) below.

Once installed, run `/bytewyrd:scaffold` in a project. It seeds `AGENTS.md`, a `CLAUDE.md` that imports it, a pull request template and `.github/workflows/ci.yml`, each only if missing. It is a dry run until you add `--apply`. Run `/bytewyrd:drift` at any time to check those files against the plugin's current templates.

### Upgrading from 0.2.x

An existing install is pinned to the cached 0.2.0 copy, and bytewyrd now loads only once its three dependencies are installed. Add the official marketplace, install the dependencies explicitly so that updates keep them resolved, then refresh the bytewyrd marketplace and update once:

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install github@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install code-review@claude-plugins-official
claude plugin marketplace update bytewyrd
claude plugin update bytewyrd@bytewyrd
```

The first four commands succeed without changing anything when the marketplace or plugin is already there. Restart Claude Code afterwards. From then on, each `claude plugin update` (or marketplace auto-update, if you turn it on) picks up the latest commit on `main`.

The command that set projects up in 0.2.x is gone. Run `/bytewyrd:drift` in each project to list what 0.2.x left behind, each with a one-line fix. The plugin's commands and hooks now need Python 3.11 or newer; see [Requirements](#requirements).

### Requirements

The plugin's commands and two of its hooks run on Python, and its skills read their JSON output with `jq`. You need:

- **Python 3.11 or newer**, on your `PATH` or named in `BYTEWYRD_PYTHON`. Check yours with `python3 --version`.
- **git** and **jq**.

The plugin runs `$BYTEWYRD_PYTHON` when it is 3.11 or newer. Otherwise it takes the first of `python3.15` down to `python3.11` that it finds on your `PATH`, and then `python3` if that is 3.11 or newer. If yours is older, install a newer Python and put it on your `PATH`. Or set `BYTEWYRD_PYTHON` to its path, for example `export BYTEWYRD_PYTHON=/path/to/python3.12`, in the environment you start Claude Code from.

Without a suitable Python, `/bytewyrd:scaffold`, `/bytewyrd:drift` and the helper commands behind the `/rfc-*` skills stop with an error that names this requirement. The hooks that run Python print the same line to stderr, and the session carries on.

## What the plugin adds at session start

When a session starts, after `/clear`, and after a compaction, a `SessionStart` hook adds the plugin's always-on rules to Claude's context: five short statements about evidence, decisions, design, git and long-running processes. Their text is in [`hooks/always-on-rules.json`](../../hooks/always-on-rules.json). The hook only adds text. It checks nothing, prints no warnings, and needs no Python. The 0.2.x releases also ran a requirement check here; it is gone, so there are no warnings to suppress.

## Team-wide enforcement (optional)

The default posture is user-scope-first: install once per machine, available in every project. `/bytewyrd:scaffold` does not write plugin entries to the project's `.claude/settings.json` — adding per-project entries would recreate the maintenance burden (name and marketplace URL) that user-scope was designed to eliminate.

New collaborators who don't have the plugin are covered by the install commands that `/bytewyrd:scaffold` puts in the `CLAUDE.md` it seeds.

If your team wants Claude Code to register the marketplace and turn the plugin on for collaborators who open the repo, you can add both entries manually and commit them to source control. `extraKnownMarketplaces` registers the marketplace, and `enabledPlugins` turns the plugin on:

```json
{
  "enabledPlugins": {
    "bytewyrd@bytewyrd": true
  },
  "extraKnownMarketplaces": {
    "bytewyrd": {
      "source": {
        "source": "github",
        "repo": "bytewyrd/claude-bytewyrd"
      }
    }
  }
}
```

Committing these entries does not install the plugin. Claude Code registers the marketplace only after a collaborator trusts the folder, and each collaborator still runs `claude plugin install bytewyrd@bytewyrd --scope project` once per clone, which also installs bytewyrd's three dependencies. They need the official marketplace registered first. Claude Code normally registers it the first time someone starts an interactive terminal session. In a shell, they add it with `claude plugin marketplace add anthropics/claude-plugins-official`. For the details, see [Require plugins per repository](https://code.claude.com/docs/en/plugins/org#require-plugins-per-repository) and [Choose an install scope](https://code.claude.com/docs/en/plugins/install#choose-an-install-scope) in the Claude Code docs.

This is not the default — and if you choose it, these entries become project-owned and must be kept current if the plugin's marketplace or name ever changes.
