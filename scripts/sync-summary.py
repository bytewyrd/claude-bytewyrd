#!/usr/bin/env python3
"""
Generate the /sync change summary from sync-run.sh JSON output.
Reads from a file path argument or stdin.

Output: formatted change-summary text on stdout.
Exit 1 on JSON parse error.
"""
import json
import sys


NEW_CLASSES = {"bootstrap_create", "authoritative_add", "add"}
UPDATE_CLASSES = {
    "authoritative_update", "fast_forward", "conflict",
    "conflict_legacy", "unchanged_legacy", "additive_merge_apply",
}
REVIEW_CLASSES = {"additive_merge_with_diff_apply"}
NOTSHOWN_CLASSES = {"unchanged", "local_only"}
ALL_KNOWN = NEW_CLASSES | UPDATE_CLASSES | REVIEW_CLASSES | NOTSHOWN_CLASSES


def load():
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as f:
            return json.load(f)
    return json.load(sys.stdin)


def format_chunks(chunks, strategy):
    lines = []
    if not chunks:
        if strategy == "additive-merge":
            lines.append("      ~ additive merge (no user input required)")
        elif strategy == "additive-merge-with-diff":
            lines.append("      ! additive merge — you cherry-pick which sections to accept")
        elif strategy == "authoritative":
            lines.append("      ✓ (full file)  → authoritative overwrite (plugin-owned)")
        elif strategy == "bootstrap":
            lines.append("      ✓ (full file)  → rendered from template")
        return "\n".join(lines)

    for chunk in chunks:
        cid = chunk.get("id", "?")
        owned = chunk.get("owned", False)
        status = chunk.get("status", "")
        if owned:
            label = (
                "updated (changed)" if status == "changed"
                else "unchanged (preserved)" if status == "unchanged"
                else status
            )
            lines.append(f"      ✓ {cid}  → {label}")
        else:
            lines.append(f"      · {cid}  → preserved (user-owned)")
    return "\n".join(lines)


def plural(n, singular, plural_form=None):
    return singular if n == 1 else (plural_form or singular + "s")


def main():
    try:
        data = load()
    except (json.JSONDecodeError, FileNotFoundError, OSError) as e:
        print(f"sync-summary: error reading input: {e}", file=sys.stderr)
        sys.exit(1)

    classifications = data.get("classifications", [])

    new_items = [c for c in classifications if c.get("classification") in NEW_CLASSES]
    update_items = [c for c in classifications if c.get("classification") in UPDATE_CLASSES]
    review_items = [c for c in classifications if c.get("classification") in REVIEW_CLASSES]
    notshown_items = [c for c in classifications if c.get("classification") in NOTSHOWN_CLASSES]
    error_items = [c for c in classifications if c.get("classification") not in ALL_KNOWN]

    total_changes = len(new_items) + len(update_items) + len(review_items) + len(error_items)

    lines = ["/sync — change summary:"]

    if total_changes == 0:
        lines.append("\nEverything is up to date.")
        print("\n".join(lines))
        return

    if new_items:
        n = len(new_items)
        lines.append(f"\nNew {plural(n, 'file')} ({n}):")
        for item in new_items:
            target = item.get("target", "?")
            strategy = item.get("strategy", "")
            chunks = item.get("chunks", [])
            lines.append(f"  + {target}")
            detail = format_chunks(chunks, strategy)
            if detail:
                lines.append(detail)

    if update_items:
        n = len(update_items)
        lines.append(f"\n{plural(n, 'Update', 'Updates')} ({n} {plural(n, 'file')}):")
        for item in update_items:
            target = item.get("target", "?")
            strategy = item.get("strategy", "")
            chunks = item.get("chunks", [])
            lines.append(f"  ~ {target}")
            detail = format_chunks(chunks, strategy)
            if detail:
                lines.append(detail)

    if review_items:
        n = len(review_items)
        lines.append(f"\nReview needed ({n} {plural(n, 'file')} — additive-merge-with-diff):")
        for item in review_items:
            lines.append(f"  ! {item.get('target', '?')}")

    if error_items:
        n = len(error_items)
        lines.append(f"\n{plural(n, 'Warning', 'Warnings')} ({n} {plural(n, 'item')} need attention):")
        for item in error_items:
            target = item.get("target", "?")
            err = item.get("error") or item.get("classification", "unknown")
            lines.append(f"  ? {target} — {err}")

    if notshown_items:
        local_only = [c["target"] for c in notshown_items if c.get("classification") == "local_only"]
        unchanged = [c["target"] for c in notshown_items if c.get("classification") == "unchanged"]
        parts = []
        if local_only:
            parts.append(f"{', '.join(local_only)} (local-only, preserved)")
        if unchanged:
            parts.append(f"{', '.join(unchanged)} (unchanged)")
        if parts:
            lines.append(f"\nNot shown: {'; '.join(parts)}.")

    print("\n".join(lines))


if __name__ == "__main__":
    main()
