# Fish Config Development

This directory contains Fish shell configuration managed with chezmoi.

## Editing Guidelines

- Keep Fish functions in `functions/<name>.fish`, with the file name matching the primary function name.
- Prefer existing local patterns from nearby files before introducing new structure.
- Shortcut and key binding changes, including `ctrl-t` style bindings, must be updated in `functions/keys.fish`.
- Do not move shortcut behavior into ad hoc files unless the user explicitly asks for a larger key binding refactor.

## Visual guidelines

- Error messages should be prefixed with emoji 🚫
- Usage instructions coming from missing arguments are not considered as error and should not have error emoji
- When a command completes successfully it should print the message with emoji 🏆
- Any helper function for git should have their description starting with emoji 🔀

## Verification

- Verify every changed Fish file with `fish --no-execute`.
- Example: `fish --no-execute functions/cpath.fish`.
- When multiple Fish files are changed, check each one explicitly before finishing.

## Chezmoi

- Add newly generated files to chezmoi with `chezmoi add <path>`.
- Leave modified existing files for the user to manage unless they explicitly ask you to run `chezmoi add` for them.
- Do not run broad chezmoi operations when a targeted `chezmoi add <path>` is sufficient.

## Tool dependencies

- All scripts depending on certain functionality such as tsp should abort immediately if tool is not installed.
- If tool has a dependency that could be considered optional downgrade gracefully. 
  Example would be notifications which depend on tmux being installed for toast messages.