# Project: TheCrust

> Modding toolkit, reverse engineering, and custom mod development for The Crust (Unreal Engine 4.27.2).

<!-- BEGIN: SETUP-PROJECT MANAGED -->
## Knowledge Base & Agent Router
All project architecture, research findings, and playbooks live in `Knowledge/` as an [OKF](https://github.com/okfcli/okf) bundle.

- **Pre-Flight Lookup**: Run `okf search Knowledge --text "<query>"` before conducting external research or redundant exploration.
- **Architecture Map**: Read [`Knowledge/Architecture/ProjectMap.md`](file:///Knowledge/Architecture/ProjectMap.md) for system boundaries.
- **Tech Stack**: Read [`Knowledge/Architecture/TechStack.md`](file:///Knowledge/Architecture/TechStack.md) for runtimes and dependencies.
- **Playbooks**: Read [`Knowledge/Playbooks/DevWorkflow.md`](file:///Knowledge/Playbooks/DevWorkflow.md) for dev & verify commands.
- **Atomic Recording**: When uncovering non-obvious facts, quirks, or decisions, immediately write a machine-dense card to `Knowledge/Research/` or `Knowledge/Architecture/`.
- **Index**: Run `okf index Knowledge && okf validate Knowledge` after modifying knowledge cards.
<!-- END: SETUP-PROJECT MANAGED -->

## Project Specific Directives
<!-- Add custom project rules and instructions below this line -->
- **Proactive Git Commits**: Always commit changes to git immediately after adding features, modifying code/configs, or updating documentation. Keep the working tree clean.
