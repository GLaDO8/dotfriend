# npm-release

Automates the full release workflow for the `dotfriend` npm package.

## What It Does

1. **Commits uncommitted changes** — Stages everything and commits with a user-provided message (or a default).
2. **Bumps the version** — Interactive prompt for bump type:
   - `patch` / `minor` → bumps the patch digit (e.g. `0.1.0` → `0.1.1`)
   - `major` → bumps the minor digit (e.g. `0.1.0` → `0.2.0`)
   - `manual` → type any exact version
3. **Commits the version bump** and creates an annotated git tag.
4. **Pushes** commits and tag to `origin`.
5. **Publishes** to npm with `npm publish --access public`.

## Versioning Rules

This project is pre-1.0. The mapping from semantic intent to npm command:

| Intent | `npm` command | Example |
|--------|---------------|---------|
| patch  | `npm version patch` | `0.1.0` → `0.1.1` |
| minor  | `npm version patch` | `0.1.0` → `0.1.1` |
| major  | `npm version minor` | `0.1.0` → `0.2.0` |
| manual | `npm version <x.y.z>` | user-defined |

## Prerequisites

- `git` configured with `origin` remote
- `npm` logged in (`npm whoami` succeeds)
- `gum` optional — provides nicer TUI prompts; falls back to plain `read`

## Usage

Run the bundled script from the repo root.

### Interactive mode (no arguments)

Prompts for commit message, bump type, and confirmation:

```bash
./.agents/skills/npm-release/scripts/release.sh
```

### Non-interactive mode (with argument)

Pass `patch`, `minor`, `major`, or an exact version (e.g. `0.2.0`) to run without prompts:

```bash
./.agents/skills/npm-release/scripts/release.sh patch
./.agents/skills/npm-release/scripts/release.sh 0.2.0
```

When running non-interactively:
- Uncommitted changes are committed with an **auto-generated** conventional commit message based on the files changed.
- The final confirmation prompt is skipped.

The script is self-contained and idempotent for the commit step (only commits if there are actual uncommitted changes).

## Manual Fallback

If the script can't be used, run the equivalent steps by hand:

```bash
# 1. Commit changes
git add -A && git commit -m "chore: pre-release changes"

# 2. Bump version
npm version patch   # or minor, major, or explicit version

# 3. Push
git push origin HEAD && git push origin --tags

# 4. Publish
npm publish --access public
```
