# Design Sources — ark-asa

# Format spec: ~/.claude/memory/design-sources.md
# An unjustified contradiction of a [locked] entry is a gate BLOCK.

- [locked] .claude/rules/build-time-vs-runtime.md — (internal) hard rule governing Dockerfile vs entrypoint placement; 3-question test is load-bearing for every phase
- [locked] docs/internal/decisions/0001-db-engine-mariadb.md     — (internal) ADR: MariaDB as economy store engine; MySQL ≥8.0.28 rejection is a hard constraint
- [locked] docs/internal/decisions/0002-runtime-deploy-of-image-baked-artifacts.md — (internal) ADR: bake-in-image + deploy-at-runtime pattern for VC++ + plugins
- [locked] docs/internal/decisions/0003-cluster-architecture.md — (internal) ADR: clusterid + ClusterDirOverride + shared `ark-cluster` volume (same path on every server); per-server full game volumes is a named tradeoff — do not re-couple the cluster dir per-container
- [locked] docs/internal/decisions/0004-shared-config-model.md — (internal) ADR: ALL 4 configs = repo canonical → fresh per-server copy each boot → repo wins; no shared writable config file anywhere (re-introducing one is a gate BLOCK); Permissions config schema is FLAT (root-level Mysql keys) — never nest it
