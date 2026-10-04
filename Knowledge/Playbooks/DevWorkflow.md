---
type: Playbook
title: Development & Verification Workflow
description: Standardized development, testing, and validation lifecycle commands.
tags: [playbook, workflow, verification]
status: stable
sources: []
---
## Goal
Standardized development, testing, and validation lifecycle for TheCrust.

## Verified Facts
- All knowledge modifications must be followed by `okf index Knowledge` and `okf validate Knowledge`.
- Code changes must adhere to CamelCase/hyphen file naming and modular multi-file structure.

## Direct Code / CLI Snippet
```pwsh
# 1. Search knowledge before investigating:
okf search Knowledge --text "<topic>"

# 2. Re-index and validate knowledge bundle:
okf index Knowledge
okf validate Knowledge
```
