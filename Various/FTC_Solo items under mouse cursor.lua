--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Additively soloes the items under the mouse cursor
]]
reaper.Undo_BeginBlock()
local sel_item_cnt = reaper.CountSelectedMediaItems(0)
-- Item: Select item under mouse cursor (leaving other items selected)
reaper.Main_OnCommand(40529, 0)

if sel_item_cnt ~= reaper.CountSelectedMediaItems(0) then
    -- Item properties: Solo
    reaper.Main_OnCommand(41559, 0)
else
    -- Item properties: Unsolo all
    reaper.Main_OnCommand(41185, 0)
    -- Item: Unselect all items
    reaper.Main_OnCommand(40289, 0)
end
reaper.Undo_EndBlock('Solo items under mouse cursor', -1)
