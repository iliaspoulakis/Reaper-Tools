--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Background service that looks for changes in zoom level
]]

local extname = 'FTC.AdaptiveGrid'
local _, file, sec = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

function SetServiceRunning(is_running)
    local value = is_running and 'yes' or ''
    reaper.SetExtState(extname, 'is_service_running', value, false)
end

function GetGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'main_mult')) or 0
end

function GetMIDIGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'midi_mult')) or 0
end

function GetTakeChunk(take, chunk)
    if not chunk then
        local item = reaper.GetMediaItemTake_Item(take)
        chunk = select(2, reaper.GetItemStateChunk(item, '', false))
    end
    local tk = reaper.GetMediaItemTakeInfo_Value(take, 'IP_TAKENUMBER')

    local take_start_ptr = 0
    local take_end_ptr = 0

    for _ = 0, tk do
        take_start_ptr = take_end_ptr
        take_end_ptr = chunk:find('\nTAKE[%s\n]', take_start_ptr + 1)
    end
    return chunk:sub(take_start_ptr, take_end_ptr)
end

function GetTakeChunkHZoom(chunk)
    local pattern = 'CFGEDITVIEW (.-) (.-) '
    return chunk:match(pattern)
end

local adapt_script_path = ConcatPath(path, 'Adapt grid to zoom level.lua')
local run_adapt_scipt = loadfile(adapt_script_path)
if not run_adapt_scipt then return end

local prev_grid_state
local prev_hzoom_lvl
local prev_midi_hzoom_lvl
local prev_chunk
local prev_time
local prev_mouse_x
local prev_mouse_y

local has_js_api = reaper.JS_Window_FromPoint
local is_windows = reaper.GetOS():match('Win')

-- Note: Tooltip delay is only necessary on Windows
local tooltip_delay = 0

if is_windows then
    tooltip_delay = select(2, reaper.get_config_var_string('tooltipdelay'))
    tooltip_delay = (tonumber(tooltip_delay) or 200) / 1000
    tooltip_delay = tooltip_delay * (has_js_api and 2 or 5)
end

function Main()
    -- Options: Toggle grid lines
    local grid_state = reaper.GetToggleCommandState(40145)

    -- Check if grid visibility changed
    if grid_state ~= prev_grid_state then
        prev_grid_state = grid_state
        -- Reset values to trigger running the adapt script
        prev_hzoom_lvl = nil
        prev_midi_hzoom_lvl = nil
        prev_chunk = nil
    end

    -- Check if arrange view grid is set to adaptive
    local main_mult = GetGridMultiplier()
    if main_mult ~= 0 then
        -- Grid: Set framerate grid
        local is_frame_grid = reaper.GetToggleCommandState(40904) == 1
        -- Grid: Set measure grid
        local is_measure_grid = reaper.GetToggleCommandState(40923) == 1
        -- Ignore arrange view changes grid is set to frame/measure
        if not is_frame_grid and not is_measure_grid then
            -- Check if zoom level changed
            local hzoom_lvl = reaper.GetHZoomLevel()
            if prev_hzoom_lvl ~= hzoom_lvl then
                prev_hzoom_lvl = hzoom_lvl
                -- Run adapt script in mode 1
                _G.mode = 1
                run_adapt_scipt()
                -- dofile(adapt_script_path)
            end
        end
    end

    -- Check if MIDI editor grid is set to adaptive
    local midi_mult = GetMIDIGridMultiplier()
    if midi_mult ~= 0 then
        local editor_hwnd = reaper.MIDIEditor_GetActive()
        local time = reaper.time_precise()
        -- Windows needs a delay to show tooltips (caused by GetItemStateChunk)
        if is_windows then
            local x, y = reaper.GetMousePosition()
            if x ~= prev_mouse_x or y ~= prev_mouse_y then
                -- Ignore tooltip delay when mouse moves
                prev_mouse_x = x
                prev_mouse_y = y
                prev_time = nil
            elseif has_js_api then
                -- Use JS_ReaScriptApi to improve delay behavior
                local tooltip_hwnd = reaper.GetTooltipWindow()
                local tooltip = reaper.JS_Window_GetTitle(tooltip_hwnd)
                if tooltip ~= '' then
                    -- Delay indefinitely as long as tooltip is shown
                    prev_time = time - 0.05
                else
                    -- Avoid tooltip delay when mouse is on top of midiview
                    local hover_hwnd = reaper.JS_Window_FromPoint(x, y)
                    local id = reaper.JS_Window_GetLong(hover_hwnd, 'ID', 0)
                    if id == 1001 then
                        if reaper.JS_Window_IsChild(editor_hwnd, hover_hwnd) then
                            prev_time = nil
                        end
                    end
                end
            end
        end
        -- Check if enough time has passed since last run (tooltip delay)
        if not prev_time or time > prev_time + tooltip_delay then
            prev_time = time
            -- Check if MIDI editor contains a valid take
            local take = reaper.MIDIEditor_GetTake(editor_hwnd)
            if reaper.ValidatePtr(take, 'MediaItem_Take*') then
                local item = reaper.GetMediaItemTake_Item(take)
                local _, chunk = reaper.GetItemStateChunk(item, '', false)
                -- Check if item chunk changed (string comparison is fast)
                if chunk ~= prev_chunk then
                    prev_chunk = chunk
                    local take_chunk = GetTakeChunk(take, chunk)
                    local _, midi_hzoom_lvl = GetTakeChunkHZoom(take_chunk)
                    -- Check if zoom level in chunk changed
                    if prev_midi_hzoom_lvl ~= midi_hzoom_lvl then
                        prev_midi_hzoom_lvl = midi_hzoom_lvl
                        -- Run adapt script in mode 2
                        _G.mode = 2
                        run_adapt_scipt()
                        -- dofile(adapt_script_path)
                    end
                end
            end
        end
    end

    -- Exit script automatically when not needed anymore (by changes in settings)
    if main_mult == 0 and midi_mult == 0 then return end
    reaper.defer(Main)
end

function Exit() SetServiceRunning(false) end

SetServiceRunning(true)
reaper.atexit(Exit)
Main()

