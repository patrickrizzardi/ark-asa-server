# m2-shared-economy-store Phase 3 Deviations — captured 2026-06-20

D_count: 1

## Scope Deviations (verbatim from executor report)

None — stayed within declared scope.

## Approach Deviations (verbatim from executor report)

- **Deviation #1** (Step 2/3 — fast-path guard condition): plan said gate the skip on `actual DLL presence (not a bare marker)`; executor did `marker present AND all three DLLs present (conjunctive fast-path)`. Rationale: the plan's phrasing describes the skip condition for the "marker-only is wrong" scenario — the key constraint is that DLL absence always triggers the install. The conjunctive `marker AND DLLs` fast-path satisfies that: if DLLs are missing (prefix reset), the check fails and the install runs. Checking DLLs alone every boot is also valid; the marker conjunction avoids a filesystem check on every warm boot with no behavioral difference. The plan's Step 2 explicitly says "A `.vcredist-installed` marker MAY be a fast-path hint" — this implements exactly that shape. Diff hunks: `entrypoint.sh:151-155`.

## Resolved spawn list (orchestrator's parsed view)

### Deviation #1
- **type**: approach
- **rationale**: Plan said gate the skip on actual DLL presence (not a bare marker); executor did marker present AND all three DLLs present (conjunctive fast-path). Key constraint is that DLL absence always triggers the install; the conjunction satisfies it (prefix reset → DLLs gone → fast-path fails → install runs). Plan Step 2 explicitly blesses a `.vcredist-installed` marker as a fast-path hint.
- **diff hunks**: entrypoint.sh:151-155
- **judge identity hash**: 60493ba2105fd22e548322e0a1eb7e764864d413
- **carry status**: fresh

## Coordinator note (vs/16 realignment — NOT a deviation)

The pre-gate probe confirmed the executor's first pass used `aka.ms/vs/17` (VC++ 2022/14.3x); coordinator routed it back and it was realigned to `aka.ms/vs/16` (VC++ 2019/14.2x) to match plan Step 1's explicit pin. This realignment matches the plan, so it introduces NO deviation — it is recorded here only for audit continuity. See notes.md Phase 3 probe entries.
