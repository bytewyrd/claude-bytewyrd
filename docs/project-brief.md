# Project Brief

## Problem

Provides a standardized, opinionated Claude Code setup — skills, agents, and MCP configs — for Bytewyrd projects and teams who want to adopt the same workflow, eliminating the manual work of configuring Claude Code from scratch on each project.

## Goals

Every Bytewyrd project (and any project adopting this workflow) has a consistent, fully-configured Claude Code environment with proven skills, agent delegation patterns, quality gates, and RFC process out of the box.

## Non-Goals

Not a general-purpose Claude Code starter kit for arbitrary workflows — while the conventions are opinionated toward the Bytewyrd stack, the plugin is designed to be adoptable by other teams wanting to follow the same workflow.

## Constraints

Must work within the Claude Code sandbox and permission model; skills must be self-contained and portable across machines without requiring global configuration changes.

This project is both the definition of the Bytewyrd workflow and a live instance of it. All changes follow a promote-through-production model: modifications are made to the project's own `.claude/` configuration first, validated through real usage in this repo, and only then promoted to the exported plugin artifacts that other projects consume. Never edit the plugin export artifacts directly — changes always start in `.claude/`.

## Naming

**`bytewyrd`** is the organization. It owns the namespace (GitHub org, Claude Code plugin namespace `/bytewyrd:*`).

**`claude-bytewyrd`** is this project — the Claude Code plugin. It lives at `bytewyrd/claude-bytewyrd-workflow` on GitHub and is installed as `bytewyrd/claude-bytewyrd` in Claude Code's marketplace. These two names must never be conflated; the plugin is a product of the bytewyrd org, not the org itself.

## Brand Identity

`claude-bytewyrd` is part of the bytewyrd design family. All bytewyrd products share the same visual language (defined originally by tinywyrd's design system) but each carries a distinct icon mark and accent color.

| Product | Icon mark | Accent color | What it is |
|---------|-----------|-------------|------------|
| `tinywyrd` | `~` tilde glyph | Phosphor amber `#F0B72F` | Tiny PaaS |
| `claude-bytewyrd` | 6-petal starburst | Electric blue `#5577FF` | Claude Code plugin |

The `claude-bytewyrd` starburst is an original geometric mark inspired by the Claude aesthetic (rounded petals radiating from a center hub). It is not a copy of Anthropic's trademark — it is an independent mark in the bytewyrd color palette that signals "Claude plugin" through visual kinship, not reproduction.

**Shared design tokens** (from tinywyrd design system):
- Background: `#0B0B0C` (warm near-black), dot-grid texture at 24px pitch
- Typography: Geist / Geist Mono
- Border: `1px solid #1F2024`, `12px` corner radius on square icons
- Dark-mode-first with light-mode parity

**Logo artifacts:**
- `docs/icon.svg` — 96×96 square icon: starburst mark on dark background. The only logo artifact; used in the README, GitHub org avatar, npm, and favicons.

## README Logo Approach

**Decided: square icon (`docs/icon.svg`) + project name as `<h1>` in markdown.**

This is the dominant pattern for open source developer tools (Bun, Deno, Homebrew, Starship, atuin). Reasons:
- The icon SVG doubles as GitHub org avatar, npm icon, favicon — a wordmark is too wide for those.
- The name is a semantic `<h1>`, visible in GitHub search and screenreaders.
- Name changes are a one-line markdown edit, not an SVG edit.
- Dark/light mode is handled automatically by GitHub for the text.

The bytewyrd brand family distinction: tinywyrd is a web product where a wordmark lockup fits naturally; claude-bytewyrd is a developer CLI plugin where the open source icon-plus-H1 pattern is more at home.
