# Install contract

## Mode
`install.sh` accepts an install mode.

`make install` is the preferred entrypoint once `make` is available, but first bootstrap on a bare host may call:

```bash
bash ./scripts/install.sh
```

Current modes:
- `standalone`
- `overlay`

## Metadata
The current install writes metadata to:
- `~/.config/jhoya/state/install-metadata.json`

The metadata stores:
- `grade`
- `version`
- `repo`
- `mode`

## Transition rule
- If the currently installed `grade` or `version` does not match the target install,
  the installer runs the fixed-path current uninstall contract first and then
  continues with the new install.
- If both `grade` and `version` already match, the installer skips the cleanup step.

## Current uninstall contract
The current install writes an executable uninstall shim to:
- `~/.config/jhoya/bin/uninstall-current-install.sh`

Other installers may execute that shim before proceeding when grade/version policy requires cleanup.
