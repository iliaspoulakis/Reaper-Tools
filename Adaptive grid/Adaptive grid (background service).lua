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

function IsServiceEnabled()
    return reaper.GetExtState(extname, 'is_service_enabled') == ''
end

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

local main_mult
local midi_mult

local prev_hzoom_lvl
local prev_midi_hzoom_lvl
local prev_chunk

function Main()

    -- Check if arrange view grid is set to adaptive
    main_mult = GetGridMultiplier()
    if main_mult ~= 0 then
        -- Check if zoom level changed
        local hzoom_lvl = reaper.GetHZoomLevel()
        if prev_hzoom_lvl ~= hzoom_lvl then
            prev_hzoom_lvl = hzoom_lvl
            -- Run adapt script in mode 1
            _G.mode = 1
            run_adapt_scipt()
        end
    end

    -- Check if MIDI editor grid is set to adaptive
    midi_mult = GetMIDIGridMultiplier()
    if midi_mult ~= 0 then
        -- Check if MIDI editor is open
        local hwnd = reaper.MIDIEditor_GetActive()
        local take = reaper.MIDIEditor_GetTake(hwnd)
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
                end
            end
        end
    end

    -- Exit script automatically when not needed anymore (by changes in settings)
    if not IsServiceEnabled() or main_mult == 0 and midi_mult == 0 then
        return
    end
    reaper.defer(Main)
end

function Exit() SetServiceRunning(false) end

SetServiceRunning(true)
reaper.atexit(Exit)
Main()

