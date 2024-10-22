--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Background service that looks for changes in zoom level
]]

local extname = 'FTC.AdaptiveGrid'
local _, file = reaper.get_action_context()
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

local prev_hzoom_lvl
local prev_midi_hzoom_lvl
local prev_editor_hwnd
local prev_editor_time
local prev_take
local prev_take_time
local prev_chunk
local prev_time
local prev_mouse_x
local prev_mouse_y

local prev_page_epos
local prev_page_size

local has_js_api = reaper.JS_Window_FromPoint
local is_windows = reaper.GetOS():match('Win')

-- Note: Tooltip delay is only necessary on Windows
local tooltip_delay = 0

if is_windows then
    tooltip_delay = select(2, reaper.get_config_var_string('tooltipdelay'))
    tooltip_delay = (tonumber(tooltip_delay) or 200) / 1000
    tooltip_delay = tooltip_delay * (has_js_api and 2 or 5)
end

local function AdaptArrangeViewGrid()
    -- Options: Toggle grid lines
    local is_grid_visible = reaper.GetToggleCommandState(40145) == 1
    if not is_grid_visible then return end
    -- Grid: Set framerate grid
    local is_frame_grid = reaper.GetToggleCommandState(40904) == 1
    if is_frame_grid then return end
    -- Grid: Set measure grid
    local is_measure_grid = reaper.GetToggleCommandState(40923) == 1
    if is_measure_grid then return end
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

local function AdaptMIDIEditorGrid()
    local time = reaper.time_precise()
    -- Find MIDI editor window (optimized)
    local editor_hwnd = prev_editor_hwnd
    if not prev_editor_time or time > prev_editor_time + 0.2 then
        prev_editor_time = time
        editor_hwnd = reaper.MIDIEditor_GetActive()
    elseif editor_hwnd and not reaper.ValidatePtr(editor_hwnd, 'HWND*') then
        editor_hwnd = reaper.MIDIEditor_GetActive()
    end
    -- Return when no MIDI editor is open
    if not editor_hwnd then
        prev_editor_hwnd = nil
        return
    end
    prev_editor_hwnd = editor_hwnd

    -- Find MIDI editor take (optimized)
    local take = prev_take
    if not prev_take or time > prev_take_time + 0.2 then
        prev_take_time = time
        take = reaper.MIDIEditor_GetTake(editor_hwnd)
    end
    if prev_take and not reaper.ValidatePtr(prev_take, 'MediaItem_Take*') then
        take = reaper.MIDIEditor_GetTake(editor_hwnd)
        -- Note: Double check that MIDIEditor_GetTake always returns a valid take
        if take and not reaper.ValidatePtr(take, 'MediaItem_Take*') then
            take = nil
        end
    end
    -- Return when no take is open
    if not take then
        prev_take = nil
        return
    end
    prev_take = take

    local item = reaper.GetMediaItemTake_Item(take)
    if not item or not reaper.ValidatePtr(item, 'MediaItem*') then return end

    if has_js_api then
        local note_view = reaper.JS_Window_FindChildByID(editor_hwnd, 1001)
        local _, _, size, _, epos = reaper.JS_Window_GetScrollInfo(note_view, 'h')
        if epos == prev_page_epos and size == prev_page_size then return end
        prev_page_epos = epos
        prev_page_size = size
    end

    -- Note: Calling GetItemStateChunk repeatedly causes issues on Windows
    -- 1. Makes channel combobox unusable
    -- 2. Prevents tooltips from being shown
    if is_windows then
        local x, y = reaper.GetMousePosition()

        local is_channel_combobox_hovered = false
        local hover_hwnd
        local hover_id

        -- Check if channel combobox is hovered
        if has_js_api then
            local GetLong = reaper.JS_Window_GetLong
            hover_hwnd = reaper.JS_Window_FromPoint(x, y)

            local is_valid = reaper.ValidatePtr(hover_hwnd, 'HWND*')
            hover_id = is_valid and GetLong(hover_hwnd, 'ID')

            -- Note: 1000 is the id of the combobox menu when opened
            if hover_id == 1000 then
                local focus_hwnd = reaper.JS_Window_GetFocus()
                is_valid = reaper.ValidatePtr(focus_hwnd, 'HWND*')

                local focus_id = is_valid and GetLong(focus_hwnd, 'ID')
                -- Check if the channel combobox (ID 1006) is focused
                if focus_id == 1006 then
                    if reaper.JS_Window_IsChild(editor_hwnd, focus_hwnd) then
                        is_channel_combobox_hovered = true
                    end
                end
            end
        end
        if is_channel_combobox_hovered then
            -- Delay indefinitely as long as combobox is hovered
            prev_time = time - 0.05
        elseif x ~= prev_mouse_x or y ~= prev_mouse_y then
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
                if hover_id == 1001 then
                    if reaper.JS_Window_IsChild(editor_hwnd, hover_hwnd) then
                        prev_time = nil
                    end
                end
            end
        end
    end
    -- Check if enough time has passed since last run (tooltip delay)
    if prev_time and time < prev_time + tooltip_delay then return end
    prev_time = time

    -- Check if item chunk changed (string comparison is fast)
    local _, chunk = reaper.GetItemStateChunk(item, '', false)
    if chunk == prev_chunk then return end
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

function Main()
    -- Check if arrange view  and MIDI editor grids are set to adaptive
    local main_mult = GetGridMultiplier()
    local midi_mult = GetMIDIGridMultiplier()

    -- Exit script automatically when not needed anymore (by changes in settings)
    if main_mult == 0 and midi_mult == 0 then return end

    if main_mult ~= 0 then AdaptArrangeViewGrid() end
    if midi_mult ~= 0 then AdaptMIDIEditorGrid() end

    reaper.defer(Main)
end

function Exit() SetServiceRunning(false) end

SetServiceRunning(true)
reaper.atexit(Exit)
Main()
