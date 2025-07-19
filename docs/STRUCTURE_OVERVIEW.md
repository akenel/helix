# 🧭 Helix Project Structure (v3)

- `utils/` — Reusable shell utilities
  - `core/` — Shared logic (spinners, config, logging)
  - `bootstrap/` — Cluster/bootstrap setup utilities
  - `addons/` — Keycloak and plugin integration tools
- `bootstrap/` — All core deployment phases and configuration
- `archive/` — Deprecated or backup scripts (read-only)
- `misc/` — Garbage bin and scratchpad for in-dev snippets
- `tools/` — Long-lived helpers and verifiers
- `run.sh` — Main orchestrator script
