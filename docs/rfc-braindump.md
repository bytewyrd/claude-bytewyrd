# RFC Braindump

Potential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.

* **Enforce evidence-based research for rfc-architect.** Update the `rfc-architect` agent's instructions to require verification of all external facts (APIs, library behavior, tool capabilities, version-specific details) via Context7 or Exa before including them in an RFC — training knowledge alone is not an acceptable source. This addresses the risk of RFCs being drafted with outdated or hallucinated technical details that later derail implementation. Approach hints: mirror the "Evidence-Based Development" guidance already in `CLAUDE.md`, and consider adding a self-check step to the RFC self-review checklist that flags unverified claims.
