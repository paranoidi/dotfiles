# Global shell defaults.
set -g fish_greeting
set -g man_standout -b 222226 ffff00

set -Ux LANG en_US.UTF-8
set -gx LC_TIME en_DK.UTF-8

# -gx, not -Ux: a global overrides EDITOR inherited from a stale tmux server
# or a parent shell; a universal is shadowed by it.
set -gx EDITOR hx
set -gx VISUAL hx
set -gx GIT_EDITOR hx
set -e -U EDITOR VISUAL GIT_EDITOR 2>/dev/null

set -x EZA_THEME ~/.config/eza/theme.yml
set -x BAT_THEME ansi

set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME ~/.config
