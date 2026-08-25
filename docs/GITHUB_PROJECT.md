# GitHub Project design

Create an owner-level GitHub Project named **omni_navi** so issues from all
component repositories can share one roadmap without moving their source.

## Recommended fields

| Field | Values/purpose |
| --- | --- |
| Status | Backlog, Ready, In progress, In review, Validating, Done |
| Priority | P0, P1, P2, P3 |
| Component | Interfaces, TF, SLAM, Planner, Bridge, Docking, Mission, App, Cloud, Integration |
| Platform | All, x86, Orin, S100, Matrix, Dog, VBot |
| Release | Candidate/version identifier |
| Quality gate | Build, Unit, Simulation, Hardware, Packaging, Security |

## Views

1. **Product roadmap** — grouped by release, sorted by priority.
2. **Integration blockers** — P0/P1 items where Component is Integration.
3. **Platform validation** — grouped by Platform and Quality gate.
4. **Current sprint** — Ready/In progress/In review only.
5. **Release readiness** — grouped by Quality gate with incomplete items first.

Issues remain in their owning repositories. The Project is planning metadata,
not a replacement for repository-specific backlogs or pull requests.

