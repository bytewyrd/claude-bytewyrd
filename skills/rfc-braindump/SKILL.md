---
name: rfc-braindump
description: Use to capture a quick RFC idea or potential RFC candidate without creating a full RFC. Triggered by "/rfc-braindump <idea>".
---

# RFC Braindump

Captures a potential RFC idea in `docs/rfc-braindump.md` as a short paragraph entry. The braindump is a lightweight parking lot — no design, no structure, just enough context to remember the idea and promote it later.

## Steps

### 1. Accept the idea

Accept the idea as an argument. If not provided, ask: "What's the idea to capture?"

### 2. Clarify if needed

If the idea is unclear — too vague to distill, references something ambiguous, or describes a symptom without a clear direction — ask one targeted clarifying question:

> "What change would this RFC make, or what problem would it solve?"

If the idea is clear enough to write a short paragraph, skip clarification.

### 3. Distill the entry via Opus + extended thinking

Spawn an Agent with `model: "opus"` and pass the raw idea (plus any clarification from step 2) as context. Instruct it to use extended thinking to preserve the important nuance and intent from the user's input, then compress it into:

`* **<Title>.** <paragraph>` — bold title, 2–4 sentences, under ~150 words, covering:
- What would change or be built
- What problem it solves
- Any key constraints or approach hints worth capturing

The goal is **fidelity without verbosity**: nothing important from the user's idea should be lost, but the output must remain a tight paragraph — not a design doc. Do not design or spec the solution.

Instruct the agent to return **only** the `* **Title.** paragraph` bullet — nothing else. Use the agent's output verbatim as the entry.

### 4. Append to `docs/rfc-braindump.md`

```bash
result="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/rfc-braindump-append.sh" "$ENTRY_BODY")"
created_file="$(printf '%s' "$result" | jq -r .created_file)"
```

Where `$ENTRY_BODY` is the formatted bullet text from Step 3 (*excluding* the leading `* ` marker), e.g., `**Title.** Paragraph text.`. The script creates the file with the standard header if absent — `$created_file` is `true` in that case, useful when the agent wants to surface "created docs/rfc-braindump.md" in its running log alongside the standard "appended" message.

### 5. Confirm

Tell the user:
- The entry added
- Reminder: promote any braindump entry to a full RFC with `/rfc-new`
