--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @about Runs in the background and lets you change the order of layers using drag & drop
  @changelog
    - Added toggle state for toolbars
    - Removed workaround for IIDs due to reaper bugfix
]]
local debug = false

if not reaper.JS_Window_FindChildByID then
    reaper.MB('Please install js_ReaScriptAPI extension', mb_title, 0)
    return
end

local main_window = reaper.JS_Window_FindChildByID(reaper.GetMainHwnd(), 1000)
local _, _, main_y = reaper.JS_Window_GetClientRect(main_window)

-- View: Toggle displaying labels above/within media items
local label_height = reaper.GetToggleCommandState(40258) == 1 and 15 or 0

local remeasure = false
local last_edit_flags = 0

local last_track_t, last_track_b
local last_item_t, last_item_b

local last_item_h, last_item_y
local last_item

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
    local sel_items = {}
    -- Save current item selection
    for i = reaper.CountSelectedMediaItems() - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        sel_items[i + 1] = item
        reaper.SetMediaItemSelected(item, false)
    end

    -- Track: Select item under mouse cursor
    reaper.Main_OnCommand(40528, 0)
    local sel_item_cnt = reaper.CountSelectedMediaItems(0)

    -- Get last selected item as its start pos will be closer to the mouse cursor
    local mouse_item = reaper.GetSelectedMediaItem(0, sel_item_cnt - 1)

    -- If the item was previously selected it has priority
    for i = 0, sel_item_cnt - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        for _, sel_item in ipairs(sel_items) do
            if item == sel_item then
                mouse_item = sel_item
                break
                break
            end
        end
    end
    reaper.SelectAllMediaItems(0, false)
    -- Restore item selection
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.PreventUIRefresh(-1)
    return mouse_item
end

function MeasureBounds(item)
    local track = reaper.GetMediaItem_Track(item)
    local track_y = reaper.GetMediaTrackInfo_Value(track, 'I_TCPY')
    local track_h = reaper.GetMediaTrackInfo_Value(track, 'I_WNDH')
    last_item_y = reaper.GetMediaItemInfo_Value(item, 'I_LASTY')
    last_item_h = reaper.GetMediaItemInfo_Value(item, 'I_LASTH')
    last_track_t = main_y + track_y
    last_track_b = last_track_t + track_h
    last_item_t = last_track_t + last_item_y
    last_item_b = last_item_t + last_item_h
    print('Measure: ' .. last_item_b - last_item_t)
    label_height = reaper.GetToggleCommandState(40258) == 1 and 15 or 0
end

function GetItemIID(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    return tonumber(chunk:match('IID (%d+)\n')) or 0
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

function Main()
    local _, _, edit_flags = reaper.GetItemEditingTime2()
    if edit_flags ~= 0 and last_edit_flags == 0 then
        print('Drag!')
        last_item = GetItemUnderMouse()
        if last_item then
            MeasureBounds(last_item)
        end
    end

    if remeasure and last_item then
        MeasureBounds(last_item)
        remeasure = false
    end

    if edit_flags == 4 and last_item then
        local item_y = reaper.GetMediaItemInfo_Value(last_item, 'I_LASTY')
        local item_h = reaper.GetMediaItemInfo_Value(last_item, 'I_LASTH')
        if item_y ~= last_item_y or item_h ~= last_item_h then
            print('Item height changed...')
            MeasureBounds(last_item)
        end
        local mouse_y = select(2, reaper.GetMousePosition())
        local is_within_track = mouse_y >= last_track_t and mouse_y < last_track_b
        if not is_within_track and last_item then
            if not GetTrackUnderMouse() then
                print('No track under mouse')
                reaper.defer(Main)
                return
            end
            print('Track changed...')
            MeasureBounds(last_item)
        end

        local is_above_item = mouse_y < last_item_t - label_height
        if is_above_item then
            -- Avoid cursor being on the label of the first lane
            print('Up: ' .. mouse_y .. ' | ' .. last_item_t .. ' ' .. last_item_b)
            -- Item lanes: Move item up one lane (when showing overlapping items in lanes)
            reaper.Main_OnCommand(40068, 0)
            remeasure = true
        end

        local is_below_item = mouse_y > last_item_b + label_height
        if is_below_item then
            print('Down: ' .. mouse_y .. ' | ' .. last_item_t .. ' ' .. last_item_b)
            -- Item lanes: Move item down one lane (when showing overlapping items in lanes)
            reaper.Main_OnCommand(40107, 0)
            remeasure = true
        end
        reaper.Undo_EndBlock('Change item lane', -1)
    end

    if edit_flags == 0 and last_edit_flags ~= 0 then
        last_item = nil
        print('Drop!')
    end

    last_edit_flags = edit_flags
    reaper.defer(Main)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
end

reaper.defer(Main)
reaper.atexit(Exit)
