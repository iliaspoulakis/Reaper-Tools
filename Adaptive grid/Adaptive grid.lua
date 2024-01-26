--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.8.0
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
  @changelog
    - Support frame and measure grid divisions
    - Added options to show frame and measure grid divisions in menu (Options > Show in menu)
    - Swing with 0% is now detected as straight grid
]]
