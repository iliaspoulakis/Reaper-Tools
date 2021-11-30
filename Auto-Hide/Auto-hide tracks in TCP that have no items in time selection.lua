--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Hides tracks in the TCP that have no items in the time selection
]]

local extname = 'FTC.AutoHideSelTCP'
local GetTrackInfoValue = reaper.GetMediaTrackInfo_Value
local SetTrackInfoValue = reaper.SetMediaTrackInfo_Value

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local track_guid = reaper.GetTrackGUID(track)

        local visible = GetTrackInfoValue(track, 'B_SHOWINTCP')
        local compact = GetTrackInfoValue(track, 'I_FOLDERCOMPACT')

        local state = ('%s:%d:%d'):format(track_guid, visible, compact)
        states[#states + 1] = state
    end
    local states_str = table.concat(states, ';')
    reaper.SetProjExtState(0, extname, 'track_states', states_str)
end

function RestoreTracksVisibilityState()
    -- Restore track states
    local _, states_str = reaper.GetProjExtState(0, extname, 'track_states')
    if states_str == '' then return end

    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local track_guid = reaper.GetTrackGUID(track)
        track_guid = track_guid:gsub('%-', '%%-')

        local visible, compact = states_str:match(track_guid .. ':(%d):(%d)')
        if visible then
            SetTrackInfoValue(track, 'B_SHOWINTCP', tonumber(visible))
            SetTrackInfoValue(track, 'I_FOLDERCOMPACT', tonumber(compact))
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
end

function HasItemsInArea(track, area_start_pos, area_end_pos)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local end_pos = start_pos + length

        if start_pos > area_end_pos then break end
        if start_pos <= area_end_pos and end_pos >= area_start_pos then
            return true
        end
    end
end

local prev_start_pos
local prev_end_pos
local is_prev_sel_valid

function Main()

    local GetTimeSelection = reaper.GetSet_LoopTimeRange
    local start_pos, end_pos = GetTimeSelection(false, true, 0, 0, false)

    if prev_start_pos ~= start_pos or prev_end_pos ~= end_pos then

        prev_start_pos = start_pos
        prev_end_pos = end_pos

        local is_sel_valid = end_pos > 0 and start_pos ~= end_pos

        if not is_sel_valid then
            RestoreTracksVisibilityState()
        else
            if is_prev_sel_valid ~= is_sel_valid then
                SaveTracksVisibilityState()
            end
            for t = 0, reaper.CountTracks(0) - 1 do
                local track = reaper.GetTrack(0, t)
                local is_visible = HasItemsInArea(track, start_pos, end_pos)
                SetTrackInfoValue(track, 'B_SHOWINTCP', is_visible and 1 or 0)
            end
        end
        is_prev_sel_valid = is_sel_valid

        reaper.TrackList_AdjustWindows(false)
    end

    reaper.defer(Main)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    RestoreTracksVisibilityState()
    reaper.TrackList_AdjustWindows(false)
end

reaper.atexit(Exit)
reaper.defer(Main)
