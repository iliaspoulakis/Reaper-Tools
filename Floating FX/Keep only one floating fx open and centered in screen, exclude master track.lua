--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
]]
local debug = false

local prev_proj
local prev_time = 0
local prev_state
local prev_focused_hwnd
local prev_wnd_cnt
local prev_wnd_list
local prev_fx_wnd_cnt

local active_hwnd

local wnd_l = 0
local wnd_t = 0
local wnd_r = 0
local wnd_b = 0

local screen_l = 0
local screen_t = 0
local screen_r = 0
local screen_b = 0

function print(msg)
    if debug then reaper.ShowConsoleMsg(tostring(msg) .. '\n') end
end

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
    reaper.JS_Window_SetPosition(hwnd, l, t, r - l, math.abs(b - t))
end

function SetScreenPosition(l, t, r, b)
    local s_l, s_t, s_r, s_b = reaper.my_getViewport(0, 0, 0, 0, l, t, r, b, 1)
    local is_new_screen =
        not (s_l == screen_l and screen_t == s_t and screen_r == s_r and
        screen_b == s_b)
    screen_l, screen_t, screen_r, screen_b = s_l, s_t, s_r, s_b
    return is_new_screen
end

function GetAllFloatingFXWindows()
    local hwnds = {}
    local projects = GetOpenProjects()

    local TrackFX_GetFloatingWindow = reaper.TrackFX_GetFloatingWindow
    local TakeFX_GetFloatingWindow = reaper.TakeFX_GetFloatingWindow

    for _, proj in ipairs(projects) do
        for t = 0, reaper.CountTracks(proj) - 1 do
            local track = reaper.GetTrack(proj, t)
            for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
                local hwnd = TrackFX_GetFloatingWindow(track, fx)
                if hwnd then hwnds[#hwnds + 1] = hwnd end
            end
            for fx = 0, reaper.TrackFX_GetRecCount(track) - 1 do
                local fx_in = fx + 0x1000000
                local hwnd = TrackFX_GetFloatingWindow(track, fx_in)
                if hwnd then hwnds[#hwnds + 1] = hwnd end
            end

            for i = 0, reaper.CountTrackMediaItems(track) - 1 do
                local item = reaper.GetTrackMediaItem(track, i)
                for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
                    local take = reaper.GetMediaItemTake(item, tk)
                    if reaper.ValidatePtr(take, 'MediaItem_Take*') then
                        for fx = 0, reaper.TakeFX_GetCount(take) - 1 do
                            local hwnd = TakeFX_GetFloatingWindow(take, fx)
                            if hwnd then
                                hwnds[#hwnds + 1] = hwnd
                            end
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
            -- Exclude master track
            return nil
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

function CenterInScreen(w, h)
    local l = screen_l + (screen_r - screen_l - w) // 2
    local t = screen_t + (screen_b - screen_t - h) // 2
    local r = l + w
    local b = t + h
    return l, t, r, b
end

function PositionFloatingFXWindow(hwnd)
    local l, t, r, b = GetWindowPosition(hwnd)
    local is_new_screen = SetScreenPosition(l, t, r, b)
    l, t, r, b = CenterInScreen(r - l, math.abs(b - t))
    SetWindowPosition(hwnd, l, t, r, b)
    if is_new_screen then PositionChunkWindows() end
end

function PositionChunkWindows()
    local time = reaper.time_precise()
    reaper.Undo_BeginBlock()

    local function SetPosition(type, x, y, w, h)
        local l, t, r, b = CenterInScreen(w, h)
        return ('%s %d %d %d %d'):format(type, l, t, r - l, b - t)
    end

    local pattern = '(FLOATP?O?S?) (%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)'

    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local _, chunk = reaper.GetTrackStateChunk(track, '', false)
        chunk = chunk:gsub(pattern, SetPosition)
        reaper.SetTrackStateChunk(track, chunk, false)
    end

    reaper.Undo_EndBlock('Center FX Windows', -1)
    print('Chunk positioning time:')
    print(reaper.time_precise() - time)
end

function Main()
    local proj = reaper.EnumProjects( -1, '')
    if prev_proj ~= proj then
        prev_proj = proj
        print('Project changed')
        -- Retrigger PositionChunkWindows in new project (fake screen change)
        screen_l = nil
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
            local l, t, r, b = GetWindowPosition(active_hwnd)
            if not (wnd_l == l and wnd_t == t and wnd_r == r and wnd_b == b) then
                print('Window position changed')
                local is_new_screen = SetScreenPosition(l, t, r, b)
                if is_new_screen then
                    print('Screen changed')
                    l, t, r, b = CenterInScreen(r - l, math.abs(b - t))
                    SetWindowPosition(active_hwnd, l, t, r, b)
                    PositionChunkWindows()
                end
                wnd_l, wnd_t, wnd_r, wnd_b = l, t, r, b
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
