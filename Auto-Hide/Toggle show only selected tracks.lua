--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about Temporarily show only specific selected tracks
  @changelog
    - Improve scroll to track behavior when exiting enabled state
    - Do not set tracks visible that were created and hidden in enabled state
]]

local extname = 'FTC.ToggleShowOnlySelTracks'
local _, _, sec, cmd = reaper.get_action_context()

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

local GetTrackInfo = reaper.GetMediaTrackInfo_Value
local SetTrackInfo = reaper.SetMediaTrackInfo_Value

local mixer_scroll_track

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)

        local show_tcp = GetTrackInfo(track, 'B_SHOWINTCP')
        local show_mcp = GetTrackInfo(track, 'B_SHOWINMIXER')

        local comp = 0
        local is_folder = GetTrackInfo(track, 'I_FOLDERDEPTH') == 1
        if is_folder and GetTrackInfo(track, 'I_SELECTED') == 0 then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            comp = chunk:match('\nBUSCOMP %d+ (%d+)')
            -- Expand folders in mixer
            if comp == '1' then
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end

        local state = ('%s:%d:%d:%d'):format(guid, show_tcp, show_mcp, comp)
        states[#states + 1] = state
    end
    local states_str = table.concat(states, ';')
    reaper.SetProjExtState(0, extname, 'track_states', states_str)

    local track = reaper.GetMixerScroll()
    local scroll_guid = track and reaper.GetTrackGUID(track) or ''
    reaper.SetProjExtState(0, extname, 'mixer_scroll_guid', scroll_guid)
end

function RestoreTracksVisibilityState(states_str)
    local _, scroll_guid = reaper.GetProjExtState(0, extname, 'mixer_scroll_guid')
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)
        local pattern = guid:gsub('%-', '%%-') .. ':(%d):(%d):(%d)'

        local show_tcp, show_mcp, comp = states_str:match(pattern)
        if show_tcp and show_mcp and comp then
            SetTrackInfo(track, 'B_SHOWINTCP', tonumber(show_tcp) or 1)
            SetTrackInfo(track, 'B_SHOWINMIXER', tonumber(show_mcp) or 1)

            if comp == '1' then
                local _, chunk = reaper.GetTrackStateChunk(track, '')
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end

        if guid == scroll_guid then mixer_scroll_track = track end
    end
end

local sel_track_cnt = reaper.CountSelectedTracks(0)

-- Restore track states
local _, states_str = reaper.GetProjExtState(0, extname, 'track_states')
if states_str ~= '' then
    reaper.Undo_BeginBlock()
    RestoreTracksVisibilityState(states_str)
    reaper.SetProjExtState(0, extname, 'track_states', '')
    reaper.SetProjExtState(0, extname, 'mixer_scroll_guid', '')
    reaper.TrackList_AdjustWindows(false)

    for t = 0, sel_track_cnt - 1 do
        local track = reaper.GetSelectedTrack(0, t)
        if GetTrackInfo(track, 'B_SHOWINTCP') == 1 then
            -- Track: Vertical scroll selected tracks into view
            reaper.Main_OnCommand(40913, 0)
            break
        end
    end

    if mixer_scroll_track then reaper.SetMixerScroll(mixer_scroll_track) end

    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.Undo_EndBlock('Toggle show only selected tracks', -1)
    return
end

if sel_track_cnt == 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.defer(function() end)
    return
end

reaper.Undo_BeginBlock()
SaveTracksVisibilityState()
reaper.SetToggleCommandState(sec, cmd, 1)

-- Hide all tracks
for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    SetTrackInfo(track, 'B_SHOWINTCP', 0)
    SetTrackInfo(track, 'B_SHOWINMIXER', 0)
end

local function ShowChildTracks(folder_track)
    local idx = GetTrackInfo(folder_track, 'IP_TRACKNUMBER')
    local depth = GetTrackInfo(folder_track, 'I_FOLDERDEPTH')

    for t = idx, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        depth = depth + GetTrackInfo(track, 'I_FOLDERDEPTH')
        SetTrackInfo(track, 'B_SHOWINTCP', 1)
        SetTrackInfo(track, 'B_SHOWINMIXER', 1)
        if depth <= 0 then break end
    end
end

-- Show selected tracks (and child tracks)
for t = 0, sel_track_cnt - 1 do
    local track = reaper.GetSelectedTrack(0, t)
    SetTrackInfo(track, 'B_SHOWINTCP', 1)
    SetTrackInfo(track, 'B_SHOWINMIXER', 1)

    local is_folder = GetTrackInfo(track, 'I_FOLDERDEPTH') == 1
    if is_folder then ShowChildTracks(track) end
end

reaper.TrackList_AdjustWindows(false)

for t = 0, sel_track_cnt - 1 do
    local track = reaper.GetSelectedTrack(0, t)
    if GetTrackInfo(track, 'B_SHOWINTCP') == 1 then
        -- Track: Vertical scroll selected tracks into view
        reaper.Main_OnCommand(40913, 0)
        break
    end
end
reaper.Undo_EndBlock('Toggle show only selected tracks', -1)
