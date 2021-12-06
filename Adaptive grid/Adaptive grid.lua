--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [main=main,midi_editor] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
  @changelog
    - Added menu option for 1/64 & 1/128
    - Add user defined grid size limits
    - Ignore arrange view when MIDI editor grid is synced
    - Various optimizations to make background service super lightweight
]]
