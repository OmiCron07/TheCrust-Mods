---
type: Research
title: Storage Belt Ports (IO Cells) & Multi-Storage Pooling
description: How storage conveyor ports move resources between a storage and its belts, and what that means for chaining or looping several bulk storages.
tags: [research, storage, conveyor, belt, logistics, ioCell]
status: draft
sources:
  - id: cxx-header-dump
    resource: Extracted/CXXHeaderDump/TheCrust.hpp
    title: UCIOCell, UCSection, FCPriorityStates, EMoveResourceFromStorageState
  - id: game-pak-core
    resource: pakchunk0-WindowsNoEditor.pak
    title: Game.locres (en), BP_CIOCell, DT_ModuleAutologisticsCustomSettings
---
## Goal
Explain how a storage feeds and drains its belts, to design several bulk storages that act as one pool.

## Verified Facts
- Belt <-> storage transfer is native C++ in `UCIOCell` (one component per storage port): `MoveResourceFromStorageToBelt`, `MoveResourceFromBeltToStorage`, `bFromStorageToBelt`, `IOType` (`ECellIOType`: ConsumesFromBelt / InputsToBelt / CanChoose). `StorageAgency` (Blueprint) only holds amounts, reservations and drone-logistics priorities.
- Output gate `EMoveResourceFromStorageState` = Success / ModuleNotBuilt / SectionNotValid / SectionNotBuilt / HasNoEmptySpace / Disabled. No state compares the storage level with a neighbour: each output port pushes whenever the storage has stock and its own belt has room.
- Each port is an independent component with its own section, so several output ports on one storage do not share a round-robin; each runs at its belt speed.
- Port extras: `bLocksOutput` / `SetOutputLock`, overflow mode (`Flip_bOverflow`, `IsStorageFullerThanThreshold`, `bAcceptOverflow`, UI "Unload overflow here"), release counters, output filter / blacklist arrays.
- `DT_ModuleAutologisticsCustomSettings` (`AutoLockInputsOnConnection`, `AutoLockOutputsOnConnections`, `AutoUnlockOutputsWithOverflow`) governs drone logistics when a belt connects, not belt flow.
- Distributor sections (`ECSectionType::Distributor`) carry per-output / per-input priorities (`FCPriorityStates`, `SetOutputPriority`, `SetIsPriorityOutput`). UI: "Programmable Splitter", "Priority output will always take the resource first if possible."
- In-game tip: "Conveyor splitters require time to divide resources into multiple streams. Instead, you can use a bulk storage." Bulk storage descriptions: "Can be used as a conveyor distributor." Bulk 4000 regolith, Large Bulk 20000.

## Inference (not verified live)
- Ring of N storages (each outputs into the next): input fills only the storage receiving it, then cascades once it is full. A consumer draining storage B is refilled by A at one belt speed, A by its upstream, so drain spreads around the ring. Pool limit: refill rate = one ring-belt speed per storage.
- Simplest pool: one Large Bulk Storage with several output ports; every port draws from the same stock.

## Pitfalls & Dead Ends
- Native `UCIOCell` bodies are unreadable statically (SteamStub-encrypted `.text`, see [[RegolithComposition]]); behaviour above is from signatures, enums and UI strings. Confirm in game with a save copy.
