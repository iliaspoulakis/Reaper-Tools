--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.7.2
  @about A fully featured adaptive grid tool for REAPER
  @metapackage
  @provides
    [main=main,midi_editor] Adaptive grid menu.lua
    [nomain] Adaptive grid (background service).lua
    [nomain] Adapt grid to zoom level.lua
    [main=main,midi_editor] Set grid to * (adaptive).lua
    [main=main,midi_editor] Adjust adaptive grid (mousewheel).lua
  @changelog
    - Adjust grid via mousewheel script now also respect grid limits when
      scrolling through fixed grid divisions (adaptive turned off)
]]
