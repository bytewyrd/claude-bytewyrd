# Agents reference

The 48 specialist subagents bundled with the `claude-bytewyrd` plugin. Each agent's `name`, `model`, and one-line role come from the agent's own frontmatter in `agents/<name>.md` — to update an entry, edit the source agent file, not this page.

The main agent picks the right subagent automatically based on the description-trigger heuristic. You can also request one by name (e.g., "Use the `code-reviewer` subagent to review this PR").

For the design rationale (why agents are local files instead of network-fetched, why noun-first naming), see [`docs/ARCHITECTURE.md`](../../ARCHITECTURE.md). For pulling improvements from the upstream `VoltAgent/awesome-claude-code-subagents` project, see [`docs/CONTRIBUTING.md`](../../CONTRIBUTING.md).

## Plugin-workflow agents

Agents that participate directly in the bytewyrd plugin's RFC and docs workflow. These are first-class — invoked by name from `/rfc-*` and `/refactor` and `/docs-review`.

| Agent | Model | Role |
|-------|-------|------|
| `rfc-architect` | opus | RFC authoring, research, design review. Spawned by `/rfc-new`, `/rfc-read-feedback`. |
| `feature-engineer` | opus | RFC-driven feature implementation with SOLID and TDD. Spawned by `/rfc-implement`. |
| `code-reviewer` | opus | Rigorous PR review — correctness, security, performance, conventions. Default for PRs and spawned by `/rfc-consensus-review`. |
| `refactoring-specialist` | opus | Deliberate, behavior-preserving refactoring with characterization tests and an approval gate. Spawned by `/refactor`. |
| `debugger` | opus | Root cause analysis and systematic diagnosis of hard-to-reproduce failures. |
| `docs-agent` | opus | User-facing documentation under `docs/guide/**` and `README.md`. Spawned by `/docs-review`. |
| `documentation-writer` | opus | General-purpose docs work outside `docs/guide/**`. |
| `claude-agent-author` | opus | Authoring and auditing subagent definitions in `agents/` against the plugin's audit criteria. |

## Backend and platform

| Agent | Model | Role |
|-------|-------|------|
| `backend-developer` | sonnet | Scalable API development, microservices, server-side logic. |
| `api-designer` | sonnet | REST and GraphQL design with developer-friendly interfaces. |
| `graphql-architect` | sonnet | GraphQL schema design, federation, subscriptions, query optimization. |
| `microservices-architect` | sonnet | Distributed system architecture, service boundaries, communication patterns. |
| `websocket-engineer` | sonnet | Real-time bidirectional communication, low-latency messaging. |

## Frontend and UX

| Agent | Model | Role |
|-------|-------|------|
| `frontend-developer` | sonnet | React components, accessibility, web standards. |
| `react-specialist` | sonnet | React 18+, advanced hooks, server components, performance. |
| `nextjs-developer` | sonnet | Next.js 14+, App Router, server actions. |
| `fullstack-developer` | sonnet | End-to-end feature ownership across the stack. |
| `ui-designer` | sonnet | Design systems, interaction patterns, visual hierarchy. |
| `ux-design-architect` | sonnet | User interface design, component systems, design specifications. |

## DevOps and infrastructure

| Agent | Model | Role |
|-------|-------|------|
| `devops-engineer` | sonnet | CI/CD, containerization, infrastructure automation. |
| `deployment-engineer` | sonnet | Release automation, blue-green, canary, rolling deployments. |
| `cloud-architect` | sonnet | Multi-cloud strategy (AWS, Azure, GCP), scalable systems. |
| `kubernetes-specialist` | sonnet | Cluster management, production deployments, security hardening. |
| `terraform-engineer` | sonnet | Infrastructure as code, multi-cloud provisioning, modular architecture. |
| `terragrunt-expert` | sonnet | Terragrunt-based IaC orchestration, DRY config patterns, multi-env deployments. |
| `platform-engineer` | sonnet | Internal developer platforms, self-service infrastructure, golden paths. |
| `sre-engineer` | sonnet | SLOs, reliability engineering, toil reduction. |
| `devops-incident-responder` | sonnet | Rapid detection, diagnosis, and resolution of production issues. |
| `build-engineer` | sonnet | Build system optimization, caching, fast and reliable build pipelines. |

## Data and databases

| Agent | Model | Role |
|-------|-------|------|
| `database-administrator` | sonnet | PostgreSQL, MySQL, MongoDB, Redis — operations, HA, disaster recovery. |
| `database-optimizer` | sonnet | Query tuning, index strategy, execution plan analysis. |
| `postgres-pro` | sonnet | PostgreSQL internals, advanced features, performance optimization. |
| `sql-pro` | sonnet | Complex SQL across PostgreSQL/MySQL/SQL Server/Oracle. |

## Security and quality

| Agent | Model | Role |
|-------|-------|------|
| `security-engineer` | opus | DevSecOps, vulnerability management, cloud and container security. |
| `penetration-tester` | opus | Adversarial review — exploit paths, abuse cases, security-sensitive RFCs. |
| `qa-expert` | sonnet | Test strategy, quality metrics, manual and automated testing. |
| `test-automator` | sonnet | Test framework design, CI integration, automated test coverage. |
| `performance-engineer` | sonnet | Profiling, load testing, bottleneck identification. |

## Languages

| Agent | Model | Role |
|-------|-------|------|
| `typescript-pro` | sonnet | Advanced TypeScript type system, full-stack TS, build optimization. |
| `python-pro` | sonnet | Modern Python 3.11+, async, type safety, data science. |
| `rust-engineer` | sonnet | Systems programming, memory safety, async, performance optimization. |
| `golang-pro` | sonnet | Idiomatic Go, concurrent programming, cloud-native microservices. |
| `rails-expert` | sonnet | Rails 7+, Hotwire, Action Cable, convention-over-configuration. |
| `cli-developer` | sonnet | CLI design, developer tools, terminal applications. |

## AI and LLM

| Agent | Model | Role |
|-------|-------|------|
| `ai-engineer` | opus | ML system design, training and inference pipelines, deployment. |
| `llm-architect` | opus | LLM system design, fine-tuning (LoRA/QLoRA/RLHF), RAG, serving. |
| `mcp-developer` | opus | Model Context Protocol — servers, clients, transports, schemas, security. |
| `prompt-engineer` | sonnet | Prompt architecture, evaluation, optimization, production prompt systems. |

## How agents are discovered

Claude Code reads `agents/<name>.md` files at the plugin root. Each agent's `description` frontmatter is what the autoload heuristic uses to decide when to spawn the agent. Models are set per-agent so the cheapest-fit model applies by default; skills that spawn agents can override the model at invocation time.

To add a new agent, see [Add a new agent to the plugin](../contributing/add-an-agent.md).
