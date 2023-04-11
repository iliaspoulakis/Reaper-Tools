--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.6.0
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
  @changelog
    - Menu toolbar button state now indicates whether an adaptive mode is active
    - Reworked toolbar button states (click each button once if state isn't reflected correctly)
]]
