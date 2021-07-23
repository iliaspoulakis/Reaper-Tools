--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
]] --
local prev_proj
local prev_time = 0
local prev_state
local prev_focused_hwnd
local prev_wnd_cnt
local prev_wnd_list
local prev_fx_wnd_cnt

local active_hwnd

local wnd_l
local wnd_t

local debug = false

function print(msg)
    if debug then reaper.ShowConsoleMsg(tostring(msg) .. "\n") end
end

local is_mac = reaper.GetOS():match('OSX')

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

function GetOpenProjects()
    local projects = {}
    local p = 0
    repeat
        local proj = reaper.EnumProjects(p)
        if reaper.ValidatePtr(proj, 'ReaProject*') then
            projects[#projects + 1] = proj
        end
        p = p + 1
    until not proj
    return projects
end

function GetWindowPosition(hwnd)
    local _, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
    return l, t, r, b
end

function SetWindowPosition(hwnd, l, t, r, b)
    if is_mac then t = b end
    reaper.JS_Window_SetPosition(hwnd, l, t, r - l, math.abs(b - t))
end

function GetAllFloatingFXWindows()
    local hwnds = {}
    local projects = GetOpenProjects()
    for _, proj in ipairs(projects) do
        local master_track = reaper.GetMasterTrack(proj)
        for fx = 0, reaper.TrackFX_GetCount(master_track) - 1 do
            local hwnd = reaper.TrackFX_GetFloatingWindow(master_track, fx)
            if hwnd then hwnds[#hwnds + 1] = hwnd end
        end
        for t = 0, reaper.CountTracks(proj) - 1 do
            local track = reaper.GetTrack(proj, t)
            for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
                local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx)
                if hwnd then hwnds[#hwnds + 1] = hwnd end
            end
            for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
                local fx_in = fx + 0x1000000
                local hwnd = reaper.TrackFX_GetFloatingWindow(track, fx_in)
                if hwnd then hwnds[#hwnds + 1] = hwnd end
            end
            for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
                    local take = reaper.GetMediaItemTake(item, tk)
                    for fx = 0, reaper.TakeFX_GetCount(take) - 1 do
                        local hwnd = reaper.TakeFX_GetFloatingWindow(take, fx)
                        if hwnd then
                            hwnds[#hwnds + 1] = hwnd
                        end
                    end
                end
            end
        end
    end
    return hwnds
end

function GetLastFocusedFloatingFXWindow()
    local ret, tnum, inum, fnum = reaper.GetFocusedFX2()

    local is_track_fx = ret & 1 == 1
    local is_item_fx = ret & 2 == 2

    if is_track_fx then
        local track
        if tnum == 0 then
            track = reaper.GetMasterTrack(0)
        else
            track = reaper.GetTrack(0, tnum - 1)
        end
        return reaper.TrackFX_GetFloatingWindow(track, fnum)
    end

    if is_item_fx then
        local track = reaper.GetTrack(0, tnum - 1)
        local item = reaper.GetTrackMediaItem(track, inum)
        local tk = fnum >> 24
        local take = reaper.GetMediaItemTake(item, tk)
        local fx = fnum & 0xFFFFFF
        return reaper.TakeFX_GetFloatingWindow(take, fx)
    end
end

function KeepTopLeftCorner(w, h)
    local l = wnd_l
    local t = is_mac and wnd_t - h or wnd_t
    local r = wnd_l + w
    local b = is_mac and wnd_t or wnd_t + h
    return reaper.EnsureNotCompletelyOffscreen(l, t, r, b)
end

function PositionFloatingFXWindow(hwnd)
    if wnd_l and wnd_t then
        local l, t, r, b = GetWindowPosition(hwnd)
        l, t, r, b = KeepTopLeftCorner(r - l, math.abs(b - t))
        SetWindowPosition(hwnd, l, t, r, b)
    end
end

function PositionChunkWindows()
    local time = reaper.time_precise()
    reaper.Undo_BeginBlock()

    local function SetPosition(type, x, y, w, h)
        local l, t, r, b = KeepTopLeftCorner(w, h)
        return ('%s %d %d %d %d'):format(type, l, t, r - l, b - t)
    end

    local m_track = reaper.GetMasterTrack(0)
    local _, m_chunk = reaper.GetTrackStateChunk(m_track, '', true)
    m_chunk = m_chunk:gsub('(FLOATP?O?S?) (%d+) (%d+) (%d+) (%d+)', SetPosition)
    reaper.SetTrackStateChunk(m_track, m_chunk, true)

    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local _, chunk = reaper.GetTrackStateChunk(track, '', false)
        chunk = chunk:gsub('(FLOATP?O?S?) (%d+) (%d+) (%d+) (%d+)', SetPosition)
        reaper.SetTrackStateChunk(track, chunk, false)
    end

    reaper.Undo_EndBlock('Center FX Windows', -1)
    print("Chunk positioning time:")
    print(reaper.time_precise() - time)
end

function Main()
    local proj = reaper.EnumProjects(-1, '')
    if prev_proj ~= proj then
        prev_proj = proj
        print('Project changed')
        -- Retrigger PositionChunkWindows in new project (fake position change)
        wnd_l = nil
    end

    local time = reaper.time_precise()
    local focused_hwnd = GetLastFocusedFloatingFXWindow()
    local state = reaper.GetProjectStateChangeCount(0)

    local has_focus_changed = prev_focused_hwnd ~= focused_hwnd
    local has_state_changed = prev_state ~= state
    local has_time_passed = time > prev_time + 0.5

    if has_focus_changed or has_state_changed or has_time_passed then
        prev_focused_hwnd = focused_hwnd
        prev_state = state
        prev_time = time

        -- Check if open windows have changed
        local wnd_cnt, wnd_list = reaper.JS_Window_ListAllTop()
        if prev_wnd_cnt ~= wnd_cnt or wnd_list ~= prev_wnd_list then
            prev_wnd_cnt = wnd_cnt
            prev_wnd_list = wnd_list
            print('Open windows changed')

            -- Ensure that only one floating fx window is open
            local fx_windows = GetAllFloatingFXWindows()
            local fx_wnd_cnt = #fx_windows

            if prev_fx_wnd_cnt ~= fx_wnd_cnt then
                prev_fx_wnd_cnt = fx_wnd_cnt
                print('Floating fx windows changed')
                print('New count: ' .. fx_wnd_cnt)

                if fx_wnd_cnt == 0 then active_hwnd = nil end

                if fx_wnd_cnt == 1 then
                    active_hwnd = fx_windows[1]
                    PositionFloatingFXWindow(active_hwnd)
                end
                if fx_wnd_cnt > 1 then
                    local new_hwnd
                    -- Close active fx window (looks snappier when closed beforehand)
                    reaper.JS_Window_Destroy(active_hwnd)
                    for _, hwnd in ipairs(fx_windows) do
                        if hwnd ~= active_hwnd then
                            if not new_hwnd then
                                -- Choose a new floating fx window
                                new_hwnd = hwnd
                                PositionFloatingFXWindow(new_hwnd)
                            else
                                -- Close all other floating fx windows
                                reaper.JS_Window_Destroy(hwnd)
                            end
                        end
                    end
                    active_hwnd = new_hwnd
                    prev_wnd_cnt, prev_wnd_list = reaper.JS_Window_ListAllTop()
                    prev_fx_wnd_cnt = 1
                end
            end
        end
    end

    -- Monitor active window position
    if reaper.ValidatePtr(active_hwnd, '*') then
        local is_mouse_pressed = reaper.JS_Mouse_GetState(1) == 1
        if not is_mouse_pressed then
            local l, t = GetWindowPosition(active_hwnd)
            if l ~= wnd_l or t ~= wnd_t then
                wnd_l = l
                wnd_t = t
                PositionChunkWindows()
            end
        end
    end

    reaper.defer(Main)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
end

reaper.atexit(Exit)

local focused_hwnd = GetLastFocusedFloatingFXWindow()
-- Close all floating fx windows except focused one
if focused_hwnd then
    local windows = GetAllFloatingFXWindows()
    for _, hwnd in ipairs(windows) do
        if hwnd ~= focused_hwnd then reaper.JS_Window_Destroy(hwnd) end
    end
end

Main()
