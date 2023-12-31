--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.7.0
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
  @changelog
    - Added new swing menu
    - Triplet is now a toggle
    - Added support for Gridbox
    - Reduced CPU usage for adaptive MIDI grid
    - Opening menu doesn't change window focus (requires JS_ReaScriptAPI)
    - Fixed "Adjust adaptive grid (mousewheel)" script not switching to Widest
]]
