--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Hides silent tracks from MCP during playback
]]

local peak_threshold = 0.001
local release_time = 75

local extname = 'FTC.AutoHideMCP'
local GetTrackInfoValue = reaper.GetMediaTrackInfo_Value
local SetTrackInfoValue = reaper.SetMediaTrackInfo_Value

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local track_guid = reaper.GetTrackGUID(track)

        local visible = GetTrackInfoValue(track, 'B_SHOWINMIXER')

        local bus_comp = 0
        local is_folder = GetTrackInfoValue(track, 'I_FOLDERDEPTH') == 1
        if is_folder then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            bus_comp = chunk:match('\nBUSCOMP %d+ (%d+)')

            if bus_comp == '1' then
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end

        local state = ('%s:%d:%d'):format(track_guid, visible, bus_comp)
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

        local visible, bus_comp = states_str:match(track_guid .. ':(%d):(%d)')
        if visible then
            SetTrackInfoValue(track, 'B_SHOWINMIXER', tonumber(visible))
            if bus_comp == '1' then
                local _, chunk = reaper.GetTrackStateChunk(track, '')
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
end

local prev_play_state
local timers = {}

function Main()

    local is_update = false
    local track_cnt = reaper.CountTracks(0)
    local play_state = reaper.GetPlayState()

    if play_state ~= prev_play_state then
        prev_play_state = play_state

        -- Reset timers
        timers = {}
        for t = 1, track_cnt do timers[t] = 0 end

        -- Save/Restore tracks visibility
        if play_state == 0 then
            RestoreTracksVisibilityState()
            reaper.TrackList_AdjustWindows(false)
            reaper.defer(Main)
            return
        else
            SaveTracksVisibilityState()
            is_update = true
        end

    end

    -- Count down timers
    for t = 1, track_cnt do
        if timers[t] > 0 then timers[t] = timers[t] - 1 end
    end

    if play_state == 0 then
        reaper.defer(Main)
        return
    end

    local x, y = reaper.GetMousePosition()
    local _, hover = reaper.GetThingFromPoint(x, y)
    if hover == 'mcp.volume' then
        reaper.defer(Main)
        return
    end

    for t = 1, track_cnt do
        local track = reaper.GetTrack(0, t - 1)
        local peak_l = reaper.Track_GetPeakInfo(track, 0)
        local peak_r = reaper.Track_GetPeakInfo(track, 1)
        local peak = math.max(peak_l, peak_r)

        if peak > peak_threshold then
            if timers[t] == 0 then is_update = true end
            timers[t] = release_time
        end

        local is_visible = timers[t] > 0
        SetTrackInfoValue(track, 'B_SHOWINMIXER', is_visible and 1 or 0)
    end

    if is_update then reaper.TrackList_AdjustWindows(false) end

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
