# Third-Party Notices

This plugin is licensed under the Apache License 2.0 (see [`LICENSE`](LICENSE)). It includes material from the third-party project listed below, which remains under its own license.

## VoltAgent/awesome-claude-code-subagents

- **Source:** <https://github.com/VoltAgent/awesome-claude-code-subagents>
- **License:** MIT (full text below)
- **Used in:** `agents/*.md`

Portions of the agent definitions in `agents/*.md` are derived from this project. The agents were vendored into this repository on 2026-05-09 (commit `a31334f`) and are now maintained here, so most of them differ from upstream to some degree.

### Files that retain substantial upstream text

Measured by comparing each agent's body (the text after the YAML frontmatter, ignoring HTML comments) line by line against the same-named upstream file at upstream commit `7308a36` (2026-05-04), the upstream state when the agents were vendored. The percentage is the share of the local file's non-blank body lines that appear verbatim in the upstream file. A comparison against the current upstream `main` found no higher match for any file.

| File | Upstream file | Body lines verbatim from upstream |
|------|---------------|-----------------------------------|
| `agents/api-designer.md` | `categories/01-core-development/api-designer.md` | 96% |
| `agents/backend-developer.md` | `categories/01-core-development/backend-developer.md` | 98% |
| `agents/build-engineer.md` | `categories/06-developer-experience/build-engineer.md` | 95% |
| `agents/cli-developer.md` | `categories/06-developer-experience/cli-developer.md` | 98% |
| `agents/cloud-architect.md` | `categories/03-infrastructure/cloud-architect.md` | 83% |
| `agents/database-administrator.md` | `categories/03-infrastructure/database-administrator.md` | 91% |
| `agents/database-optimizer.md` | `categories/05-data-ai/database-optimizer.md` | 88% |
| `agents/deployment-engineer.md` | `categories/03-infrastructure/deployment-engineer.md` | 91% |
| `agents/devops-engineer.md` | `categories/03-infrastructure/devops-engineer.md` | 36% |
| `agents/devops-incident-responder.md` | `categories/03-infrastructure/devops-incident-responder.md` | 95% |
| `agents/frontend-developer.md` | `categories/01-core-development/frontend-developer.md` | 26% |
| `agents/fullstack-developer.md` | `categories/01-core-development/fullstack-developer.md` | 99% |
| `agents/golang-pro.md` | `categories/02-language-specialists/golang-pro.md` | 98% |
| `agents/graphql-architect.md` | `categories/01-core-development/graphql-architect.md` | 93% |
| `agents/kubernetes-specialist.md` | `categories/03-infrastructure/kubernetes-specialist.md` | 99% |
| `agents/microservices-architect.md` | `categories/01-core-development/microservices-architect.md` | 96% |
| `agents/nextjs-developer.md` | `categories/02-language-specialists/nextjs-developer.md` | 89% |
| `agents/performance-engineer.md` | `categories/04-quality-security/performance-engineer.md` | 88% |
| `agents/platform-engineer.md` | `categories/03-infrastructure/platform-engineer.md` | 94% |
| `agents/postgres-pro.md` | `categories/05-data-ai/postgres-pro.md` | 94% |
| `agents/prompt-engineer.md` | `categories/05-data-ai/prompt-engineer.md` | 94% |
| `agents/python-pro.md` | `categories/02-language-specialists/python-pro.md` | 91% |
| `agents/qa-expert.md` | `categories/04-quality-security/qa-expert.md` | 96% |
| `agents/react-specialist.md` | `categories/02-language-specialists/react-specialist.md` | 95% |
| `agents/rust-engineer.md` | `categories/02-language-specialists/rust-engineer.md` | 99% |
| `agents/sql-pro.md` | `categories/02-language-specialists/sql-pro.md` | 99% |
| `agents/sre-engineer.md` | `categories/03-infrastructure/sre-engineer.md` | 96% |
| `agents/terraform-engineer.md` | `categories/03-infrastructure/terraform-engineer.md` | 91% |
| `agents/terragrunt-expert.md` | `categories/03-infrastructure/terragrunt-expert.md` | 96% |
| `agents/test-automator.md` | `categories/04-quality-security/test-automator.md` | 98% |
| `agents/typescript-pro.md` | `categories/02-language-specialists/typescript-pro.md` | 99% |
| `agents/ui-designer.md` | `categories/01-core-development/ui-designer.md` | 97% |
| `agents/websocket-engineer.md` | `categories/01-core-development/websocket-engineer.md` | 51% |

### Files that started from upstream and were rewritten

These agents were vendored from upstream and later rewritten for this plugin. Little upstream text remains: at most about 12% of body lines in any of them (`rails-expert`, the highest), mostly headings and short generic list items. The files are `agents/ai-engineer.md`, `agents/code-reviewer.md`, `agents/debugger.md`, `agents/llm-architect.md`, `agents/mcp-developer.md`, `agents/penetration-tester.md`, `agents/rails-expert.md`, `agents/refactoring-specialist.md`, `agents/security-engineer.md`.

The remaining agents (`claude-agent-author`, `docs-agent`, `documentation-writer`, `feature-engineer`, `rfc-architect`, `ux-design-architect`) have no counterpart in the upstream project.

When you copy or pull an agent from upstream, add it to the table above (or update its row) in the same change.

### License text

```text
MIT License

Copyright (c) 2025 VoltAgent

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
