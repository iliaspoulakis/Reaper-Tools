--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Runs in the background and lets you change the order of layers using drag & drop
]]
if not reaper.JS_Window_FindChildByID then
    reaper.MB('Please install js_ReaScriptAPI extension', mb_title, 0)
    return
end

local main_window = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
local _, _, main_y = reaper.JS_Window_GetClientRect(main_window)

local last_edit_flags
local last_edit_source
local last_edit_item

local last_track_t, last_track_b
local last_item_t, last_item_b
local last_item_h

local transition_y = 0
local remeasure = false
local mouse_click_y

local debug = false

function print(msg)
    if debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
end

function GetTrackUnderMouse()
    reaper.PreventUIRefresh(1)
    -- Save track selection
    local sel_tracks = {}
    for i = reaper.CountSelectedTracks(0) - 1, 0, -1 do
        local track = reaper.GetSelectedTrack(0, i)
        sel_tracks[#sel_tracks + 1] = track
        reaper.SetTrackSelected(track, false)
    end

    -- Track: Select track under mouse
    reaper.Main_OnCommand(41110, 0)
    local mouse_track = reaper.GetSelectedTrack(0, 0)
    if mouse_track then
        reaper.SetTrackSelected(mouse_track, false)
    end
    -- Restore track selection
    for _, track in ipairs(sel_tracks) do
        reaper.SetTrackSelected(track, true)
    end
    reaper.PreventUIRefresh(-1)
    return mouse_track
end

function GetItemUnderMouse()
    reaper.PreventUIRefresh(1)
    reaper.Undo_BeginBlock()
    local sel_items = {}
    -- Save current item selection
    for i = reaper.CountSelectedMediaItems() - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        sel_items[i + 1] = item
        reaper.SetMediaItemSelected(item, false)
    end

    -- Track: Select item under mouse cursor
    reaper.Main_OnCommand(40528, 0)
    local mouse_item = reaper.GetSelectedMediaItem(0, 0)
    if mouse_item then
        reaper.SetMediaItemSelected(mouse_item, false)
    end

    -- Restore item selection
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.Undo_EndBlock('Undo point caused by moving item horizontally (bug)', 0)
    reaper.PreventUIRefresh(-1)
    return mouse_item
end

function MeasureBounds(item)
    local track = reaper.GetMediaItem_Track(item)
    local track_y = reaper.GetMediaTrackInfo_Value(track, 'I_TCPY')
    local track_h = reaper.GetMediaTrackInfo_Value(track, 'I_WNDH')
    local item_y = reaper.GetMediaItemInfo_Value(item, 'I_LASTY')
    local item_h = reaper.GetMediaItemInfo_Value(item, 'I_LASTH')
    last_track_t = main_y + track_y
    last_track_b = last_track_t + track_h
    last_item_t = last_track_t + item_y
    last_item_b = last_item_t + item_h
    last_item_h = last_item_b - last_item_t
    print('Measure: ' .. last_item_t .. ' ' .. last_item_b)
end

function GetItemIID(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    return tonumber(chunk:match('IID (%d+)\n'))
end

function SetItemIID(item, iid)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    if not tonumber(iid) then
        print('Error: Trying to set iid to ' .. tostring(iid))
        return
    end
    chunk = chunk:gsub('IID (%d+)\n', 'IID ' .. tonumber(iid) .. '\n')
    reaper.SetItemStateChunk(item, chunk, true)
end

function PrintTrackIIDs(track)
    print('Item IIDs:')
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        print(GetItemIID(item))
    end
end

function FixTrackIIDs(track)
    for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item ~= last_edit_item then
            local iid = GetItemIID(item)
            SetItemIID(item, iid + i * 2)
        end
    end
end

function FixItemTrackIIDs(drag_item)
    reaper.Undo_BeginBlock()
    local track = reaper.GetMediaItem_Track(drag_item)
    local drag_item_offset = 2
    for i = reaper.CountTrackMediaItems(track) - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if item ~= drag_item then
            local iid = GetItemIID(item)
            SetItemIID(item, iid + i * 2 + drag_item_offset)
        else
            drag_item_offset = 0
        end
    end
    reaper.Undo_EndBlock('Prepare track for lanes changes (bugfix?)', -1)
end

function Main()
    local _, _, edit_flags = reaper.GetItemEditingTime2()
    if edit_flags ~= 0 and last_edit_flags == 0 then
        print('Drag!')
        last_edit_item = GetItemUnderMouse()
        if last_edit_item then
            MeasureBounds(last_edit_item)
            FixItemTrackIIDs(last_edit_item)
        end
    end

    if remeasure and last_edit_item then
        MeasureBounds(last_edit_item)
        remeasure = false
    end

    if edit_flags == 4 then
        local mouse_y = select(2, reaper.GetMousePosition())
        local is_within_track = mouse_y > last_track_t and mouse_y < last_track_b
        if not is_within_track and last_edit_item then
            print('Track changed...')
            MeasureBounds(last_edit_item)
            FixItemTrackIIDs(last_edit_item)
        end

        local is_transition = math.abs(mouse_y - transition_y) < last_item_h / 5
        local is_above_item = mouse_y < last_item_t

        if not is_transition and is_above_item then
            print('Up: ' .. mouse_y .. ' | ' .. last_item_t .. ' ' .. last_item_b)
            -- Item lanes: Move item up one lane (when showing overlapping items in lanes)
            reaper.Main_OnCommand(40068, 0)
            transition_y = mouse_y
            remeasure = true
        end
        local is_below_item = mouse_y > last_item_b
        if not is_transition and is_below_item then
            print('Down: ' .. mouse_y .. ' | ' .. last_item_t .. ' ' .. last_item_b)
            -- Item lanes: Move item down one lane (when showing overlapping items in lanes)
            reaper.Main_OnCommand(40107, 0)
            transition_y = mouse_y
            remeasure = true
        end
        reaper.Undo_EndBlock('Change item lane', -1)
    end

    if edit_flags == 0 and last_edit_flags ~= 0 then
        print('Drop!')
    end

    last_edit_flags = edit_flags
    reaper.defer(Main)
end

reaper.defer(Main)
