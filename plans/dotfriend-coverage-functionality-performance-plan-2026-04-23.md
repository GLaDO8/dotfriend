# Dotfriend Coverage, Functionality, and Performance Plan

Created: 2026-04-23
Status: active
Owner: Codex + Shreyas

## Problem Frame

`dotfriend` is already stronger than the current handcrafted dotfiles repo at machine-state discovery, especially for app-to-cask matching, agent-tool detection, and initial repo generation. But the generated restore experience is still materially behind the current repo in three areas:

1. Coverage fidelity: `dotfriend` captures broad machine state, but it lacks typed handling for important config classes like app-managed files, macOS defaults, secrets, shell cache regeneration, and curated AI tool setup.
2. Restore functionality: the generated installer is generic and copy-heavy, while the current dotfiles installer has specialized restore adapters, stronger preflight behavior, and more complete post-install setup.
3. Performance and maintainability: discovery is already fairly optimized, but sync and generation still over-copy, over-scan, and encode too much behavior as generic directory mirroring instead of structured manifests.

This plan turns `dotfriend` into a generator that preserves its discovery strengths while producing repos and installers with parity-or-better behavior compared with the current handcrafted setup.

## Goals

1. Preserve `dotfriend`'s automated discovery advantages.
2. Add typed backup and restore adapters so generated repos can distinguish symlinked, copied, rsynced, imported, and regenerated state.
3. Reach practical parity with the current dotfiles workflow for install, backup, validation, and agent-tool restoration.
4. Reduce unnecessary copied state so generated repos are smaller, safer, and faster to sync.
5. Expand regression coverage around discovery, generation, installer behavior, and sync behavior.

## Non-Goals

1. Rebuild every one-off preference from the current handcrafted repo in the first pass.
2. Automate app logins, TCC permissions, or other macOS approval flows that remain inherently manual.
3. Replace the existing wizard UX wholesale before backup and installer semantics are stabilized.
4. Implement cloud sync for app data or large mutable app state databases.

## Requirements Traceability

This plan is derived from the repo comparison requested in this thread.

Key requirements carried forward:

1. Improve backup coverage in `dotfriend`.
2. Improve restore and installer functionality in `dotfriend`.
3. Improve runtime and sync performance in `dotfriend`.
4. Use the current dotfiles repo as the parity baseline where its behavior is stronger.

## Current State Summary

### Strengths to Preserve

1. Parallel discovery orchestration in `lib/discovery.sh`.
2. High-quality cask matching and MAS receipt fallback in `lib/discovery.sh`.
3. Agent-tool cataloging in `lib/agent-tools.json`.
4. Existing generation and sync regression coverage in `tests/`.

### Main Gaps

1. The wizard currently writes every discovered `~/.config` directory into selections, which is too broad and untyped.
2. Generated installers mostly treat config as symlink-or-copy, without richer restore classes.
3. Generated installers do not yet have parity for secrets, shell init cache regeneration, macOS defaults import, default-app rules, or specialized agent restore flows.
4. Sync logic still treats tracked config trees generically and lacks manifest-driven semantics.
5. Validation coverage is more generic than the current handcrafted repo's restore-specific checks.

## Architectural Direction

The core design change is to move `dotfriend` from a selection-driven generator to a selection-plus-manifest generator.

Instead of only generating files and simple script blocks, `dotfriend` should generate a machine-readable restore manifest that classifies backed-up state by restore strategy. Generated scripts should consume that manifest, while tests assert both the manifest content and the resulting script behavior.

Recommended restore classes:

1. `symlink`: stable text configs that should remain live-linked to the repo.
2. `copy`: app-managed files that break under symlinks or are rewritten atomically.
3. `rsync`: canonical directories where recursive sync with deletion is desired.
4. `defaults_import`: exported macOS preference domains.
5. `generated`: files that should be regenerated locally after install, not copied from backup.
6. `install_only`: packages or tools that must be installed but are not backed up as repo files.
7. `manual_followup`: explicit post-install reminders for flows that cannot be automated safely.

## Workstreams

### Workstream 1: Backup Manifest and Typed Coverage

Decision:
Introduce a generated backup manifest and curated config registry so coverage is broad but intentional.

Implementation units:

1. `lib/discovery.sh`
2. `lib/wizard.sh`
3. `lib/generate.sh`
4. `lib/common.sh`
5. `lib/agent-tools.json`
6. `templates/install.sh`
7. `templates/scripts/backup.sh`
8. `templates/scripts/validate.sh`
9. `tests/generate_regressions.sh`
10. `tests/verify_fixes.sh`

Changes:

1. Add a curated config registry that classifies known config paths and restore modes.
2. Change wizard selection writing so discovered config directories are not all auto-included by default.
3. Generate a manifest file in the output repo that records selected dotfiles, config entries, agents, defaults, generated files, and manual followups.
4. Keep a separate discovery cache for "seen on machine" vs "approved for backup".

Test scenarios:

1. Selecting a known symlink-safe config produces a `symlink` manifest entry and symlink install block.
2. Selecting a copy-only config like Choosy or Karabiner produces a `copy` manifest entry.
3. Unselected discovered configs do not get copied into the generated repo.
4. Agent entries preserve canonical directories plus excluded symlink views.
5. Generated repo output remains portable and does not embed source-machine absolute paths.

### Workstream 2: Installer Parity

Decision:
Lift the generated installer closer to the current handcrafted installer by reusing its phased structure and restore semantics, but keep it template-driven.

Implementation units:

1. `templates/install.sh`
2. `templates/bootstrap.sh`
3. `lib/generate.sh`
4. `lib/bootstrap.sh`
5. `templates/scripts/validate.sh`
6. `tests/generate_regressions.sh`
7. `tests/verify_fixes.sh`

Changes:

1. Add preflight checks for macOS, repo presence, and writability.
2. Cache installed brew and MAS state during install to avoid repeated process calls.
3. Add typed helper functions for symlink, copy, rsync, defaults import, and generated-file regeneration.
4. Add shell init cache regeneration for tools like `atuin`, `direnv`, `fzf`, and `zoxide`.
5. Add secrets restore hooks using an optional generated secrets section.
6. Replace placeholder `duti` behavior with generated default-app associations when selected.
7. Make VS Code and Cursor extension installs parallelized in generated installers.
8. Preserve soft-fail semantics for package installs and optional setup tasks.

Test scenarios:

1. Generated `install.sh` passes `bash -n`.
2. A repo with defaults exports generates defaults import steps.
3. A repo with generated shell cache entries regenerates caches instead of copying them.
4. Extension installs are skipped cleanly when CLI binaries are unavailable.
5. Installer backs up replaced files safely before mutating them.

### Workstream 3: Agent and Shared Tooling Parity

Decision:
Keep generic agent discovery, but add agent-specific restore adapters for tools with shared global stores or known symlink exclusions.

Implementation units:

1. `lib/agent-tools.json`
2. `lib/discovery.sh`
3. `lib/generate.sh`
4. `lib/sync.sh`
5. `templates/install.sh`
6. `templates/scripts/backup.sh`
7. `templates/scripts/validate.sh`
8. `tests/generate_regressions.sh`
9. `tests/verify_fixes.sh`

Changes:

1. Extend agent metadata to include restore mode, shared stores, generated locals, and validation hooks.
2. Add first-class support for shared `~/.agents/skills` and `~/.agents/agent-docs` style stores.
3. Add agent-specific local template generation where full backup is unsafe, such as local settings overlays.
4. Preserve current Claude hook sanitization behavior while extending it into manifest-driven restore logic.
5. Teach sync to use the agent metadata instead of generic recursive file copy.

Test scenarios:

1. Claude and Codex shared stores are restored without duplicating symlink mirrors.
2. Agent sync skips excluded symlink paths.
3. Generated local template files are created when missing but do not overwrite explicit local user files.
4. Copied agent settings remain sanitized where required.

### Workstream 4: macOS Preferences, Dock, and Default Apps

Decision:
Treat OS-level state as a first-class backup surface with explicit restore classes instead of one-off script snippets.

Implementation units:

1. `lib/discovery.sh`
2. `lib/wizard.sh`
3. `lib/generate.sh`
4. `templates/install.sh`
5. `templates/scripts/backup.sh`
6. `templates/scripts/validate.sh`
7. `tests/generate_regressions.sh`

Changes:

1. Add explicit backup and restore support for tracked preference domains.
2. Separate Dock app list restore from Dock preference restore.
3. Generate concrete `duti` rules for selected browser/media defaults.
4. Add validation for imported defaults and dock restore assets.

Test scenarios:

1. Dock-only selection restores app list without requiring preference import.
2. Preference-domain selection generates import logic for each selected domain.
3. Default-app association selection generates concrete `duti` commands, not placeholders.
4. Validation warns when expected tools like `dockutil` or `duti` are missing.

### Workstream 5: Sync and Reverse-Backup Reliability

Decision:
Make sync manifest-driven so `dotfriend sync` and generated `scripts/backup.sh` behave consistently with how the repo was produced.

Implementation units:

1. `lib/sync.sh`
2. `templates/scripts/backup.sh`
3. `lib/generate.sh`
4. `lib/common.sh`
5. `tests/verify_fixes.sh`

Changes:

1. Make sync read the generated manifest instead of inferring behavior from directory layout alone.
2. Preserve typed behavior across sync: symlink-backed text files, copy-only files, rsynced directories, generated files, and defaults exports.
3. Add drift reporting for removed live files, newly discovered configs, and manifest mismatches.
4. Keep quick mode, but make it append-only only for safe categories.

Test scenarios:

1. Manifest-driven sync updates only selected tracked assets.
2. Copy-only files are copied back into the repo and not converted to symlink workflows.
3. Removed live files surface as drift instead of silently disappearing.
4. Quick mode skips categories that require interactive review.

### Workstream 6: Performance and Scale

Decision:
Preserve parallel discovery and improve performance by reducing unnecessary copying and repeated process calls in sync and generation.

Implementation units:

1. `lib/discovery.sh`
2. `lib/generate.sh`
3. `lib/sync.sh`
4. `tests/benchmark_approaches.sh`
5. `tests/batch_discovery_test.sh`

Changes:

1. Keep the current batched cask API lookup architecture.
2. Add cached lookup indexes where repeated `jq` parsing of the same metadata is still happening.
3. Reduce over-copy in generation by filtering out unselected config trees and generated cache files earlier.
4. Cache manifest-derived path sets in sync rather than repeatedly scanning the repo.
5. Add reproducible benchmarks for discovery and sync on larger mocked config trees.

Test scenarios:

1. Discovery benchmarks remain stable or improve against the current baseline.
2. Sync over a repo with many config directories avoids quadratic rescans.
3. Large config trees exclude `node_modules`, caches, build outputs, and transient directories consistently.

## Proposed Phase Order

### Phase 1: Manifest Foundation

Outcome:
`dotfriend` can distinguish selected state from merely discovered state, and generated repos include a typed manifest.

Primary files:

1. `lib/wizard.sh`
2. `lib/generate.sh`
3. `lib/common.sh`
4. `lib/agent-tools.json`
5. `tests/generate_regressions.sh`

### Phase 2: Installer Parity Core

Outcome:
Generated installers gain preflight checks, typed restore helpers, defaults import, shell cache regeneration, and concrete default-app setup.

Primary files:

1. `templates/install.sh`
2. `templates/bootstrap.sh`
3. `lib/generate.sh`
4. `templates/scripts/validate.sh`

### Phase 3: Agent and Shared-Store Parity

Outcome:
Generated repos restore Claude, Codex, shared agent stores, and other agent tools with structured semantics rather than raw directory rsync.

Primary files:

1. `lib/agent-tools.json`
2. `lib/generate.sh`
3. `lib/sync.sh`
4. `templates/install.sh`
5. `templates/scripts/backup.sh`

### Phase 4: Reverse-Sync and Validation

Outcome:
`dotfriend sync` and generated backup scripts become manifest-driven and validation becomes restore-aware.

Primary files:

1. `lib/sync.sh`
2. `templates/scripts/backup.sh`
3. `templates/scripts/validate.sh`
4. `tests/verify_fixes.sh`

### Phase 5: Performance and Hardening

Outcome:
Discovery, generation, and sync avoid unnecessary work and have benchmark-backed regressions.

Primary files:

1. `lib/discovery.sh`
2. `lib/generate.sh`
3. `lib/sync.sh`
4. `tests/benchmark_approaches.sh`
5. `tests/batch_discovery_test.sh`

## Risks and Mitigations

1. Risk: generated repos become too complex to inspect manually.
Mitigation: keep the manifest human-readable and keep generated shell scripts flat and comment-light.

2. Risk: generic config capture still brings in sensitive or noisy state.
Mitigation: move from auto-include to reviewed selection plus curated registry defaults.

3. Risk: agent restore logic becomes brittle across tool versions.
Mitigation: drive behavior from metadata in `lib/agent-tools.json` and keep version-specific assumptions out of templates.

4. Risk: parity work accidentally regresses current discovery performance.
Mitigation: keep discovery optimizations isolated and benchmarked.

5. Risk: manifest adoption causes a migration burden for already-generated repos.
Mitigation: add manifest bootstrapping logic to sync and document a one-time regeneration path.

## Open Questions

1. Should generated repos keep broad `config/` copies as an opt-in advanced mode, or should they become curated-only by default?
2. Should secrets support be scaffold-only in v1, or should `dotfriend` generate optional `sops` wiring when relevant tools are present?
3. Should default-app associations remain a wizard choice, or be inferred from installed apps and confirmed?
4. Should the generated repo continue to store install behavior mostly in shell, or should some logic move into a machine-readable manifest interpreter script?

## Success Criteria

1. A generated repo can restore the same high-value categories currently covered by the handcrafted dotfiles setup.
2. The generated installer includes preflight, typed restore helpers, defaults import, agent parity, and validation.
3. The generated backup and sync flows use the same manifest semantics as install.
4. Discovery quality stays at least as strong as today for cask and MAS app resolution.
5. Performance benchmarks show no regression in discovery and measurable improvement in sync behavior on larger repos.

## Recommended Execution Posture

Use characterization-first changes for installer and sync behavior. For each workstream, add regression coverage before changing semantics, especially where current generated repos may already rely on existing output shape.
