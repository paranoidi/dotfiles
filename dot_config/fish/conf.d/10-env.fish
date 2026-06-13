# Global shell defaults.
set -g fish_greeting
set -g man_standout -b 222226 ffff00

set -Ux LANG en_US.UTF-8
set -Ux LC_ALL en_US.UTF-8

set -Ux EDITOR hx
set -Ux VISUAL hx
set -Ux GIT_EDITOR hx

set -x EZA_THEME ~/.config/eza/theme.yml
set -x BAT_THEME ansi

set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME ~/.config
