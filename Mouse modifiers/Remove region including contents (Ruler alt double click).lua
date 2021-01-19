--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Mouse modifier to remove a region including contents.
]]
reaper.Undo_BeginBlock()

-- Get mouse cursor position
reaper.PreventUIRefresh(1)
local cursor_pos = reaper.GetCursorPosition()
-- View: Move edit cursor to mouse cursor (no snapping)
reaper.Main_OnCommand(40514, 0)
local mouse_pos = reaper.GetCursorPosition()
reaper.SetEditCurPos2(0, cursor_pos, false, false)
reaper.PreventUIRefresh(-1)

if reaper.Undo_CanUndo2(0) == 'Remove time selection' then
    reaper.Undo_DoUndo2(0)
end

if reaper.Undo_CanUndo2(0) == 'Remove region' then
    reaper.Undo_DoUndo2(0)
    local _, regionidx = reaper.GetLastMarkerAndCurRegion(0, mouse_pos)
    if regionidx >= 0 then
        local ret, _, start_pos, end_pos = reaper.EnumProjectMarkers3(0, regionidx)
        reaper.GetSet_LoopTimeRange(true, true, start_pos, end_pos, false)
        -- Time selection: Remove contents of time selection (moving later items)
        reaper.Main_OnCommand(40201, 0)
    end
else
    -- Time selection: Remove time selection and loop points
    reaper.Main_OnCommand(40020, 0)
end

reaper.Undo_EndBlock('Remove region (and contents) under mouse', -1)
