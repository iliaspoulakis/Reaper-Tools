--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.8.4
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
  @changelog
    - Enforce grid limits of minimum 1/4096 and maximum 4096
]]
