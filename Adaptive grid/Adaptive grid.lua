--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 2.0.6
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
    [main=main,midi_editor] Adjust fixed grid *.lua
  @changelog
    - Fix MIDI editor grid limits
    - Fix MIDI editor grid not reacting to certain zoom levels (2.0.5 regression)
]]
