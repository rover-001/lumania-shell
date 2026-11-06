-- =============================================================================
-- LUMANIA SHELL HYPRLAND INTEGRATION (PURE LUA CONFIGURATION)
-- =============================================================================
-- Following Omarchy standard: strictly .lua configuration (no .conf files).
--
-- Keybindings and window rules for Lumania Shell.
-- This file is kept in ~/.config/hypr/lumania.lua and loaded from hyprland.lua:
--   require("hypr.lumania")
-- =============================================================================

-- Search Notch (Super + Space)
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Lumania Search", "lumania-search")

hl.unbind("SUPER + SHIFT + RETURN")
o.bind("SUPER + SHIFT + RETURN", "Lumania Search", "lumania-search")

hl.unbind("SUPER + SHIFT + SPACE")
o.bind("SUPER + SHIFT + SPACE", "Lumania Search", "lumania-search")

-- Wallpaper Selector (Super + Ctrl + Space)
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Lumania Wallpaper", "lumania-wallpaper")

-- Control Center Toggle (Super + C)
o.bind("SUPER + C", "Lumania Control Center", "omarchy-shell lumania.control toggle")

-- Luma AI Desktop Assistant (Super + M)
hl.unbind("SUPER + M")
o.bind("SUPER + M", "Luma AI Assistant", "luma --toggle")

-- Settings Companion App Window Rule
o.window({ class = "lumania-settings" }, { float = true, size = "780 580", center = true })
