---
type: Research
title: Regolith Composition Mixing & Refinery Output
description: How regolith carries an oxide composition map, how storages blend it, and how Single/Multi-Regolith Refineries turn it into oxides and slag.
tags: [research, regolith, refinery, storage, production, bytecode]
status: stable
sources:
  - id: game-pak-core
    resource: pakchunk0-WindowsNoEditor.pak
    title: StorageAgency, ProductionAgency, MB_ExtractorDeepOre, MB_EnrichmentFactory bytecode
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/TheCrust.hpp
    title: UE4SS SDK dump (UCommonCPP_FL, UCResource)
---
## Goal
Explain what happens to deposit composition when regolith from several extractors is merged into one storage and fed to a refinery.

## Verified Facts
- Regolith is ONE resource type (`EResourceType::Regolith = 1`) plus a composition map `TMap<EResourceType,float>` (keys: SiliconOxide, IronOxide, TitanOxide, AluminiumOxide, Slag; fractions, UI widget `W_RegolithSaturation`).
- Composition lives per storage (`StorageAgency.CurrentResourceRegolithPercentage`), per belt item (`UCResource.RegolithPercentage`), per orbital storage (`UOrbitalStorageComponentCPP.RegolithPercentage`). One map per storage: no per-batch tracking.
- Extractor (`MB_ExtractorDeepOre`) overwrites its output storage map with `MineralField.ResourcePercentageForRegolithExtractor` (the deposit profile).
- On deposit into a storage: `UpdateRegolithPercentageWithNewValue(amount, incoming%)` -> `UCommonCPP_FL::RecalculateRegolithPercentage(CurrentAmount, Delta, Incoming%, Current%)` -> replaces the storage map. Native C++; signature implies amount-weighted average `(cur*cur% + delta*in%) / (cur+delta)` (formula NOT verified: exe `.text` is SteamStub-encrypted, see Pitfalls).
- Taking regolith out does not change the map (homogeneous mix).
- Multi-Regolith Refinery = `MB_EnrichmentFactory`; Single Regolith Refinery = `MB_SingleRegolithRefinery`. Both flagged `Enrichment` in `ProductionAgency.EndProduce` unless recipe input key is Slag (6).
- `EndProduce` for Enrichment modules ignores the recipe `To` amounts. With `R = From[Regolith]` consumed per cycle and `p = input storage map`:
  - each output X (oxide, or Slag in a recipe with >2 outputs): `p[X] * R`.
  - Slag in a 2-output recipe (single refinery: oxide + slag): `(1 - p[oxide]) * R`.
  - Amounts go through `TrimResourceFloatWithCollectingExcess` (fractional carry-over).
- Slag-input recipes (Multi refinery on slag) are NOT enrichment: fixed recipe amounts.
- Consequence: Multi refinery output is linear in composition, so merging all extractors into one bulk storage yields the same total oxides as separate lines. Single refinery loses everything except the selected oxide to slag, so mixing dilutes its yield.

## Pitfalls & Dead Ends
- `TheCrust-Win64-Shipping.exe` `.text` has entropy 8.0 plus a `.bind` section (SteamStub DRM): static disassembly of native functions returns garbage. Unpack (Steamless) or call the function live via UE4SS to verify native math.
- Blueprint bytecode readable via `UAssetGUI.exe tojson <in.uasset> <out.json> VER_UE4_27` after `repak unpack -i <path>`.
