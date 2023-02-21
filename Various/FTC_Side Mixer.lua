--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.2
  @about Fix tracks not showing when exiting script
]]
-------------------------------- SETTINGS -----------------------------------

-- Screenset number
local screenset_default = 1
local screenset_sidemixer = 2

-- Layouts (optional)
local layout_default = 'Default'
local layout_default_master = 'Default'
local layout_sidemixer = 'SideMixer'
local layout_sidemixer_master = 'SideMixer'

-- Send region size (set to -1 to bypass)
local send_region_default = 0.25
local send_region_default_master = 0
local send_region_sidemixer = 0.25
local send_region_sidemixer_master = 0

-- Combined FX and sends region size (set to -1 to bypass)
local fx_send_default = 0.75
local fx_send_default_master = 0.75
local fx_send_sidemixer = 0.75
local fx_send_sidemixer_master = 0.75

--------------------------------------------------------------------------------

local extname = 'FTC.SideMixer'
local GetTrackInfo = reaper.GetMediaTrackInfo_Value
local SetTrackInfo = reaper.SetMediaTrackInfo_Value

function AdjustTracks()
    -- Set master send region scales
    local master = reaper.GetMasterTrack(0)
    if send_region_sidemixer_master >= 0 then
        SetTrackInfo(master, 'F_MCP_SENDRGN_SCALE',
            send_region_sidemixer_master)
    end
    if fx_send_sidemixer_master >= 0 then
        SetTrackInfo(master, 'F_MCP_FXSEND_SCALE', fx_send_sidemixer_master)
    end
    -- Hide Tracks
    local track_states = ''
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local track_guid = reaper.GetTrackGUID(track)

        local visible = tostring(GetTrackInfo(track, 'B_SHOWINMIXER'))
        visible = visible:gsub('(.)%..', '%1', 1)

        SetTrackInfo(track, 'B_SHOWINMIXER', 0)

        local _, chunk = reaper.GetTrackStateChunk(track, '')
        local _, e = chunk:find('\nBUSCOMP %d %d')
        local buscomp = chunk:sub(e, e)
        if buscomp == '1' then
            chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
            reaper.SetTrackStateChunk(track, chunk)
        end

        track_states = track_states .. track_guid .. visible .. buscomp .. '\n'

        -- Set track send region scales
        if send_region_sidemixer >= 0 then
            SetTrackInfo(track, 'F_MCP_SENDRGN_SCALE', send_region_sidemixer)
        end
        if fx_send_sidemixer >= 0 then
            SetTrackInfo(track, 'F_MCP_FXSEND_SCALE', fx_send_sidemixer)
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', track_states)
    reaper.TrackList_AdjustWindows(false)
end

function RestoreTracks()
    -- Set master send region scales
    local master = reaper.GetMasterTrack(0)
    if send_region_default_master >= 0 then
        SetTrackInfo(master, 'F_MCP_SENDRGN_SCALE',
            send_region_default_master)
    end
    if fx_send_default_master >= 0 then
        SetTrackInfo(master, 'F_MCP_FXSEND_SCALE', fx_send_default_master)
    end
    -- Restore track states
    local _, states = reaper.GetProjExtState(0, extname, 'track_states')
    if states ~= '' then
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local track_guid = reaper.GetTrackGUID(track)

            local _, guid_end = states:find(track_guid, 0, true)
            if guid_end then
                local visible = tonumber(states:sub(guid_end + 1,
                    guid_end + 1))
                if not visible then
                    visible = 1
                end
                SetTrackInfo(track, 'B_SHOWINMIXER', visible)

                local buscomp = states:sub(guid_end + 2, guid_end + 2)
                if buscomp == '1' then
                    local _, chunk = reaper.GetTrackStateChunk(track, '')
                    chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
                    reaper.SetTrackStateChunk(track, chunk)
                end
            else
                SetTrackInfo(track, 'B_SHOWINMIXER', 1)
            end
            -- Set track send region scales
            if send_region_default >= 0 then
                SetTrackInfo(track, 'F_MCP_SENDRGN_SCALE',
                    send_region_default)
            end
            if fx_send_default >= 0 then
                SetTrackInfo(track, 'F_MCP_FXSEND_SCALE', fx_send_default)
            end
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
    reaper.TrackList_AdjustWindows(false)
end

-- Select first track if no track selected
function FallBack()
    local sel_track = reaper.GetSelectedTrack(0, 0)
    if sel_track == nil and reaper.CountTracks(0) > 0 then
        sel_track = reaper.GetTrack(0, 0)
        reaper.SetCursorContext(0)
        reaper.SetTrackSelected(sel_track, true)
        reaper.SetCursorContext(0)
        SetTrackInfo(sel_track, 'B_SHOWINMIXER', 1)
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end
end

function Exit()
    -- Restore tracks for all projects
    local curr_proj, fn = reaper.EnumProjects( -1, '')
    if not reaper.ValidatePtr(curr_proj, 'ReaProject*') then
        return
    end
    local i = 0
    local proj = reaper.EnumProjects(i)
    while reaper.ValidatePtr(proj, 'ReaProject*') do
        reaper.SelectProjectInstance(proj)
        RestoreTracks()
        i = i + 1
        proj = reaper.EnumProjects(i)
    end
    if reaper.ValidatePtr(curr_proj, 'ReaProject*') then
        reaper.SelectProjectInstance(curr_proj)
    end
    -- Load mixing screenset
    reaper.Main_OnCommand(40453 + screenset_default, 0)
    reaper.ThemeLayout_SetLayout('mcp', layout_default)
    reaper.ThemeLayout_SetLayout('master_mcp', layout_default_master)
    local mixer_visible = reaper.GetToggleCommandState(40078)
    if mixer_visible == 0 and fn ~= '' then
        reaper.Main_OnCommand(40078, 0)
    end
end

-- Check state / Restore if necessary
local _, track_states = reaper.GetProjExtState(0, extname, 'track_states')
if track_states ~= '' then
    Exit()
end

-- Check if mixer is open but not visible (and project exists for global startup)
local _, fn = reaper.EnumProjects( -1, '')
local mixer_visible = reaper.GetToggleCommandState(40078)

if mixer_visible == 0 and fn ~= '' then
    reaper.Main_OnCommand(40078, 0)
    return
end

AdjustTracks()

-- Load track sidemixer screenset
reaper.Main_OnCommand(40453 + screenset_sidemixer, 0)
reaper.ThemeLayout_SetLayout('mcp', layout_sidemixer)
reaper.ThemeLayout_SetLayout('master_mcp', layout_sidemixer_master)

FallBack()

local proj_old
local file_name_old
local old_sel_track
local track_cnt_old = -1

function Main()
    -- Tab change
    local proj_new, file_name_new = reaper.EnumProjects( -1, '')
    if proj_old ~= proj_new or file_name_old ~= file_name_new then
        proj_old = proj_new
        file_name_old = file_name_new
        local _, states = reaper.GetProjExtState(0, extname, 'track_states')
        if states == '' then
            AdjustTracks()
        end
        FallBack()
    end

    local new_sel_track = reaper.GetSelectedTrack(0, 0)

    -- Track count change
    local track_cnt_new = reaper.CountTracks(0)
    if track_cnt_old ~= track_cnt_new then
        track_cnt_old = track_cnt_new
        local _, states = reaper.GetProjExtState(0, extname, 'track_states')
        for i = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, i)
            local track_guid = reaper.GetTrackGUID(track)

            local visible = GetTrackInfo(track, 'B_SHOWINMIXER')
            -- Append new tracks
            if visible and track ~= old_sel_track then
                states = states .. track_guid .. visible .. '\n'
                SetTrackInfo(track, 'B_SHOWINMIXER', 0)
            end
        end
        reaper.SetProjExtState(0, extname, 'track_states', states)

        if not new_sel_track and track_cnt_new > 0 then
            local track_first = reaper.GetTrack(0, track_cnt_new - 1)
            reaper.SetCursorContext(0)
            reaper.SetTrackSelected(track_first, true)
            reaper.SetCursorContext(0)
            SetTrackInfo(track_first, 'B_SHOWINMIXER', 1)
            old_sel_track = track_first
        end
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
    end
    -- Track selection change
    if new_sel_track and new_sel_track ~= old_sel_track then
        SetTrackInfo(new_sel_track, 'B_SHOWINMIXER', 1)
        if old_sel_track and reaper.ValidatePtr(old_sel_track, 'MediaTrack*') then
            SetTrackInfo(old_sel_track, 'B_SHOWINMIXER', 0)
        end
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        old_sel_track = new_sel_track
    end
    reaper.defer(Main)
end

Main()

reaper.atexit(Exit)
