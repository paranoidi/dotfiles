local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local act = wezterm.action

config.colors = {
  foreground = "#d3d7cf",
  background = "#232528",
  ansi = {
    "#2e3436", "#e66666", "#a2bd68", "#f0c674",
    "#6485ab", "#b294bb", "#8abeb7", "#d3d7cf",
  },
  brights = {
    "#555753", "#d54e53", "#9ad949", "#e7c547",
    "#7baae0", "#c397d8", "#70c0b1", "#eeeeec",
  },
}

config.enable_tab_bar = false
config.use_resize_increments = true
config.font = wezterm.font("FiraCode Nerd Font")
config.harfbuzz_features = {'calt=0', 'clig=0', 'liga=0'}
config.font_size = 13.0

config.keys = {
  -- suppress fullscreen toggle so tmux gets M-Enter
  { key = 'Return', mods = 'ALT', action = act.DisableDefaultAssignment },
}

config.mouse_bindings = {
  -- Ctrl+click drag = block selection
  { event = { Down = { streak = 1, button = 'Left' } },   mods = 'CTRL',     action = act.SelectTextAtMouseCursor 'Block' },
  { event = { Drag = { streak = 1, button = 'Left' } },   mods = 'CTRL',     action = act.ExtendSelectionToMouseCursor 'Block' },
  { event = { Up   = { streak = 1, button = 'Left' } },   mods = 'CTRL',     action = act.CompleteSelection 'ClipboardAndPrimarySelection' },

  -- defaults
  { event = { Down = { streak = 1, button = 'Left' } },   mods = 'NONE',     action = act.SelectTextAtMouseCursor 'Cell' },
  { event = { Down = { streak = 2, button = 'Left' } },   mods = 'NONE',     action = act.SelectTextAtMouseCursor 'Word' },
  { event = { Down = { streak = 3, button = 'Left' } },   mods = 'NONE',     action = act.SelectTextAtMouseCursor 'Line' },
  { event = { Drag = { streak = 1, button = 'Left' } },   mods = 'NONE',     action = act.ExtendSelectionToMouseCursor 'Cell' },
  { event = { Drag = { streak = 2, button = 'Left' } },   mods = 'NONE',     action = act.ExtendSelectionToMouseCursor 'Word' },
  { event = { Drag = { streak = 3, button = 'Left' } },   mods = 'NONE',     action = act.ExtendSelectionToMouseCursor 'Line' },
  { event = { Up   = { streak = 1, button = 'Left' } },   mods = 'NONE',     action = act.CompleteSelectionOrOpenLinkAtMouseCursor 'ClipboardAndPrimarySelection' },
  { event = { Up   = { streak = 2, button = 'Left' } },   mods = 'NONE',     action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
  { event = { Up   = { streak = 3, button = 'Left' } },   mods = 'NONE',     action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
  { event = { Down = { streak = 1, button = 'Middle' } }, mods = 'NONE',     action = act.PasteFrom 'PrimarySelection' },
  { event = { Down = { streak = 1, button = 'Left' } },   mods = 'CTRL|SHIFT', action = act.OpenLinkAtMouseCursor },
  { event = { Drag = { streak = 1, button = 'Left' } },   mods = 'CTRL|SHIFT', action = act.StartWindowDrag },
  { event = { Drag = { streak = 1, button = 'Left' } },   mods = 'SUPER',      action = act.StartWindowDrag },
}

return config
