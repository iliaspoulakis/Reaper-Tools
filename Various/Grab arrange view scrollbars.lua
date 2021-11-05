--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Grabs the arrange view vertical and horizontal scrollbars for as long as
    the script is running. (Recommended on arrange view middle click mouse modifier)
]]

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

local prev_x, prev_y

local is_osx = reaper.GetOS():match('OSX') or reaper.GetOS():match('macOS')
local main_hwnd = reaper.GetMainHwnd()
local hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)

local _, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)

function GetScrollBarInfo(type)
    local _, pos, page, min, max = reaper.JS_Window_GetScrollInfo(hwnd, type)
    local total = math.abs(type == 'v' and bottom - top or right - left) - 72
    local unit = (max - min) / total
    local bar_w = page / unit
    return pos, unit, bar_w
end

-- Set initial cursor position
local pos, unit, bar_w = GetScrollBarInfo('h')
local start_x = left + 16 + math.floor(pos / unit + bar_w / 2)

pos, unit, bar_w = GetScrollBarInfo('v')
local offs = 16 + math.floor(pos / unit + bar_w / 2)
local start_y = is_osx and top - offs or top + offs

reaper.JS_Mouse_SetPosition(start_x, start_y)

-- Prepare new cursor icon
local cursor = reaper.JS_Mouse_LoadCursor(429)
reaper.JS_WindowMessage_Intercept(hwnd, 'WM_SETCURSOR', false)
reaper.JS_WindowMessage_Intercept(main_hwnd, 'WM_SETCURSOR', false)

function Main()
    local x, y = reaper.GetMousePosition()

    if prev_x ~= x or prev_y ~= y then
        prev_x, prev_y = x, y

        _, unit, bar_w = GetScrollBarInfo('h')
        pos = math.max(0, math.min(right, x - left - 16 - bar_w / 2))
        reaper.JS_Window_SetScrollPos(hwnd, 'h', math.floor(pos * unit))

        _, unit, bar_w = GetScrollBarInfo('v')
        offs = 16 + bar_w / 2
        pos = is_osx and top - y - offs or y - top - offs
        reaper.JS_Window_SetScrollPos(hwnd, 'v', math.floor(pos * unit))
    end

    reaper.JS_Mouse_SetCursor(cursor)
    reaper.defer(Main)
end

function Exit()
    -- Set cursor back to default
    reaper.JS_WindowMessage_Release(hwnd, 'WM_SETCURSOR')
    reaper.JS_WindowMessage_Release(main_hwnd, 'WM_SETCURSOR')
    cursor = reaper.JS_Mouse_LoadCursor(527)
    reaper.JS_Mouse_SetCursor(cursor)
end

reaper.atexit(Exit)
Main()
