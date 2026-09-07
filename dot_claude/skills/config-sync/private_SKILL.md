---
name: claude-config-sync
description: Set up and maintain a chezmoi-managed dotfiles repo to keep Claude Code configuration (settings.json, CLAUDE.md, commands, agents, MCP server setup) synced across multiple Linux machines. Use this whenever the user wants to sync, share, back up, or version-control their Claude Code config across machines, set up dotfiles for Claude Code, or bring a new machine's Claude Code setup up to date with their others. Also use it if the user mentions chezmoi in the context of Claude Code, or asks to "initialize"/"bootstrap" Claude config on a new machine.
---

# Claude Code Config Sync (via chezmoi)

This skill sets up a git-backed, chezmoi-managed dotfiles repo that keeps Claude Code
configuration consistent across multiple machines, while allowing small per-machine
overrides and keeping secrets local (never committed).

It covers two flows:
1. **First-time initialization** (first machine, creates the repo)
2. **Adding another machine** (clones the existing repo and applies it)

Figure out which flow applies by asking the user (see Step 0), then follow the
matching section below. Run one shell command at a time and check its output before
continuing — don't chain the whole setup into one blind script, since git remote
creation and per-machine choices need the user in the loop.

## Guardrails

- **Never commit secrets.** API keys, tokens, and credentials must stay in local
  shell env vars or a password manager — never in the chezmoi source directory.
- **Never invent a git remote URL.** Always ask the user for it, or ask if they want
  guidance creating one first.
- **Confirm before every push.** Show the user `git diff`/`chezmoi diff` output and
  get a go-ahead before `chezmoi apply` or `git push`.
- **Don't add `~/.claude.json` wholesale.** It mixes shareable MCP config with local
  session state and can contain secrets. Handle MCP setup via the run_once script
  approach in Step 6 instead.

---

## Step 0: Determine the flow

Ask the user:

> "Is this the **first machine** you're setting this up on (we'll create a new
> dotfiles repo), or are you **adding another machine** to a setup that already
> exists (we'll clone your existing repo)?"

- First machine → go to **Part A**
- Additional machine → skip to **Part B**

If unclear from context, ask explicitly rather than guessing — the two flows diverge immediately.

---

## Part A: First-time initialization

### A1. Check for chezmoi

Run:
```bash
command -v chezmoi
```
If missing, ask the user:

> "chezmoi isn't installed. Want me to install it now with the official install
> script (`curl -fsLS get.chezmoi.io | sh`), or would you prefer to install it
> yourself first?"

Only run the installer after they confirm — it pipes a remote script to `sh`, so
don't run it unprompted. Once installed, confirm `~/.local/bin` (or wherever it
landed) is on `PATH`.

### A2. Initialize the source directory

```bash
chezmoi init
```

### A3. Set up the git remote

Ask the user:

> "Do you already have an empty git repo created for this (e.g. on GitHub/GitLab)?
> If so, share the remote URL. If not, I'd recommend creating a **private** repo
> now — this will contain your CLAUDE.md and command files, which can reveal
> internal project names or workflows you may not want public."

Once they give a URL:
```bash
cd "$(chezmoi source-path)"
git init
git remote add origin <URL>
```

### A4. Add existing Claude config into chezmoi

Check what actually exists first:
```bash
ls -la ~/.claude/ 2>/dev/null
```

For whichever of these exist, add them one at a time so the user can see what's
being pulled in:
```bash
chezmoi add ~/.claude/settings.json
chezmoi add ~/.claude/CLAUDE.md
chezmoi add ~/.claude/commands
chezmoi add ~/.claude/agents
```

Do **not** add `~/.claude.json` — see Guardrails.

After adding, run `chezmoi diff` and show the user a summary of what got captured
before moving on.

### A5. Ask about per-machine differences

Ask the user:

> "Will every machine run identical config, or do you already know of specific
> settings that need to differ by machine (e.g. a work laptop vs a personal
> desktop)?"

- If **identical** → skip to A6.
- If **differs** → for each file that needs a per-machine tweak:
  1. Rename it to add a `.tmpl` suffix, e.g.:
     ```bash
     mv "$(chezmoi source-path)/private_dot_claude/settings.json" \
        "$(chezmoi source-path)/private_dot_claude/settings.json.tmpl"
     ```
  2. Ask the user what the actual per-machine difference should be, and what
     hostnames it applies to.
  3. Edit the file with `chezmoi edit ~/.claude/<file>` and wrap the differing
     section in a template conditional, e.g.:
     ```
     {{- if eq .chezmoi.hostname "work-laptop" }}
     // work-specific override
     {{- end }}
     ```

### A6. Commit and push

Show the user `git status`/`git diff` inside `$(chezmoi source-path)` and get
confirmation, then:
```bash
cd "$(chezmoi source-path)"
git add -A
git commit -m "initial claude code config"
git push -u origin main
```

### A7. Set up MCP servers and secrets (outside git)

Ask the user:

> "Do you use any MCP servers with Claude Code that need setting up on every
> machine? If so, what are they, and where should each machine pull its secrets
> from (an existing env var, a password-manager CLI, something else)?"

Based on the answer, create a `run_once_setup-mcp.sh.tmpl` script in the chezmoi
source directory that calls `claude mcp add ...` for each server, referencing
`${ENV_VAR}`-style lookups for secrets rather than literal values. Walk the user
through the exact `claude mcp add` invocations rather than guessing server names
or flags. chezmoi runs any `run_once_*` script automatically on `chezmoi apply`.

Commit this script (it contains no secrets, only references to where to find them)
and push:
```bash
cd "$(chezmoi source-path)"
git add -A
git commit -m "add mcp setup script"
git push
```

Tell the user setup is complete on this machine, and that Part B is what they'll
run on each additional machine.

---

## Part B: Adding another machine

### B1. Check for chezmoi

Same as A1 — check, and only install with confirmation.

### B2. Get the repo URL

Ask the user for the git remote URL of their existing dotfiles repo (or confirm
it's the same one from a prior setup in this conversation).

### B3. Preview before applying

First do a dry-run so nothing is silently overwritten:
```bash
chezmoi init <URL>
chezmoi diff
```

Show the user the diff. If `~/.claude/` already has content on this machine that
would be overwritten, ask:

> "This machine already has some Claude config that differs from your repo. Want
> me to back up the current `~/.claude/` first (e.g. copy it to
> `~/.claude.bak-<date>`), or overwrite it?"

Back up if requested:
```bash
cp -r ~/.claude ~/.claude.bak-$(date +%Y%m%d)
```

### B4. Apply

Once confirmed:
```bash
chezmoi apply
```
This renders any `.tmpl` files using this machine's own hostname/facts and writes
the real files into `~/.claude/`. Any `run_once_*` MCP setup script fires
automatically here.

### B5. Handle secrets for this machine

If the MCP run_once script expects environment variables or a password-manager
lookup, ask the user:

> "The MCP setup script expects [list the env vars/lookups it needs]. Are those
> already available on this machine, or do you need to set them up first?"

Help them set the needed env vars (e.g. in `~/.bashrc`/`~/.profile`) before
re-running the script if it failed due to missing secrets.

### B6. Verify

```bash
claude mcp list
cat ~/.claude/settings.json
```
Confirm with the user that things look right.

---

## Ongoing updates (either machine, after initial setup)

- Edit: `chezmoi edit ~/.claude/<file>` (or edit files directly in
  `$(chezmoi source-path)`).
- Preview: `chezmoi diff`.
- Apply locally: `chezmoi apply`.
- Push: `git -C "$(chezmoi source-path)" add -A && git -C "$(chezmoi source-path)" commit -m "<message>" && git -C "$(chezmoi source-path)" push`.
- Pull + apply on another machine in one step: `chezmoi update`.

Always show the user the diff and get confirmation before `chezmoi apply` or
`git push` when making ongoing changes, same as during initial setup.
