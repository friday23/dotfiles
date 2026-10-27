# Home lab dotfiles and package setup (chezmoi)

One git repo, managed by chezmoi, holding dotfiles, package lists and the
scripts that install them on Ubuntu/Debian. No enterprise tooling, only
chezmoi, bash and a few small tools.

## Install from this archive

The archive has a single top-level directory named `chezmoi`, so extracting
into `~/.local/share` puts every file in chezmoi's default source directory
(`~/.local/share/chezmoi`) and cannot spill files into the current directory.

    mkdir -p ~/.local/share
    tar -xzf chezmoi-homelab-setup.tar.gz -C ~/.local/share
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply

`init` with no repository argument uses the existing source directory. If
`~/.local/share/chezmoi` already exists, the extraction merges into it, so
back it up first. To keep this as a repo:

    cd ~/.local/share/chezmoi
    git init && git add -A && git commit -m "initial setup"
    git remote add origin git@github.com:YOU/dotfiles.git
    git push -u origin main

`-b "$HOME/.local/bin"` installs the chezmoi binary there. Without it the script
drops chezmoi into `./bin` of the current directory, which is not on your PATH.
After the first apply, open a new shell (or run
`export PATH="$HOME/.local/bin:$PATH"`) so `chezmoi` is found. Update it later
with `chezmoi upgrade`.

## Bootstrap a new machine from the git repo

    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply YOUR_GITHUB_USER

For a private repo use SSH: git@github.com:YOU/dotfiles.git

You are prompted once for machine role (desktop/server/minimal), git name
and git email. After the first apply:

1. Run `gh auth login` and `claude` once to authenticate.
2. If you use Vaultwarden for secrets:

        bw config server https://vw.cape21.org
        bw login
        export BW_SESSION="$(bw unlock --raw)"
        chezmoi apply

   Files that need secrets are skipped until `bw` is installed and unlocked,
   so the second apply fills them in.

## How it works

- `.chezmoidata/packages.yaml` is the single source of truth for apt packages,
  uv tools, uv Python versions and flatpaks.
- Scripts in `.chezmoiscripts/` use the `run_onchange_` prefix. chezmoi
  re-runs one only when its rendered content changes, so editing a package
  list (or the mise config or Neovim lockfile, which are hashed into the
  scripts) triggers the matching install.
- Order: before_10 (apt repos) -> before_20 (apt packages) -> dotfiles written
  -> after_30 (uv, Claude Code, mise, uv tools) -> after_40 (ghostty)
  -> after_45 (espanso, desktop only) -> after_50 (Neovim plugins and parsers).
- mise (`dot_config/mise/config.toml`) manages node, neovim, zellij, the
  Bitwarden CLI, the Node-based language servers, tree-sitter, fzf, lazygit
  and starship.

## Shell tools and espanso

| Tool | Installed by | Notes |
|---|---|---|
| ripgrep (`rg`), fd (`fdfind`), jq | apt (`packages.yaml`) | `fd` is aliased to `fdfind` in `.bashrc` |
| fzf, lazygit, starship | mise | latest releases, user-space |
| espanso | official .deb (desktop role only) | see below |

`.bashrc` wires these up: starship is initialised last; fzf gives Ctrl-R
(history), Ctrl-T (files) and Alt-C (directories), using `fdfind` for listing;
`lg` runs lazygit. The prompt config is `dot_config/starship.toml` (directory,
git, python/uv, command duration; no Nerd Font needed).

**espanso** is installed by `.chezmoiscripts/run_onchange_after_45-espanso.sh.tmpl`
from the official .deb for the session type set in `packages.yaml`
(`espanso.session: x11` or `wayland`; check with `echo $XDG_SESSION_TYPE`). The
.deb needs Debian 12+ or Ubuntu 23.04+ and an amd64 machine. If you switch
between X11 and Wayland, change that value, remove espanso
(`sudo apt remove espanso`) and re-apply. The script registers the systemd user
service and starts it only when a desktop session is running; otherwise run
`espanso start` from your desktop. To upgrade, download the new .deb and run
`sudo apt install ./espanso-debian-x11-amd64.deb`. Track your snippets with
`chezmoi add ~/.config/espanso` (don't put secrets in match files).

## Files you add yourself

These are your own configs, so they are not included here. Add them selectively:

    chezmoi add ~/.config/ghostty/config
    chezmoi add ~/.config/zellij/config.kdl
    chezmoi add ~/.claude/CLAUDE.md
    chezmoi add ~/.claude/settings.json
    chezmoi add ~/.claude/commands
    chezmoi add ~/.ssh/config

Do NOT run `chezmoi add ~/.claude` or `chezmoi add ~/.config/gh/hosts.yml`.
They contain credentials, history and caches. `~/.bashrc` here is a minimal
starter. If you already have one, run `chezmoi add ~/.bashrc` instead and
append the PATH, mise and uv lines from `dot_bashrc.tmpl`.

The first time you run Neovim it creates `lazy-lock.json`. Run
`chezmoi add ~/.config/nvim/lazy-lock.json` so plugin versions are pinned, and
`chezmoi re-add` after later plugin updates.

## Day to day

    chezmoi edit ~/.bashrc      # edit a managed file
    chezmoi re-add              # capture edits made directly in $HOME
    chezmoi diff                # preview
    chezmoi apply               # apply
    chezmoi update              # pull the repo and apply
    pkg-drift                   # list apt/uv packages not recorded in packages.yaml

## Python with uv

Per project: `uv init`, `uv add`, `uv run`, commit `pyproject.toml` and
`uv.lock`; on another machine `uv sync` recreates the environment.

For basedpyright to find the project environment either start the editor with
`uv run nvim .` or add this to pyproject.toml:

    [tool.basedpyright]
    venvPath = "."
    venv = ".venv"

## Notes

- Ghostty has no official apt package. `.chezmoiscripts/run_onchange_after_40-ghostty.sh.tmpl`
  is a reminder hook; add your preferred install source there.
- Ghostty sets TERM=xterm-ghostty, which servers may not know. Fix a host with:

        infocmp -x xterm-ghostty | ssh YOUR_SERVER -- tic -x -

- Neovim needs 0.11+ and nvim-treesitter's `main` branch needs the tree-sitter
  CLI (0.26.1+) and a C compiler. The CLI comes from mise's `tree-sitter`
  entry (official release binary), not the npm package. If a mise tool name
  stops resolving, check `mise registry | grep <name>`.
- Treesitter parser install fails with `spawn ... tree-sitter ENOENT`? The CLI
  binary is missing. Run `mise install`, check `tree-sitter --version`, then:
  `nvim --headless -c "lua require('nvim-treesitter').install(require('langs')):wait(300000)" -c qa`
- Docker is optional: set `docker: true` in packages.yaml. On Ubuntu
  derivatives (Mint etc.) the Docker repo codename may need to be
  `ubuntuCodename` instead of `versionCodename`.
- Test the bootstrap in a throwaway VM or container before trusting it on real
  hardware.
