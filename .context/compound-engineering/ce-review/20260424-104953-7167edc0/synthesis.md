# ce-review synthesis

Scope: current branch vs a84bd8591a7dedba18e1cc55673f734b0ccc61f7
Intent: add macOS preferences backup/restore to dotfriend with recommended/custom wizard choices; skip cloud-backed text replacements, fonts, and third-party app prefs; include keyboard shortcut enabled/disabled state and duti default app associations; update README and AGENTS guidance.
Mode: interactive

Applied safe fixes:
- Added lib/macos_preferences.sh to AGENTS high-value files and task map.
- Guarded generated macOS defaults UI restarts so dry-run/no-op restores do not kill UI services.
- Added a generation regression for the restored_any/DRY_RUN guard.

Residual findings:
- P1 gated_auto: Regeneration can leave stale managed macOS outputs that install.sh may restore anyway.
- P1 agent-native/manual: macOS preferences are not covered by dotfriend sync or generated scripts/backup.sh.
- P2 gated_auto: Recommended macOS backup currently selects every category, beyond the prompt's recommended wording.
- P2 manual: duti export only handles LSHandlerRoleAll and drops viewer/editor/shell-only handlers.
- P2 manual: Dock app layout can be restored through com.apple.dock defaults even when Dock layout backup is off.
- P2 manual: Recommended Apple app prefs include com.apple.Passwords.
- P2 manual: Generated README omits macOS preferences from generated repo restore/sync docs.
- P2 manual: Tests need deterministic fixtures for wizard choices, default export content, and restore execution.
- P3 manual: Legacy dock.defaults compatibility and category metadata can be cleaner.

Verification:
- ./tests/verify_fixes.sh passed.
- ./tests/generate_regressions.sh passed via verify_fixes.
