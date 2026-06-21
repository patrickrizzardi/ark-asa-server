## Deviation Judge: ark-asa-server / m2-shared-economy-store Phase 2 Deviation #3 (Round 2 re-judge)

### Verdict: PASS

### Deviation summary (one line)
The binding "clean-replace over rsync" decision was re-homed from notes.md churn to plan.md Decision Ledger row #12 (class: verified-design); notes.md:76 now carries a one-line pointer only.

### Adversarial input(s) constructed

1. **Second copy embedded in the pointer line itself**: notes.md:76 reads "Plugin sync = clean-replace over rsync → see plan.md Decision Ledger row #12 (the durable home)." — does the pointer line also assert the decision's rationale, creating a second binding copy?

2. **Rationale completeness / faithfulness**: row #12 in plan.md:119 — does it capture the real engineering rationale for the choice (not just the name of the choice), or is the rationale only in notes.md making the ledger entry a hollow shell while the actual reasoning lives in churn?

3. **Existing-primitive check**: grep the notes.md "## Phase 2 — decisions" section for any prose that re-asserts the decision body (not the pointer line) to find residual duplication.

### Trace

**Input 1 — pointer-as-second-copy probe:**

notes.md:76 text verbatim: `Plugin sync = clean-replace over rsync → see plan.md Decision Ledger row #12 (the durable home).`

This line names the choice ("clean-replace over rsync") but contains ZERO rationale — no mention of rsync availability, no mention of `set -euo pipefail` abort risk, no mention of POSIX cp/rm guarantee. It is a label + a redirect, not a decision record. The binding rationale lives exclusively in plan.md:119. Rule 00 ("pointer is fine; second copy of the decision+rationale is not") is satisfied. No duplication of the binding decision.

**Input 2 — rationale faithfulness in row #12:**

plan.md:119 row #12 full text:
`Plugin sync uses clean-replace (stash configs → rm AsaApi-owned paths → cp fresh → restore configs), NOT rsync --delete | verified-design | rsync not guaranteed in parkervcp/steamcmd:proton base; under set -euo pipefail a missing rsync aborts with a confusing error; POSIX cp/rm always present (Phase-2 execution)`

This captures:
- The specific mechanism (stash → rm → cp → restore cycle, not just "clean-replace")
- The rejected alternative named explicitly (rsync --delete)
- The primary engineering constraint (rsync not guaranteed in the base image)
- The failure mode of the alternative (pipefail abort with confusing error)
- The positive guarantee of the chosen approach (POSIX cp/rm always present)
- The evidence class (Phase-2 execution — empirically verified, not speculative)

The ledger row is not a hollow label. The full rationale that was previously in notes.md churn is now faithfully reproduced in the durable contract. No information loss.

**Input 3 — residual duplication scan:**

The notes.md "## Phase 2 — decisions" section (lines ~64–85 of current file) contains:
- Distribution channel confirmation (different decision — not this one)
- PERMISSIONS_VERSION documentation pin (different decision)
- Line 76: the one-line pointer (confirmed above — label + redirect only)
- `ONLY FOR DEVELOPERS` dir exclusion (different decision)
- Lib/AsaApi.lib exclusion (different decision)
- .pdb strip at build (different decision)

None of these entries re-assert the clean-replace rationale. The pointer at line 76 is the only reference to the decision in notes.md. No second copy of the binding decision exists anywhere in notes.md.

### Where the fix overshoots (BLOCK only)

N/A — verdict is PASS.

### Strategies attempted

- **Mixed inputs**: Tested whether the pointer line doubles as a second decision record by carrying rationale. It does not — it is label + redirect only. No mix of pointer + rationale creates duplication.

- **Existing-primitive / second-copy check**: Grepped the "## Phase 2 — decisions" block in notes.md entry-by-entry. Zero re-statements of the clean-replace rationale body outside of the pointer line. The rationale body lives exclusively in plan.md:119.

- **Rationale completeness (faithfulness probe)**: Verified row #12's Decision column and Evidence column are substantive — mechanism, rejected alternative, constraint, failure mode, guarantee, evidence class all present. An executor who reads only the plan.md ledger has the full picture. The round-1 BLOCK's concern ("decision in churn not contract") is completely resolved: the contract now IS the home.

- **Round-trip check**: The round-1 finding was "binding decision in notes.md churn, not plan.md ledger." The round-2 fix moved the binding record to plan.md:119 (class: verified-design, consistent with rows #10 and #11). notes.md:76 is now a one-line pointer. Rule 00 one-home requirement is satisfied. The fix is exactly as narrow as the stated problem demanded.

### Bottom Line

Decision is in exactly one durable home (plan.md:119), notes.md holds a one-line pointer with zero rationale, and row #12 is substantively complete. Round-1 BLOCK is resolved — nothing new to BLOCK on here.
