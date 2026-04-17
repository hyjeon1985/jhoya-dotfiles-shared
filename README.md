# jhoya-dotfiles-shared

Public shared-base layer for the jhoya shell/tmux/font environment.

This repository owns the non-secret/common installation base that can be reused across environments without requiring access to any private overlay.

## Current scope
- shared install contract skeleton
- grade/version metadata contract
- current uninstall contract path
- shared required tool bootstrap
  - `make`, `bash`, `git`, `curl`, `jq`, `tmux`
  - `uv`, `uvx`
  - `bw`, `bws`
  - `starship`, `btop`, `gh`, `tombi`
- tmux catppuccin plugin bootstrap

## Install
```bash
make install
```

If `make` is not installed yet on a fresh host, bootstrap with:
```bash
bash ./scripts/install.sh
```

Optional mode/version override:
```bash
JHOYA_INSTALL_MODE=standalone JHOYA_INSTALL_VERSION=0.2.0 make install
```

Current modes:
- `standalone`
- `overlay`

## Doctor
```bash
make doctor
```

## Uninstall
```bash
make uninstall
```

## Operator utility: root home bridge
For unusual hosts where root logins evaluate startup files under `/root` while
the intended working home is elsewhere, an operator-only helper is available:

```bash
make root-home-bridge-status
make fix-root-home-bridge
make root-home-bridge-status
make remove-root-home-bridge
```

The helper inspects existing root bash login files in precedence order and only
patches a file that already appears to source `~/.bashrc`, or prefers
`/root/.bashrc` itself when that file already rewrites `HOME` away from `/root`.
It uses a managed block, updates cleanly, and never creates new login files. By
default it uses the current shell's `$HOME` as the target working home.

The installer always refreshes the fixed-path current uninstall contract at:
- `~/.config/jhoya/bin/uninstall-current-install.sh`

This shared base is bash-first on remote hosts. It keeps common shell assets,
tmux, fonts, templates, and shared tool bootstrap public while private zsh
support lives in the private overlay repository.
The installer manages `~/.bashrc` for bash shell startup and will create that
file if it is missing. For login shells it checks existing `~/.bash_profile`,
`~/.bash_login`, and `~/.profile` files: if one already sources `~/.bashrc` it
leaves it alone, otherwise it appends a managed `~/.bashrc` bridge block to
each existing file. If none of the three files exist, it creates
`~/.bash_profile` with the managed block.
