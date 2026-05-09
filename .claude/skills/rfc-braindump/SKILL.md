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

### 3. Write a short paragraph

Write a **bold title** followed by a concise paragraph (2–4 sentences). Keep it under ~150 words. Cover:
- What would change or be built
- What problem it solves
- Any key constraints or approach hints worth capturing

Do not design or spec the solution — just enough to remember the idea and give it a head start when promoted to a full RFC.

### 4. Append to `docs/rfc-braindump.md`

Read `docs/rfc-braindump.md`. If the file doesn't exist, create it with this header first:

```markdown
# RFC Braindump

Potential RFC ideas. Add with `/rfc-braindump`, promote to full RFC with `/rfc-new`.

```

Append the new entry as a bullet at the end of the file:

```
* **<Title>.** <paragraph>
```

### 5. Confirm

Tell the user:
- The entry added
- Reminder: promote any braindump entry to a full RFC with `/rfc-new`
