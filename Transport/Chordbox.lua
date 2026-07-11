--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.2
  @about Adds a little box to transport that displays chord information
  @changelog
    - Fix possible crash when loading saved coordinates
]]

local box_name = 'ChordBox'
local extname = 'FTC.' .. box_name

local box_w
local box_h
local box_x
local box_y

local prev_box_w
local prev_box_h
local prev_box_x
local prev_box_y

local attach_mode
local attach_x
local attach_center_mode
local attach_center_x
local prev_is_centered

local user_bg_color
local user_play_color
local user_cursor_color
local user_rec_color
local user_border_color
local user_arrow_color
local user_button_on_color
local user_button_off_color
local user_button_sep_color
local user_button_size
local user_corner_radius
local user_text_color
local user_font_height
local user_font_family
local user_font_weight
local user_font_yoffs

local window_hwnd
local prev_window_hwnd
local window_w
local window_h

local prev_time
local prev_window_w
local prev_window_h
local prev_color_theme
local prev_top_window_cnt
local prev_attach_hwnd
local top_window_array = reaper.new_array(4096)
local main_hwnd = reaper.GetMainHwnd()

local chord_text = ''
local chord_icon = 0

local drag_x
local drag_y

local is_left_click = false
local is_right_click = false

local menu_time

local bitmap
local lice_font
local font_size

local bg_bitmap
local button_bitmap
local prev_button_color

local prev_bg_color
local prev_bg_corner_r

local is_redraw = false
local is_resize = false
local resize_flags = 0
local resize_cursor

local comp_fps, comp_delay
local transport_title
local attach_window_title, attach_window_wait, attach_window_child_id

local measure_scale, draw_scale
local min_box_size

local mouse_x, mouse_y
local button_w = 0

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Detect operating system
local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OS')
local is_linux = os:match('Other')

-- Check dependencies
local has_reapack = reaper.ReaPack_BrowsePackages ~= nil
local missing_dependencies = {}

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Composite_Delay then
    if has_reapack then
        table.insert(missing_dependencies, 'js_ReaScriptAPI')
    else
        reaper.MB('Please install js_ReaScriptAPI extension', box_name, 0)
        return
    end
end

if #missing_dependencies > 0 then
    local msg = ('Missing dependencies:\n\n'):format(#missing_dependencies)
    for _, dependency in ipairs(missing_dependencies) do
        msg = msg .. ' • ' .. dependency .. '\n'
    end
    reaper.MB(msg, box_name, 0)

    for i = 1, #missing_dependencies do
        if missing_dependencies[i]:match(' ') then
            missing_dependencies[i] = '"' .. missing_dependencies[i] .. '"'
        end
    end
    reaper.ReaPack_BrowsePackages(table.concat(missing_dependencies, ' OR '))
    return
end

-------------------------------- BOX FUNCTIONS -----------------------------------

function print(...)
    local values = {...}
    for i = 1, #values do values[i] = tostring(values[i]) end
    if #values == 0 then values[1] = 'nil' end
    reaper.ShowConsoleMsg(table.concat(values, ' ') .. '\n')
end

function ConcatPath(...)
    return table.concat({...}, package.config:sub(1, 1))
end

function GetTransportScale()
    local _, new_dpi = reaper.ThemeLayout_GetLayout('trans', -3)
    local scale = tonumber(new_dpi) / 256
    return is_macos and 1 or scale, scale
end

function Scale(value, scale)
    if not tonumber(value) then return value end
    return math.floor(value * scale + 0.5)
end

reaper.gmem_attach('mouse_pos')
local mouse_pos_state = reaper.gmem_read(0)

local function GetMousePosition()
    local global_state = reaper.gmem_read(0)
    if global_state > mouse_pos_state then
        mouse_pos_state = global_state
        return reaper.gmem_read(1), reaper.gmem_read(2)
    else
        mouse_pos_state = mouse_pos_state + 1
        local x, y = reaper.GetMousePosition()
        reaper.gmem_write(0, mouse_pos_state)
        reaper.gmem_write(1, x)
        reaper.gmem_write(2, y)
        return x, y
    end
end

local function SerializeParts(obj, parts)
    parts = parts or {}
    local obj_type = type(obj)
    if obj_type == 'number' then
        parts[#parts + 1] = obj
    elseif obj_type == 'string' then
        parts[#parts + 1] = string.format('%q', obj)
    elseif obj_type == 'boolean' then
        parts[#parts + 1] = obj and 'true' or 'false'
    elseif obj_type == 'table' then
        parts[#parts + 1] = '{'
        for key, value in pairs(obj) do
            local val_type = type(value)
            if val_type ~= 'function' then
                local key_type = type(key)
                local is_num_key = key_type == 'number'
                if is_num_key or key_type == 'string' and key:sub(1, 1) ~= '_' then
                    if is_num_key or not key:match('^[_%a]+$') then
                        parts[#parts + 1] = '['
                        parts[#parts + 1] = string.format('%q', key)
                        parts[#parts + 1] = ']'
                    else
                        parts[#parts + 1] = key
                    end
                    parts[#parts + 1] = '='
                    SerializeParts(value, parts)
                    parts[#parts + 1] = ','
                end
            end
        end
        if parts[#parts] == ',' then parts[#parts] = nil end
        parts[#parts + 1] = '}'
    end
    return parts
end

function Serialize(obj)
    return table.concat(SerializeParts(obj))
end

local env = {reaper = reaper}
function Deserialize(obj_str)
    local str = obj_str
    if str:sub(1, 7) ~= 'return ' then str = 'return ' .. str end
    local func, err = load(str, nil, 't', env)
    local res = func and func()
    return res, err
end

function ExtSave(key, value, is_temporary)
    if value == nil then
        reaper.DeleteExtState(extname, key, not is_temporary)
        return
    end
    local value_str = Serialize(value)
    if not value_str then return end
    reaper.SetExtState(extname, key, value_str, not is_temporary)
end

function ExtLoad(key, default)
    local value = default
    local value_str = reaper.GetExtState(extname, key)
    if value_str ~= '' then value = Deserialize(value_str) end
    return value
end

function GetStartupHookCommandID()
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

function IsStartupHookEnabled(opt_cmd_id)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = opt_cmd_id or GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

function CreateMenuRecursive(menu)
    local str = ''
    if menu.title then str = str .. '>' .. menu.title .. '|' end

    for _, entry in ipairs(menu) do
        if entry then
            local arg = entry.arg
            if entry.IsGrayed and entry.IsGrayed(arg) or entry.is_grayed then
                str = str .. '#'
            end
            if entry.IsChecked and entry.IsChecked(arg) or entry.is_checked then
                str = str .. '!'
            end
            if #entry > 0 then
                str = str .. CreateMenuRecursive(entry) .. '|'
            else
                if entry.title or entry.separator then
                    str = str .. (entry.title or '') .. '|'
                end
            end
        end
    end
    if menu.title then str = str .. '<' end
    return str
end

function ReturnMenuRecursive(menu, idx, i)
    i = i or 1
    for _, entry in ipairs(menu) do
        if entry then
            if #entry > 0 then
                i = ReturnMenuRecursive(entry, idx, i)
                if i < 0 then return i end
            elseif entry.title then
                if i == math.floor(idx) then
                    if entry.OnReturn then entry.OnReturn(entry.arg) end
                    return -1
                end
                i = i + 1
            end
        end
    end
    return i
end

local function ParseIni(content)
    local t = {}
    for line in content:gmatch('[^\r\n]+') do
        line = line:match('^%s*(.-)%s*$')
        if line ~= '' and line:sub(1, 1) ~= ';' and line:sub(1, 1) ~= '#' then
            local key, value = line:match('^([^=]+)%s*=%s*(.*)$')
            if key and value then
                local value_num = not key:match('_color$') and tonumber(value)
                t[key:match('^%s*(.-)%s*$')] = value_num or value
            end
        end
    end
    return t
end

function PrintIni()
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(prev_color_theme)
    local settings = theme_settings[theme_key]
    if settings then
        local sorted_settings = {}
        for k, v in pairs(settings) do
            sorted_settings[#sorted_settings + 1] = {key = k, value = v}
        end
        local function SortByName(t, key)
            local function Format(d) return ('%03d%s'):format(#d, d) end
            local function Compare(a, b)
                local ak, bk = tostring(a[key]), tostring(b[key])
                local ac, bc = ak:find('_color') ~= nil,
                    bk:find('_color') ~= nil
                if ac ~= bc then return bc end
                return ak:gsub('%d+', Format) < bk:gsub('%d+', Format)
            end
            table.sort(t, Compare)
        end
        SortByName(sorted_settings, 'key')

        reaper.ClearConsole()
        reaper.ShowConsoleMsg(box_name:lower() .. '.ini:\n\n')
        for _, entry in ipairs(sorted_settings) do
            reaper.ShowConsoleMsg(entry.key .. '=' .. entry.value .. '\n')
        end
    else
        reaper.ShowConsoleMsg('No saved settings')
    end
end

function LoadIntegratedSettings(theme_path)
    local file_name = box_name:lower() .. '.ini'
    if not theme_path:lower():match('%.reaperthemezip$') then
        -- Read theme file to get image resource path
        local theme_file = io.open(theme_path, 'r')
        if not theme_file then return nil, 'Could not read theme file' end
        local content = theme_file:read('*a')
        theme_file:close()

        local ui_img
        for line in content:gmatch('[^\r\n]+') do
            ui_img = line:match('^%s*ui_img=(.+)%s*$')
            if ui_img then break end
        end

        if not ui_img then return nil, 'Could not parse theme file' end

        local theme_dir = theme_path:match('^(.+)/')
        if is_windows then theme_dir = theme_path:match('^(.+)\\') end

        if ui_img:lower():match('%.reaperthemezip$') then
            -- Image resource path is a zipped
            theme_path = ConcatPath(theme_dir, ui_img)
        else
            -- Image resource path is unzipped
            local config_path = ConcatPath(theme_dir, ui_img, file_name)
            if not reaper.file_exists(config_path) then return nil, 'No config' end

            local config_file = io.open(config_path, 'r')
            if not config_file then return nil, 'Could not read config file' end
            content = config_file:read('*a')
            config_file:close()

            local config = ParseIni(content)
            if not next(config) then return nil, 'Empty config' end
            return config
        end
    end

    local zip, err = reaper.JS_Zip_Open(theme_path, 'r', 0)
    if err ~= 0 then return nil, reaper.JS_Zip_ErrorString(err) end

    local count, list = reaper.JS_Zip_ListAllEntries(zip)
    if count < 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(count)
    end

    local found_entry = nil
    for entry in list:gmatch('[^%z]+') do
        if entry:find(file_name, 1, true) then
            found_entry = entry
            break
        end
    end

    if not found_entry then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, 'Entry not found: ' .. file_name
    end

    local ret = reaper.JS_Zip_Entry_OpenByName(zip, found_entry)
    if ret ~= 0 then
        reaper.JS_Zip_Close(theme_path, zip)
        return nil, reaper.JS_Zip_ErrorString(ret)
    end

    local bytes, content = reaper.JS_Zip_Entry_ExtractToMemory(zip)
    reaper.JS_Zip_Entry_Close(zip)
    reaper.JS_Zip_Close(theme_path, zip)

    if bytes < 0 then
        return nil, reaper.JS_Zip_ErrorString(bytes)
    end

    local config = ParseIni(content)
    if not next(config) then return nil, 'Empty config' end
    return config
end

function SetThemeIntegration(value)
    local i = 0
    local param_pattern = box_name:lower()
    repeat
        local ret, desc, val, def, min, max = reaper.ThemeLayout_GetParameter(i)
        if desc and desc:lower():match(param_pattern) then
            if val ~= value and def == 0 and min == 0 and max == 1 then
                reaper.ThemeLayout_SetParameter(i, value, false)
                reaper.ThemeLayout_RefreshAll()
            end
            break
        end
        i = i + 1
    until not ret
end

function GetThemeKey(path)
    if path == '' then
        -- Note: Theme path can be empty in new REAPER installations?
        local reaper_version = reaper.GetAppVersion():match('[%d]+')
        return ('ColorThemes/Default_%s.0'):format(reaper_version)
    end
    -- Use relative path if inside resource directory
    local resource_dir = reaper.GetResourcePath()
    -- Note: Using find to suppress matching special characters in path
    local _, end_idx = path:find(resource_dir, 0, true)
    if end_idx then path = path:sub(end_idx + 2) end

    -- Replace windows path separator with unix (make cross-platform)
    if is_windows then path = path:gsub('\\', '/') end
    -- Remove file extension
    path = path:gsub('%.([^./]+)$', '')
    return path
end

function GetThemeFromKey(key)
    local theme_name = key:match('([^/]+)$')
    if is_windows then key = key:gsub('/', '\\') end

    local function FindInDir(dir)
        local fallback = nil
        local i = 0
        repeat
            local file_name = reaper.EnumerateFiles(dir, i)
            if file_name then
                local file_name_no_ext = file_name:gsub('%.([^./\\]+)$', '')
                if file_name_no_ext == theme_name then
                    if file_name:lower():match('%.reaperthemezip$') then
                        return ConcatPath(dir, file_name)
                    else
                        fallback = ConcatPath(dir, file_name)
                    end
                end
            end
            i = i + 1
        until not file_name
        return fallback
    end

    local dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    local result = FindInDir(dir)
    if result then return result end

    key = ConcatPath(reaper.GetResourcePath(), key)
    dir = is_windows and key:match('^(.+)\\') or key:match('^(.+)/')
    return FindInDir(dir)
end

function LoadThemeSettings(theme_path, only_appeareance)
    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)
    local settings = theme_settings[theme_key]

    if not settings then
        local theme_file = GetThemeFromKey(theme_key)
        if theme_file then
            local integrated_settings = LoadIntegratedSettings(theme_file)
            if integrated_settings then
                settings = integrated_settings
                SetEditMode(false)
            end
        end
    end

    local has_settings = settings ~= nil
    settings = settings or {}

    user_bg_color = settings.bg_color
    user_text_color = settings.text_color
    user_border_color = settings.border_color
    user_font_height = settings.font_height
    user_font_family = settings.font_family
    user_font_weight = settings.font_weight
    user_font_yoffs = settings.font_yoffs
    user_corner_radius = settings.corner_radius
    user_play_color = settings.play_color
    user_cursor_color = settings.cursor_color
    user_rec_color = settings.rec_color
    user_arrow_color = settings.arrow_color
    user_button_on_color = settings.button_on_color
    user_button_off_color = settings.button_off_color
    user_button_sep_color = settings.button_sep_color
    user_button_size = settings.button_size

    if settings.draw_scale and settings.draw_scale ~= draw_scale then
        local scale_factor = draw_scale / settings.draw_scale
        user_font_height = Scale(user_font_height, scale_factor)
        user_font_yoffs = Scale(user_font_yoffs, scale_factor)
        user_corner_radius = Scale(user_corner_radius, scale_factor)
        user_button_size = Scale(user_button_size, scale_factor)
    end

    if only_appeareance then return has_settings end

    if attach_window_title then
        settings = ExtLoad('attach_settings') or settings
    end

    attach_x = settings.attach_x
    attach_mode = settings.attach_mode
    attach_center_x = settings.attach_center_x
    attach_center_mode = settings.attach_center_mode

    local new_box_x = settings.box_x
    local new_box_y = settings.box_y
    local new_box_w = settings.box_w
    local new_box_h = settings.box_h

    if settings.measure_scale and settings.measure_scale ~= measure_scale then
        local scale_factor = measure_scale / settings.measure_scale
        new_box_x = Scale(new_box_x, scale_factor)
        new_box_y = Scale(new_box_y, scale_factor)
        new_box_w = Scale(new_box_w, scale_factor)
        new_box_h = Scale(new_box_h, scale_factor)
        attach_x = Scale(attach_x, scale_factor)
        attach_center_x = Scale(attach_center_x, scale_factor)
    end

    if attach_x or attach_center_x then new_box_x = GetAttachPosition() end
    SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
    local has_box_coords = box_x and box_y and box_w and box_h
    return (has_box_coords and (has_settings or attach_window_title ~= nil))
end

function SaveThemeSettings(theme_path)
    local settings = {
        box_x = box_x,
        box_y = box_y,
        box_w = box_w,
        box_h = box_h,
        attach_x = attach_x,
        attach_mode = attach_mode,
        attach_center_x = attach_center_x,
        attach_center_mode = attach_center_mode,
        bg_color = user_bg_color,
        text_color = user_text_color,
        border_color = user_border_color,
        font_height = user_font_height,
        font_family = user_font_family,
        font_weight = user_font_weight,
        font_yoffs = user_font_yoffs,
        corner_radius = user_corner_radius,
        draw_scale = draw_scale,
        measure_scale = measure_scale,
        play_color = user_play_color,
        cursor_color = user_cursor_color,
        rec_color = user_rec_color,
        arrow_color = user_arrow_color,
        button_on_color = user_button_on_color,
        button_off_color = user_button_off_color,
        button_sep_color = user_button_sep_color,
        button_size = user_button_size,
    }

    local theme_settings = ExtLoad('theme_settings', {})
    local theme_key = GetThemeKey(theme_path)

    if attach_window_title then
        local attach_settings = {
            box_x = box_x,
            box_y = box_y,
            box_w = box_w,
            box_h = box_h,
            attach_x = attach_x,
            attach_mode = attach_mode,
            measure_scale = measure_scale,
        }
        ExtSave('attach_settings', attach_settings)

        local prev_settings = theme_settings[theme_key]
        if prev_settings then
            for key in pairs(attach_settings) do
                settings[key] = prev_settings[key]
            end
        end
    end

    theme_settings[theme_key] = settings
    ExtSave('theme_settings', theme_settings)
end

function GetThemeColor(key, flag)
    local color = reaper.GetThemeColor(key, flag or 0)
    if is_windows then
        local r, g, b = reaper.ColorFromNative(color)
        color = r * 65536 + g * 256 + b
    end
    return color
end

function RGBAToHex(r, g, b, a)
    local int_color = r * 65536 + g * 256 + b
    if not a or a == 255 then return ('#%06x'):format(int_color) end
    return ('#%06x%02x'):format(int_color, a)
end

function IntToHex(int_color)
    local r, g, b = reaper.ColorFromNative(int_color)
    return RGBAToHex(r, g, b)
end

function TintIntColor(color, factor)
    local a = color & 0xFF000000
    local r = (color & 0xFF0000) >> 16
    local g = (color & 0x00FF00) >> 8
    local b = (color & 0x0000FF)

    r = (r * factor) // 1
    g = (g * factor) // 1
    b = (b * factor) // 1

    r = r < 0 and 0 or r > 255 and 255 or r
    g = g < 0 and 0 or g > 255 and 255 or g
    b = b < 0 and 0 or b > 255 and 255 or b

    return (r * 65536 + g * 256 + b) | a
end

function GetUserColor()
    local ret, color = reaper.GR_SelectColor(main_hwnd)
    if ret ~= 0 then return IntToHex(color):gsub('#', '') end
end

function SetCustomSize()
    local title = 'Size/Position'
    local captions = 'Width:,Height:,X pos:,Y pos:'

    local floor = math.floor
    local curr_vals = {floor(box_w), floor(box_h), floor(box_x), floor(box_y)}
    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 4, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = tonumber(input)
    end

    local x, y, w, h
    if input_vals[1] then w = floor(input_vals[1] + 0.5) end
    if input_vals[2] then h = floor(input_vals[2] + 0.5) end
    if input_vals[3] then x = floor(input_vals[3] + 0.5) end
    if input_vals[4] then y = floor(input_vals[4] + 0.5) end
    SetBoxCoords(x, y, w, h)

    UpdateAttachPosition()
    EnsureBoxVisible()

    SaveThemeSettings(prev_color_theme)
end

function SetCustomCornerRadius()
    local title = 'Corners'
    local captions = 'Corner radius: (e.g. 4)'

    local curr_vals_str = ('%s'):format(user_corner_radius or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_corner_radius = tonumber(input_vals[1])
    user_corner_radius = user_corner_radius and math.floor(user_corner_radius)
    is_redraw = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomFont()
    local title = 'Font'
    local captions = 'Height: (e.g.42),Family (e.g. Comic Sans):,\z
        Weight (0/400/700):,Y offset:,extrawidth=50'

    local curr_vals_str = ('%s,%s,%s,%s'):format(
        user_font_height or '',
        user_font_family or '',
        user_font_weight or '',
        user_font_yoffs or ''
    )

    local ret, inputs = reaper.GetUserInputs(title, 4, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_font_height = tonumber(input_vals[1])
    user_font_family = input_vals[2]
    if user_font_family == '' then user_font_family = nil end
    user_font_weight = tonumber(input_vals[3])
    user_font_yoffs = tonumber(input_vals[4])
    is_resize = true

    SaveThemeSettings(prev_color_theme)
end

function SetCustomButtonSize()
    local title = 'Button'
    local captions = 'Icon size: (e.g.24),extrawidth=50'

    local curr_vals_str = ('%s'):format(user_button_size or '')

    local ret, inputs = reaper.GetUserInputs(title, 1, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local input_vals = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        input_vals[#input_vals + 1] = input
    end

    user_button_size = tonumber(input_vals[1])
    is_resize = true

    SaveThemeSettings(prev_color_theme)

    if user_button_size and user_button_size // 0.4 > box_w / 1.3 then
        local msg = 'You entered a large size. The button will not be \z
        visible.\n\nReduce the size or expand Chordbox to make it show.'
        reaper.MB(msg, 'Warning', 0)
    end
end

function SetCustomColors()
    local title = 'Custom Colors'
    local captions = 'Background: (e.g. #525252),Text:,Border:,\z
        Cursor icon:,Play icon:,Record icon:,Arrow icons:,\z
        Button on:,Button off:,Button separator:'

    local curr_vals = {}
    local function AddCurrentValue(color)
        local hex_num = color and tonumber(color, 16)
        curr_vals[#curr_vals + 1] = hex_num and ('#%.6X'):format(hex_num) or ''
    end

    AddCurrentValue(user_bg_color)
    AddCurrentValue(user_text_color)
    AddCurrentValue(user_border_color)
    AddCurrentValue(user_cursor_color)
    AddCurrentValue(user_play_color)
    AddCurrentValue(user_rec_color)
    AddCurrentValue(user_arrow_color)
    AddCurrentValue(user_button_on_color)
    AddCurrentValue(user_button_off_color)
    AddCurrentValue(user_button_sep_color)

    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 10, captions, curr_vals_str)
    if not ret or inputs == curr_vals_str then return end

    local colors = {}
    local has_invalid_color = false

    local function ValidateColor(color)
        local is_valid = #color <= 8 and tonumber(color, 16)
        if not is_valid then has_invalid_color = true end
        return is_valid and color or nil
    end

    local i = 1
    for input in (inputs .. ','):gmatch('[^,]*') do
        input = input:gsub('^#', '')
        if input == '' then input = nil else input = ValidateColor(input) end
        colors[i] = input
        i = i + 1
    end

    user_bg_color = colors[1]
    user_text_color = colors[2]
    user_border_color = colors[3]
    user_cursor_color = colors[4]
    user_play_color = colors[5]
    user_rec_color = colors[6]
    user_arrow_color = colors[7]
    user_button_on_color = colors[8]
    user_button_off_color = colors[9]
    user_button_sep_color = colors[10]

    SaveThemeSettings(prev_color_theme)
    is_redraw = true

    if has_invalid_color then
        local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
        reaper.MB(msg, 'Invalid input', 0)
    end
end

function InvalidateBoxRect()
    if not box_x then return end
    reaper.JS_Window_InvalidateRect(window_hwnd, box_x, box_y,
        box_x + box_w, box_y + box_h, false)
end

function GetBitmapSize()
    local pixel_ratio = draw_scale / measure_scale
    local bm_w, bm_h = box_w * pixel_ratio, box_h * pixel_ratio
    return math.floor(bm_w), math.floor(bm_h)
end

function ClearBitmap(bm, color)
    -- Note: Clear to transparent avoids artifacts on aliased rect corners
    if is_windows then
        reaper.JS_LICE_Clear(bm, 0x00000000)
    else
        reaper.JS_LICE_Clear(bm, color & 0x00FFFFFF)
    end
end

function DrawRect(bm, color, x, y, w, h, fill, r, a)
    if a == 0 then return end
    fill = fill or 0
    r = r or 0
    a = a or 1

    if not fill or fill == 0 then
        local LICE_RoundRect = reaper.JS_LICE_RoundRect
        for _ = 1, math.max(1, draw_scale) do
            LICE_RoundRect(bm, x, y, w - 1, h - 1, r, color, a, '', true)
            x, y, w, h = x + 1, y + 1, w - 2, h - 2
        end
        return
    end

    if not r or r == 0 then
        -- Body
        reaper.JS_LICE_FillRect(bm, x, y, w, h, color, a, '')
        return
    end

    if h <= 2 * r then r = math.floor(h / 2 - 1) end
    if w <= 2 * r then r = math.floor(w / 2 - 1) end

    -- Top left corner
    local LICE_FillCircle = reaper.JS_LICE_FillCircle
    LICE_FillCircle(bm, x + r, y + r, r, color, a, '', true)
    -- Top right corner
    LICE_FillCircle(bm, x + w - r - 1, y + r, r, color, a, '', true)
    -- Bottom right corner
    LICE_FillCircle(bm, x + w - r - 1, y + h - r - 1, r, color, a, '', true)
    -- Bottom left corner
    LICE_FillCircle(bm, x + r, y + h - r - 1, r, color, a, '', true)
    -- Ends
    reaper.JS_LICE_FillRect(bm, x, y + r, r, h - r * 2, color, a, '')
    reaper.JS_LICE_FillRect(bm, x + w - r, y + r, r, h - r * 2, color, a, '')
    -- Body and sides
    reaper.JS_LICE_FillRect(bm, x + r, y, w - r * 2, h, color, a, '')
end

function DrawBackground(bm, bg_color, w, h, corner_r, a)
    if a == 0 then return end
    if not bg_bitmap then
        bg_bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
        prev_bg_color = nil
    end

    if bg_color ~= prev_bg_color or corner_r ~= prev_bg_corner_r then
        prev_bg_color = bg_color
        prev_bg_corner_r = corner_r
        ClearBitmap(bg_bitmap, bg_color)
        DrawRect(bg_bitmap, bg_color, 0, 0, w, h, true, corner_r)
    end
    reaper.JS_LICE_Blit(bm, 0, 0, bg_bitmap, 0, 0, w, h, a, 'COPY')
end

local LoadCursor = reaper.JS_Mouse_LoadCursor
local normal_cursor = LoadCursor(is_windows and 32512 or 0)
local diag1_resize_cursor = LoadCursor(is_linux and 32642 or 32643)
local diag2_resize_cursor = LoadCursor(is_linux and 32643 or 32642)
local horz_resize_cursor = LoadCursor(32644)
local vert_resize_cursor = LoadCursor(32645)
local move_cursor = LoadCursor(32646)

local Intercept = reaper.JS_WindowMessage_Intercept
local Release = reaper.JS_WindowMessage_Release
local Peek = reaper.JS_WindowMessage_Peek

local is_edit_mode = ExtLoad('is_edit_mode', true)

local prev_cursor = normal_cursor
local is_intercept = false

local intercepts = {
    {timestamp = 0, passthrough = false, message = 'WM_SETCURSOR'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_LBUTTONUP'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONDOWN'},
    {timestamp = 0, passthrough = false, message = 'WM_RBUTTONUP'},
}

function SetCursor(cursor)
    if not is_intercept then return end
    reaper.JS_Mouse_SetCursor(cursor)
    prev_cursor = cursor
end

function StartIntercepts()
    if is_intercept then return end
    is_intercept = true
    local _, intercept_str = reaper.JS_WindowMessage_ListIntercepts(window_hwnd)
    local blocked_messages = {}
    for entry in (intercept_str .. ','):gmatch('(.-),') do
        local blocked_message = entry:match('(.-):block')
        if blocked_message then blocked_messages[blocked_message] = true end
    end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        if blocked_messages[msg] then
            is_intercept = false
            return
        end
    end
    for _, intercept in ipairs(intercepts) do
        Intercept(window_hwnd, intercept.message, intercept.passthrough)
    end
end

function EndIntercepts()
    if not is_intercept then return end
    if prev_cursor ~= normal_cursor then
        SetCursor(normal_cursor)
    end
    for _, intercept in ipairs(intercepts) do
        Release(window_hwnd, intercept.message)
        intercept.timestamp = 0
    end
    is_intercept = false
    prev_cursor = -1
end

function SetEditMode(mode)
    is_edit_mode = mode
    ExtSave('is_edit_mode', mode)
end

function PeekIntercepts(m_x, m_y)
    if not is_intercept then return end
    for _, intercept in ipairs(intercepts) do
        local msg = intercept.message
        local ret, _, time = Peek(window_hwnd, msg)

        if ret and time ~= intercept.timestamp then
            intercept.timestamp = time

            if msg == 'WM_LBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_left_click = true
                if is_edit_mode then
                    drag_x = m_x
                    drag_y = m_y
                end
            end

            if msg == 'WM_LBUTTONUP' then
                if not is_left_click then return end
                if OnLeftClick then OnLeftClick(m_x - box_x, m_y - box_y) end
            end

            if msg == 'WM_RBUTTONDOWN' then
                -- Avoid new clicks after showing menu
                if menu_time and reaper.time_precise() < menu_time + 0.05 then
                    return
                end
                is_right_click = true
            end

            if msg == 'WM_RBUTTONUP' then
                if not is_right_click then return end
                if OnRightClick then OnRightClick(m_x - box_x, m_y - box_y) end
            end
        end
    end
end

function ShowMenu(menu)
    SetCursor(normal_cursor)

    local focus_hwnd = reaper.JS_Window_GetFocus()
    -- Open gfx window
    gfx.clear = GetThemeColor('col_main_bg2')
    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local window_x, window_y = ClientToScreen(window_hwnd, 0, 0)
    local m = Scale(4, measure_scale)
    gfx.init('Box Menu', Scale(24, measure_scale), 0, 0,
        window_x + m, window_y + m)

    -- Open menu at bottom left corner
    local menu_x, menu_y = ClientToScreen(window_hwnd, box_x, box_y + box_h)
    gfx.x, gfx.y = gfx.screentoclient(menu_x, menu_y)

    -- Hide gfx window
    local gfx_hwnd = reaper.JS_Window_Find('Box Menu', true)
    reaper.JS_Window_SetOpacity(gfx_hwnd, 'ALPHA', 0)

    if is_linux then
        reaper.JS_Window_SetStyle(gfx_hwnd, 'POPUP')
    else
        reaper.JS_Window_Show(gfx_hwnd, 'HIDE')
        if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    end

    -- Show menu
    local menu_str = CreateMenuRecursive(menu)
    local ret = gfx.showmenu(menu_str)
    gfx.quit()

    if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
    if ret > 0 then ReturnMenuRecursive(menu, ret) end

    -- Make sure that user can click box to close menu
    menu_time = reaper.time_precise()
    is_left_click = false
    is_right_click = false
    drag_x = nil
end

function GetStatusWindowClientRect()
    -- Get status window coordinates
    local status_hwnd = reaper.JS_Window_FindChildByID(window_hwnd, 1010)
    local _, st_l, st_t, st_r, st_b = reaper.JS_Window_GetRect(status_hwnd)
    st_l, st_t = reaper.JS_Window_ScreenToClient(window_hwnd, st_l, st_t)
    st_r, st_b = reaper.JS_Window_ScreenToClient(window_hwnd, st_r, st_b)

    -- Note: Window can be out of transport bounds
    st_l = math.max(st_l, 0)
    st_t = math.max(st_t, 0)
    st_r = math.min(st_r, window_w)
    st_b = math.min(st_b, window_h)

    return st_l, st_t, st_r, st_b
end

function SetBoxCoords(x, y, w, h)
    if w == 0 or h == 0 then return end
    local has_pos_changed = x and x ~= box_x or y and y ~= box_y
    local has_size_changed = w and w ~= box_w or h and h ~= box_h
    if not has_pos_changed and not has_size_changed then return end

    if has_pos_changed then is_redraw = true end
    if has_size_changed then is_resize = true end

    -- Redraw previous area
    InvalidateBoxRect()

    box_x, box_y, box_w, box_h = x or box_x, y or box_y, w or box_w, h or box_h

    -- Redraw new area
    InvalidateBoxRect()

    if not is_resize then
        -- Change bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap, 0, 0,
            GetBitmapSize())
    end
end

function UpdateAttachPosition()
    local mode = GetAttachMode()
    local new_x
    if mode == 1 then new_x = box_x end
    if mode == 2 then new_x = box_x - window_w end
    if mode == 3 then
        local st_l = GetStatusWindowClientRect()
        new_x = box_x - st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_x = box_x - st_r
    end
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if not attach_window_title and is_centered then
        attach_center_x = new_x
    else
        attach_x = new_x
    end
end

function GetAttachMode()
    local mode = attach_mode or attach_center_mode
    if attach_window_title then
        -- Note: Status window options are only valid when attached to transport
        if mode and mode > 2 then mode = mode - 2 end
    else
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then mode = attach_center_mode or attach_mode end
    end
    return mode
end

function SetAttachMode(mode)
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if attach_window_title or not is_centered then
        attach_mode = mode
    else
        attach_center_mode = mode
    end
end

function GetAttachPosition()
    local x = attach_x or attach_center_x
    if not x then return end
    if not attach_window_title then
        local is_centered = reaper.GetToggleCommandState(40533) == 1
        if is_centered then x = attach_center_x or attach_x end
    end

    local mode = GetAttachMode()
    local new_box_x
    if mode == 1 then
        new_box_x = x
    end
    if mode == 2 then
        new_box_x = x + window_w
    end
    if mode == 3 or mode == 4 then
        local st_l = GetStatusWindowClientRect()
        new_box_x = x + st_l
    end
    if mode == 4 then
        local _, _, st_r = GetStatusWindowClientRect()
        new_box_x = x + st_r
    end
    return new_box_x
end

function EnsureBoxVisible()
    -- Ensure position/size is within bounds
    if window_w == 0 or window_h == 0 then return end
    if not box_w or not box_h then return end
    local w = math.max(min_box_size, math.min(box_w, window_w))
    local h = math.max(min_box_size, math.min(box_h, window_h))

    local x = math.max(0, math.min(window_w - w, box_x))
    local y = math.max(0, math.min(window_h - h, box_y))

    if attach_window_title then
        SetBoxCoords(x, y, w, h)
        return
    end

    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()

    local st_x = st_l
    local st_y = st_t
    local st_w = st_r - st_l
    local st_h = math.abs(st_b - st_t)

    -- Check if bitmap overlaps or contains status window
    local is_left = x + w < st_x
    local is_right = x > st_x + st_w
    local is_above = y + h < st_y
    local is_below = y > st_y + st_h

    local is_overlap = not (is_left or is_right or is_above or is_below)
    local is_contained = x > st_l and x < st_r and y > st_t and y < st_b

    if is_overlap or is_contained then
        -- Move bitmap to not overlap with status window
        local space_l = st_l
        local space_r = window_w - st_r
        local space_t = st_t
        local space_b = window_h - st_b

        local new_l_x = st_l - w
        local new_r_x = st_r
        local new_t_y = st_t - h
        local new_b_y = st_b

        local move_x = 0
        local move_y = 0

        if space_l >= w or space_r >= w then
            if space_l >= w and space_r >= w then
                -- Space on both sides, move to closest position
                move_x = x - new_l_x < new_r_x - x and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_x = space_r > space_l and 1 or -1
            end
        elseif space_t >= h or space_b >= h then
            if space_t >= h and space_b >= h then
                -- Space on both sides, move to closest position
                move_y = y - new_t_y < new_b_y - y and -1 or 1
            else
                -- Space only on one side, move accordingly
                move_y = space_b > space_t and 1 or -1
            end
        else
            -- Check if more vertical or horizontal space, move accordingly
            if math.max(space_l, space_r) > math.max(space_t, space_b) then
                move_x = space_r > space_l and 1 or -1
            else
                move_y = space_b > space_t and 1 or -1
            end
        end

        if move_x == -1 then
            -- Move left
            x = new_l_x
            w = math.min(w, space_l)
        end
        if move_x == 1 then
            -- Move right
            x = new_r_x
            w = math.min(w, space_r)
        end
        if move_y == -1 then
            -- Move top
            y = new_t_y
            h = math.min(h, space_t)
        end
        if move_y == 1 then
            -- Move bottom
            y = new_b_y
            h = math.min(h, space_b)
        end

        -- Ensure position/size is within bounds after move
        w = math.max(min_box_size, math.min(w, window_w))
        h = math.max(min_box_size, math.min(h, window_h))

        x = math.max(0, math.min(window_w - w, x))
        y = math.max(0, math.min(window_h - h, y))
    end

    SetBoxCoords(x, y, w, h)
end

function FindInitialPosition()
    -- Get status window coordinates
    local st_l, st_t, st_r, st_b = GetStatusWindowClientRect()
    local st_y = st_t
    local st_h = math.abs(st_b - st_t)

    -- Set initial position that matches status window
    box_x = 0
    box_y = st_y
    box_w = st_h * 8 // 2
    box_h = st_h

    -- Add small vertical margin if status window takes up full transport height
    if st_h >= window_h - Scale(4, measure_scale) then
        box_y = box_y + Scale(2, measure_scale)
        box_h = box_h - Scale(4, measure_scale)
    end

    -- Now we'll use GetThingFromPoint to get empty transport areas on x axis
    local st_mid_y = st_y + box_h // 2
    local empty_areas = {}

    local size = 0
    local sel_cnt = 0
    local bpm_x

    local function AddEmptyArea(x, y, align)
        local _, thing = reaper.GetThingFromPoint(x, y)

        if thing == 'trans' then
            -- Empty transport area, increase size
            size = size + 1
        else
            -- Remember x position of BPM button
            if not bpm_x and thing:sub(1, 9) == 'trans.bpm' then
                bpm_x = x
            end
            if size > 0 then
                -- Add previous area
                if sel_cnt == 0 and size > min_box_size then
                    local area = {size = size, r = x, align = align}
                    empty_areas[#empty_areas + 1] = area
                end
                size = 0
                sel_cnt = 0
            end

            -- Skip areas to the right of selection (selection textboxes)
            if thing == 'trans.sel' then sel_cnt = sel_cnt + 1 end
        end
    end

    local ClientToScreen = reaper.JS_Window_ClientToScreen
    local x_start, y = ClientToScreen(window_hwnd, 0, st_mid_y)
    local x_end = ClientToScreen(window_hwnd, st_l, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, 1)
    end
    AddEmptyArea(x_end, -1, 1)

    x_start = ClientToScreen(window_hwnd, st_r, st_mid_y)
    x_end = ClientToScreen(window_hwnd, window_w, st_mid_y)

    for x = x_start, x_end do
        AddEmptyArea(x, y, -1)
    end
    AddEmptyArea(x_end, -1, 1)

    local target_area

    if bpm_x then
        local min_bpm_distance
        for _, area in ipairs(empty_areas) do
            -- Check if area is large enough
            if area.size > box_w * 0.7 then
                local area_x = area.r > bpm_x and area.r or area.r - area.size
                local diff = bpm_x - area_x
                local distance = math.abs(diff)
                -- Check distance to bpm window
                if not min_bpm_distance or distance < min_bpm_distance then
                    min_bpm_distance = distance
                    target_area = area
                    target_area.align = area.r > bpm_x and -1 or 1
                end
            end
        end
    end

    if not target_area then
        -- Find largest empty area
        local largest_area_size = 0
        for _, area in ipairs(empty_areas) do
            if area.size > largest_area_size then
                target_area = area
                largest_area_size = area.size
            end
        end
    end

    if target_area then
        -- Make bitmap a bit larger if it'll then fully fit empty space
        if target_area.size < box_w * 1.5 then box_w = target_area.size end

        -- Add margin
        local m = box_h // 6
        box_w = math.max(min_box_size, math.min(target_area.size - 2 * m, box_w))

        -- Convert back to client coordinates
        local r = target_area.r
        r = reaper.JS_Window_ScreenToClient(window_hwnd, r, st_mid_y)

        -- Place bitmap (x pos) in empty target area (based on alignment)
        if target_area.align > 0 then
            box_x = math.max(0, r - box_w - m)
            SetAttachMode(box_x < st_r and 3 or 2)
        else
            box_x = math.max(0, r - target_area.size + m)
            SetAttachMode(box_x < st_r and 1 or 4)
        end
    else
        SetAttachMode(box_x < st_r and 1 or 2)
    end
    UpdateAttachPosition()
end

function WaitForAttachedWindow()
    if attach_window_title == 'REAPER Main Window' then return true end
    if attach_window_title == 'Active MIDI editor' then return true end
    return attach_window_wait == attach_window_title
end

function FindAttachedWindow()
    local hwnd
    local window_cnt = 0
    if attach_window_title == 'REAPER Main Window' then
        hwnd = main_hwnd
    elseif attach_window_title == 'Active MIDI editor' then
        hwnd = reaper.MIDIEditor_GetActive()
    else
        local title = attach_window_title or transport_title
        local cnt, list = reaper.JS_Window_ListFind(title, true)
        window_cnt = cnt
        if window_cnt > 0 then
            local first_hwnd
            local main_child
            for addr in (list .. ','):gmatch('(.-),') do
                local handle = reaper.JS_Window_HandleFromAddress(addr)
                first_hwnd = first_hwnd or handle
                -- Check if only one of the windows is child of main window
                -- (for case when running multiple reaper instances)
                if reaper.JS_Window_IsChild(main_hwnd, hwnd) then
                    if main_child then
                        main_child = nil
                        break
                    else
                        main_child = handle
                    end
                end
            end
            if main_child then
                hwnd = main_child
                window_cnt = 1
            else
                hwnd = first_hwnd
            end
        end

        if hwnd and attach_window_title then
            reaper.SetExtState(extname, 'attach_wait', attach_window_title, true)
        end
    end
    if hwnd and attach_window_child_id then
        hwnd = reaper.JS_Window_FindChildByID(hwnd, attach_window_child_id)
    end
    return hwnd, window_cnt
end

function SaveAttachedWindow(title, child_id)
    if not title or title == transport_title and not child_id then
        attach_window_title = nil
        attach_window_child_id = nil
        ExtSave('attach_title', nil)
        ExtSave('attach_child_id', nil)
        ExtSave('attach_wait', nil)
        ExtSave('attach_settings', nil)
    else
        attach_window_title = title
        attach_window_child_id = child_id
        ExtSave('attach_title', title)
        ExtSave('attach_child_id', child_id)
        ExtSave('attach_wait', nil)
    end
end

function Main()
    -- Find window
    if not window_hwnd or not reaper.ValidatePtr(window_hwnd, 'HWND*') then
        local time = reaper.time_precise()
        if not prev_time or time > prev_time + 0.5 then
            prev_time = time
            local top_window_cnt = reaper.JS_Window_ArrayAllTop(top_window_array)
            if top_window_cnt ~= prev_top_window_cnt then
                prev_top_window_cnt = top_window_cnt
                window_hwnd = FindAttachedWindow()
                is_resize = true
            end
        end
    elseif attach_window_title and not attach_window_child_id and not drag_x then
        -- Check attached window title changes (e.g. when switching toolbar)
        local curr_title = reaper.JS_Window_GetTitle(window_hwnd)
        if curr_title ~= attach_window_title then
            if bitmap then
                reaper.JS_Composite_Unlink(window_hwnd, bitmap)
                reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
            end
            EndIntercepts()
            InvalidateBoxRect()
            prev_window_hwnd = window_hwnd
            window_hwnd = nil
        end
    end

    if prev_window_hwnd and reaper.ValidatePtr(prev_window_hwnd, 'HWND*') and
        reaper.JS_Window_GetTitle(prev_window_hwnd) == attach_window_title then
        window_hwnd = prev_window_hwnd
        prev_window_hwnd = nil
    end

    -- Go idle if window is not found/visible
    if not window_hwnd or not reaper.JS_Window_IsVisible(window_hwnd) then
        reaper.defer(Main)
        return
    end

    mouse_x, mouse_y = GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(mouse_x, mouse_y)

    do
        local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
        window_w, window_h = w, h
    end

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        SetThemeIntegration(1)
        prev_color_theme = color_theme
        if not LoadThemeSettings(color_theme) then
            FindInitialPosition()
        end
        EnsureBoxVisible()
        is_resize = true
    end

    -- Detect changes to window size
    if window_w ~= prev_window_w or window_h ~= prev_window_h then
        local prev_measure_scale, prev_draw_scale = measure_scale, draw_scale
        measure_scale, draw_scale = GetTransportScale()

        if draw_scale ~= prev_draw_scale then
            local scale_factor = draw_scale / prev_draw_scale
            user_font_height = Scale(user_font_height, scale_factor)
            user_font_yoffs = Scale(user_font_yoffs, scale_factor)
            user_corner_radius = Scale(user_corner_radius, scale_factor)
            user_button_size = Scale(user_button_size, scale_factor)
            is_resize = true
        end
        if measure_scale ~= prev_measure_scale then
            min_box_size = Scale(12, measure_scale)

            local scale_factor = measure_scale / prev_measure_scale
            local new_box_x = Scale(box_x, scale_factor)
            local new_box_y = Scale(box_y, scale_factor)
            local new_box_w = Scale(box_w, scale_factor)
            local new_box_h = Scale(box_h, scale_factor)

            attach_x = Scale(attach_x, scale_factor)
            attach_center_x = Scale(attach_center_x, scale_factor)
            if attach_x or attach_center_x then new_box_x = GetAttachPosition() end

            SetBoxCoords(new_box_x, new_box_y, new_box_w, new_box_h)
            EnsureBoxVisible()
            is_resize = true
        end
        if prev_window_w then
            -- Move bitmap based on attached position
            local new_box_x = GetAttachPosition()
            if new_box_x then SetBoxCoords(new_box_x) end
            EnsureBoxVisible()
        end
        prev_window_w = window_w
        prev_window_h = window_h
    end

    -- Detect centered transport toggle
    local is_centered = reaper.GetToggleCommandState(40533) == 1
    if is_centered ~= prev_is_centered then
        prev_is_centered = is_centered
        local new_box_x = GetAttachPosition()
        if new_box_x then SetBoxCoords(new_box_x) end
        EnsureBoxVisible()
    end

    local is_hovered = false

    if hover_hwnd == window_hwnd or drag_x then
        local ScreenToClient = reaper.JS_Window_ScreenToClient
        local m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)
        -- Handle drag move/resize
        if drag_x and (drag_x ~= m_x or drag_y ~= m_y) then
            if resize_flags > 0 then
                if resize_flags & 1 == 1 then
                    local box_r = box_x + box_w
                    local new_box_w = math.max(min_box_size, box_r - m_x)
                    local new_box_x = box_r - new_box_w
                    SetBoxCoords(new_box_x, nil, new_box_w, nil)
                end
                if resize_flags & 2 == 2 then
                    local box_b = box_y + box_h
                    local new_box_h = math.max(min_box_size, box_b - m_y)
                    local new_box_y = box_b - new_box_h
                    SetBoxCoords(nil, new_box_y, nil, new_box_h)
                end
                if resize_flags & 4 == 4 then
                    local new_box_w = math.max(min_box_size, m_x - box_x)
                    SetBoxCoords(nil, nil, new_box_w, nil)
                end
                if resize_flags & 8 == 8 then
                    local new_box_h = math.max(min_box_size, m_y - box_y)
                    SetBoxCoords(nil, nil, nil, new_box_h)
                end
                is_resize = true
            else
                prev_box_w = prev_box_w or box_w
                prev_box_h = prev_box_h or box_h
                prev_box_x = prev_box_x or box_x
                prev_box_y = prev_box_y or box_y

                -- Move box to hovered window
                if hover_hwnd and hover_hwnd ~= window_hwnd then
                    prev_attach_hwnd = prev_attach_hwnd or window_hwnd
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
                    -- Redraw previous area
                    window_hwnd = hover_hwnd
                    reaper.JS_Window_SetFocus(hover_hwnd)

                    -- Get relative position to bitmap top left corner
                    local drag_x_diff = drag_x - box_x
                    local drag_y_diff = drag_y - box_y

                    -- Get new mouse window position
                    m_x, m_y = ScreenToClient(window_hwnd, mouse_x, mouse_y)

                    -- Set bitmap coordinates with relative position
                    -- Note: Avoid SetBoxCoords as it doesn't allow going out
                    -- of bounds
                    box_x = m_x - drag_x_diff
                    box_y = m_y - drag_y_diff
                    drag_x = box_x + drag_x_diff
                    drag_y = box_y + drag_y_diff

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                else
                    -- Move box inside window
                    local new_box_x = box_x + m_x - drag_x
                    local new_box_y = box_y + m_y - drag_y
                    SetBoxCoords(new_box_x, new_box_y)
                end
                if m_x > 0 and m_y > 0 and m_x < window_w and m_y < window_h then
                    SetCursor(move_cursor)
                    resize_flags = -1
                    resize_cursor = nil
                end
            end
            drag_x = m_x
            drag_y = m_y
            is_left_click = false
        end

        local m = Scale(4, measure_scale)
        is_hovered = m_x > box_x - m and m_y > box_y - m and
            m_x < box_x + box_w + m and m_y < box_y + box_h + m

        if is_hovered and hover_hwnd == window_hwnd then
            if not is_intercept and not drag_x then
                if OnHoverStart then OnHoverStart() end
            end

            StartIntercepts()
            PeekIntercepts(m_x, m_y)
            if is_edit_mode and not drag_x then
                local new_resize = 0
                local cursor = normal_cursor

                local diff_l = math.abs(box_x - m_x)
                local diff_t = math.abs(box_y - m_y)
                local diff_r = math.abs(box_x + box_w - m_x)
                local diff_b = math.abs(box_y + box_h - m_y)

                if diff_l < m then
                    new_resize = 1
                    cursor = horz_resize_cursor
                end

                if diff_t < m then
                    new_resize = 2
                    cursor = vert_resize_cursor
                end

                if diff_r < m then
                    new_resize = 4
                    cursor = horz_resize_cursor
                end

                if diff_b < m then
                    new_resize = 8
                    cursor = vert_resize_cursor
                end

                local d_m = 2 * m

                if diff_l < d_m and diff_t < d_m then
                    new_resize = 3
                    cursor = diag2_resize_cursor
                end

                if diff_t < d_m and diff_r < d_m then
                    new_resize = 6
                    cursor = diag1_resize_cursor
                end

                if diff_r < d_m and diff_b < d_m then
                    new_resize = 12
                    cursor = diag2_resize_cursor
                end

                if diff_b < d_m and diff_l < d_m then
                    new_resize = 9
                    cursor = diag1_resize_cursor
                end

                if resize_flags ~= new_resize then
                    resize_flags = new_resize
                    resize_cursor = cursor
                    is_redraw = true
                end
            end
            if resize_cursor then
                SetCursor(resize_cursor)
            elseif not drag_x then
                SetCursor(normal_cursor)
            end
            if OnHover and not drag_x then OnHover(m_x - box_x, m_y - box_y) end
        else
            is_left_click = false
            is_right_click = false
            if resize_flags > 0 and not drag_x then
                resize_flags = 0
                resize_cursor = nil
                is_redraw = true
            end
            if is_intercept then
                if OnHoverEnd then OnHoverEnd() end
            end
            EndIntercepts()
        end

        -- Release drags / left clicks / right clicks
        if drag_x and reaper.JS_Mouse_GetState(3) == 0 then
            -- Check if new attached window is valid
            if drag_x and prev_attach_hwnd and window_hwnd ~= prev_attach_hwnd then
                local is_reset = false
                local target_hwnd = window_hwnd
                local title = reaper.JS_Window_GetTitle(target_hwnd)

                local child_id = nil
                -- If window has no title, check if window has ID and parent has title
                if title == '' then
                    local parent_hwnd = reaper.JS_Window_GetParent(target_hwnd)
                    if reaper.ValidatePtr(parent_hwnd, 'HWND*') then
                        local id = reaper.JS_Window_GetLong(target_hwnd, 'ID')
                        id = tonumber(id)
                        if id and id > 0 then
                            child_id = id
                            title = reaper.JS_Window_GetTitle(parent_hwnd)
                            target_hwnd = parent_hwnd
                        end
                    end
                end

                -- Do not allow windows with empty titles
                if title == '' then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Window does not have a title.'
                    reaper.MB(msg:format(box_name), 'Notice', 0)
                    is_reset = true
                end

                -- Do not allow titles with newline characters
                if not is_reset and title:match('\n') then
                    local msg = 'Can not attach %s to this window.\n\n\z
                        Invalid window title:\n\nTITLE: %s'
                    reaper.MB(msg:format(box_name, title), 'Notice', 0)
                end

                local found_hwnd
                if not is_reset then
                    -- Check if new attached window can be found via Window_Find
                    local window_cnt, list = reaper.JS_Window_ListFind(title, 1)
                    if window_cnt > 1 then
                        local msg = 'Can not attach %s to this window. \z
                            %d windows have the same title!\n\n\z
                            TITLE: %s\n\nIf this window is a toolbar, make sure \z
                            that it is only open once (not in toolbar docker) and \z
                            consider giving it a unique title.'
                        msg = msg:format(box_name, window_cnt, title)
                        reaper.MB(msg, 'Notice', 0)
                        is_reset = true
                    elseif window_cnt == 0 then
                        local msg = 'Can not attach %s to this window.\z
                            \n\nCould not find window by title.\n\nTITLE: %s'
                        reaper.MB(msg:format(box_name, title), 'Notice', 0)
                        is_reset = true
                    else
                        found_hwnd = reaper.JS_Window_HandleFromAddress(list)
                        if found_hwnd ~= target_hwnd then
                            local msg = 'Can not attach %s to this \z
                                window.\n\nHandle missmatch'
                            reaper.MB(msg:format(box_name), 'Notice', 0)
                            is_reset = true
                        end
                    end
                end

                if not is_reset then
                    is_reset = true
                    -- Save accessible windows by custom ID instead of title
                    if target_hwnd == main_hwnd then
                        title = 'REAPER Main Window'
                    end
                    if target_hwnd == reaper.MIDIEditor_GetActive() then
                        title = 'Active MIDI editor'
                    end

                    -- Prompt user to confirm new attachment
                    local msg = '%s will be attached to this window:\z
                            \n\nTITLE: %s%s\n\nProceed?'
                    local id_text = ''
                    if child_id then id_text = ('\nID: %d'):format(child_id) end
                    msg = msg:format(box_name, title, id_text)

                    local ret = reaper.MB(msg, 'Notice', 4)
                    if ret == 6 then
                        -- Save info on new attachment for next script startup
                        SaveAttachedWindow(title, child_id)
                        is_reset = false
                    end
                end

                if is_reset then
                    -- Move box back to previous window (pre-drag)
                    EndIntercepts()
                    InvalidateBoxRect()
                    reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)

                    window_hwnd = prev_attach_hwnd
                    reaper.JS_Window_SetFocus(prev_attach_hwnd)

                    box_w = prev_box_w
                    box_h = prev_box_h
                    box_x = prev_box_x
                    box_y = prev_box_y

                    StartIntercepts()

                    -- Remeasure window size
                    local _, w, h = reaper.JS_Window_GetClientSize(window_hwnd)
                    window_w, window_h = w, h

                    -- Avoid edge attachment
                    prev_window_w = nil
                    is_resize = true
                end
            end
            EnsureBoxVisible()
            UpdateAttachPosition()
            SaveThemeSettings(color_theme)
            drag_x = nil
            drag_y = nil
            is_redraw = true
            prev_attach_hwnd = nil
            prev_box_w = nil
            prev_box_h = nil
            prev_box_x = nil
            prev_box_y = nil
        end
    else
        if is_intercept then
            if OnHoverEnd then OnHoverEnd() end
        end
        EndIntercepts()
    end

    if is_resize then
        -- Prepare LICE bitmap for drawing
        if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
        if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
        if button_bitmap then reaper.JS_LICE_DestroyBitmap(button_bitmap) end
        local bm_w, bm_h = GetBitmapSize()
        bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
        bg_bitmap = nil
        button_bitmap = nil

        local font_family = user_font_family or 'Arial'
        -- Binary search to find font size that fits target height
        local default_h = Scale(14, draw_scale)
        local target_h = math.max(math.min(default_h, bm_h), bm_h // 2.5)
        if user_font_height then target_h = math.min(user_font_height, bm_h) end

        local lo, hi, mid = 1, target_h * 2, nil
        font_size = lo
        while lo <= hi do
            mid = math.floor((lo + hi) / 2)
            gfx.setfont(1, font_family, mid)
            local curr_h = math.max(1, select(2, gfx.measurechar(70)))
            if curr_h <= target_h then
                font_size = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end
        if font_size ~= mid then gfx.setfont(1, font_family, font_size) end

        -- Create LICE font
        if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
        lice_font = reaper.JS_LICE_CreateFont()

        local GDI_CreateFont = reaper.JS_GDI_CreateFont
        local font_weight = user_font_weight or 0
        local gdi = GDI_CreateFont(font_size, font_weight, 0, 0, 0, 0,
            font_family)
        reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
        reaper.JS_GDI_DeleteObject(gdi)

        -- Set bitmap draw coordinates
        reaper.JS_Composite_Delay(window_hwnd, comp_delay, comp_delay * 1.5, 2)
        reaper.JS_Composite(window_hwnd, box_x, box_y, box_w, box_h, bitmap,
            0, 0, bm_w, bm_h)
        is_resize = false
        is_redraw = true
    end

    if OnRun then OnRun() end

    if is_redraw then
        DrawBitmap(bitmap, GetBitmapSize())
        InvalidateBoxRect()
        is_redraw = false
    end

    reaper.defer(Main)
end

-------------------------------- BOX CODE -----------------------------------

comp_fps = ExtLoad('comp_fps', 30)
comp_delay = comp_fps == 0 and 0 or 1 / comp_fps

transport_title = reaper.JS_Localize('Transport', 'common')
attach_window_title = ExtLoad('attach_title')
attach_window_wait = ExtLoad('attach_wait')
attach_window_child_id = ExtLoad('attach_child_id')

measure_scale, draw_scale = GetTransportScale()
-- Smallest size the box is allowed to have (width and height in pixels)
min_box_size = Scale(12, measure_scale)

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)

    if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
    if bg_bitmap then reaper.JS_LICE_DestroyBitmap(bg_bitmap) end
    if button_bitmap then reaper.JS_LICE_DestroyBitmap(button_bitmap) end
    if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end
    if reaper.ValidatePtr(window_hwnd, 'HWND*') then
        reaper.JS_Composite_Delay(window_hwnd, 0, 0, 0)
        InvalidateBoxRect()
        EndIntercepts()
    end
end

if attach_window_title then
    local is_reset = false
    -- Give option to move box back to transport when attached window
    -- is not found upon script startup (or when multiple windows are found)
    local window_cnt = 0
    window_hwnd, window_cnt = FindAttachedWindow()

    if window_cnt > 1 then
        local msg = 'Found %d windows with the same title.\n\n\z
            Move %s back to transport?'
        local ret = reaper.MB(msg:format(window_cnt, box_name), box_name, 4)
        is_reset = ret == 6
        ExtSave('start_cnt', nil)
    end

    if not window_hwnd and not WaitForAttachedWindow() then
        local msg = 'Could not find window.\n\nTITLE: %s\n\nWait for \z
            window to open?'
        local ret = reaper.MB(msg:format(attach_window_title), box_name, 4)
        is_reset = ret ~= 6
        if is_reset then
            msg = 'Moved %s back to transport'
            reaper.MB(msg:format(box_name), box_name, 0)
        end
        ExtSave('start_cnt', nil)
    end

    -- Give option to move box back to transport when user quickly toggles
    -- the script 3 times in a row (in 3 seconds)
    local curr_time = reaper.time_precise()
    local start_cnt = ExtLoad('start_cnt', 1)
    local start_time = ExtLoad('start_time', curr_time)

    -- Check if more than 3 seconds have passed
    if math.abs(start_time - curr_time) > 3 then
        start_cnt = 1
        ExtSave('start_cnt', nil)
        ExtSave('start_time', nil)
    else
        start_cnt = start_cnt + 1
        -- Check if script has started 3 times
        if start_cnt > 3 then
            start_cnt = nil
            curr_time = nil
            local msg = 'Move %s back to transport?'
            local ret = reaper.MB(msg:format(box_name), box_name, 4)
            is_reset = ret == 6
        end
        ExtSave('start_cnt', start_cnt)
        ExtSave('start_time', curr_time)
    end

    -- Move box back to transport
    if is_reset then
        SaveAttachedWindow(nil)
        EndIntercepts()
        window_hwnd = nil
        prev_top_window_cnt = nil
    end
end

reaper.atexit(Exit)
reaper.defer(Main)

-------------------------------- CHORDBOX -----------------------------------

local sel_track

local input_timer
local input_chord_name = ''
local prev_input_chord_name = ''
local input_note_map = {}
local input_note_cnt = 0

local prev_input_idx

local curr_chords
local take_note_map = {}
local prev_take_notes = {}
local cleanup_time = 0

local use_compact = ExtLoad('compact', 1) == 1
local use_inversions = ExtLoad('inversions', 1) == 1
local use_omissions = ExtLoad('omissions', 0) == 1
local use_major = ExtLoad('major', 0) == 1
local use_solfege = ExtLoad('solfege', 0) == 1
local use_sharps = ExtLoad('sharps', 0) == 1

local chord_track_name = ExtLoad('chord_track_name', 'Chords')
local reuse_chord_track = ExtLoad('reuse_chord_track', 0) == 1

local prev_is_button_hovered
local is_toggle = ExtLoad('toggle', 1) == 1
local detect_mode_on = ExtLoad('detect_mode_on', 15)
local detect_mode_off = ExtLoad('detect_mode_off', 1)
local detect_mode = is_toggle and detect_mode_on or detect_mode_off
local label = ExtLoad('label', 'Chord')

local curr_chord_names
local chord_names = {}

-- Dyads
chord_names['1 2'] = {expanded = ' minor 2nd', compact = 'm2'}
chord_names['1 3'] = {expanded = ' major 2nd', compact = 'M2'}
chord_names['1 4'] = {expanded = ' minor 3rd', compact = 'm3'}
chord_names['1 5'] = {expanded = ' major 3rd', compact = 'M3'}
chord_names['1 6'] = {expanded = ' perfect 4th', compact = 'P4'}
chord_names['1 7'] = {expanded = '5-', compact = '5-'}
chord_names['1 8'] = {expanded = '5', compact = '5'}
chord_names['1 9'] = {expanded = ' minor 6th', compact = 'm6'}
chord_names['1 10'] = {expanded = ' major 6th', compact = 'M6'}
chord_names['1 11'] = {expanded = ' minor 7th', compact = 'm7'}
chord_names['1 12'] = {expanded = ' major 7th', compact = 'M7'}
chord_names['1 13'] = {expanded = ' octave', compact = 'P8'}
-- Compound intervals
chord_names['1 14'] = {expanded = ' minor 9th', compact = 'm9'}
chord_names['1 15'] = {expanded = ' major 9th', compact = 'M9'}
chord_names['1 16'] = {expanded = ' minor 10th', compact = 'm10'}
chord_names['1 17'] = {expanded = ' major 10th', compact = 'M10'}
chord_names['1 18'] = {expanded = ' perfect 11th', compact = 'P11'}
chord_names['1 19'] = {expanded = ' minor 12th', compact = 'm12'}
chord_names['1 20'] = {expanded = ' perfect 12th', compact = 'P12'}
chord_names['1 21'] = {expanded = ' minor 13th', compact = 'm13'}
chord_names['1 22'] = {expanded = ' major 13th', compact = 'M13'}
chord_names['1 23'] = {expanded = ' minor 14th', compact = 'm14'}
chord_names['1 24'] = {expanded = ' major 14th', compact = 'M14'}

-- Major chords
chord_names['1 5 8'] = {expanded = 'maj', compact = 'M'}
chord_names['1 8 12'] = {expanded = 'maj7 omit3', compact = 'M7(no3)'}
chord_names['1 5 12'] = {expanded = 'maj7 omit5', compact = 'M7(no5)'}
chord_names['1 5 8 12'] = {expanded = 'maj7', compact = 'M7'}
chord_names['1 3 5 12'] = {expanded = 'maj9 omit5', compact = 'M9(no5)'}
chord_names['1 3 5 8 12'] = {expanded = 'maj9', compact = 'M9'}
chord_names['1 3 5 6 12'] = {expanded = 'maj11 omit5', compact = 'M11(no5)'}
chord_names['1 5 6 8 12'] = {expanded = 'maj11 omit9', compact = 'M11(no9)'}
chord_names['1 3 5 6 8 12'] = {expanded = 'maj11', compact = 'M11'}
chord_names['1 3 5 6 10 12'] = {expanded = 'maj13 omit5', compact = 'M13(no5)'}
chord_names['1 5 6 8 10 12'] = {expanded = 'maj13 omit9', compact = 'M13(no9)'}
chord_names['1 3 5 6 8 10 12'] = {expanded = 'maj13', compact = 'M13'}
chord_names['1 8 10'] = {expanded = '6 omit3', compact = '6(no3)'}
chord_names['1 5 8 10'] = {expanded = '6', compact = '6'}
chord_names['1 3 5 10'] = {expanded = '6/9 omit5', compact = '6/9(no5)'}
chord_names['1 3 5 8 10'] = {expanded = '6/9', compact = '6/9'}

-- Dominant/Seventh
chord_names['1 8 11'] = {expanded = '7 omit3', compact = '7(no3)'}
chord_names['1 5 11'] = {expanded = '7 omit5', compact = '7(no5)'}
chord_names['1 5 8 11'] = {expanded = '7', compact = '7'}
chord_names['1 3 8 11'] = {expanded = '9 omit3', compact = '9(no3)'}
chord_names['1 3 5 11'] = {expanded = '9 omit5', compact = '9(no5)'}
chord_names['1 3 5 8 11'] = {expanded = '9', compact = '9'}
chord_names['1 3 5 10 11'] = {expanded = '13 omit5', compact = '13(no5)'}
chord_names['1 5 8 10 11'] = {expanded = '13 omit9', compact = '13(no9)'}
chord_names['1 3 5 8 10 11'] = {expanded = '13', compact = '13'}
chord_names['1 5 7 11'] = {expanded = '7#11 omit5', compact = '7#11(no5)'}
chord_names['1 5 7 8 11'] = {expanded = '7#11', compact = '7#11'}
chord_names['1 3 5 7 11'] = {expanded = '9#11 omit5', compact = '9#11(no5)'}
chord_names['1 3 5 7 8 11'] = {expanded = '9#11', compact = '9#11'}

-- Altered
chord_names['1 2 5 11'] = {expanded = '7b9 omit5', compact = '7b9(no5)'}
chord_names['1 2 5 8 11'] = {expanded = '7b9', compact = '7b9'}
chord_names['1 2 5 7 8 11'] = {expanded = '7b9#11', compact = '7b9#11'}
chord_names['1 4 5 11'] = {expanded = '7#9 omit5', compact = '7#9(no5)'}
chord_names['1 4 5 8 11'] = {expanded = '7#9', compact = '7#9'}
chord_names['1 4 5 9 11'] = {expanded = '7#5#9', compact = '7#5#9'}
chord_names['1 4 5 7 8 11'] = {expanded = '7#9#11', compact = '7#9#11'}
chord_names['1 2 5 8 10 11'] = {expanded = '13b9', compact = '13b9'}
chord_names['1 3 5 7 8 10 11'] = {expanded = '13#11', compact = '13#11'}

-- Suspended
chord_names['1 6 8'] = {expanded = 'sus4', compact = 'sus4'}
chord_names['1 3 8'] = {expanded = 'sus2', compact = 'sus2'}
chord_names['1 6 11'] = {expanded = '7sus4 omit5', compact = '7sus4(no5)'}
chord_names['1 6 8 11'] = {expanded = '7sus4', compact = '7sus4'}
chord_names['1 3 6 11'] = {expanded = '11 omit5', compact = '11(no5)'}
chord_names['1 6 8 11'] = {expanded = '11 omit9', compact = '11(no9)'}
chord_names['1 3 6 8 11'] = {expanded = '11', compact = '11'}

-- Minor
chord_names['1 4 8'] = {expanded = 'm', compact = 'm'}
chord_names['1 4 11'] = {expanded = 'm7 omit5', compact = 'm7(no5)'}
chord_names['1 4 8 11'] = {expanded = 'm7', compact = 'm7'}
chord_names['1 4 12'] = {expanded = 'm/maj7 omit5', compact = 'm/M7(no5)'}
chord_names['1 4 8 12'] = {expanded = 'm/maj7', compact = 'm/M7'}
chord_names['1 3 4 12'] = {expanded = 'm/maj9 omit5', compact = 'm/M9(no5)'}
chord_names['1 3 4 8 12'] = {expanded = 'm/maj9', compact = 'm/M9'}
chord_names['1 3 4 11'] = {expanded = 'm9 omit5', compact = 'm9(no5)'}
chord_names['1 3 4 8 11'] = {expanded = 'm9', compact = 'm9'}
chord_names['1 3 4 6 11'] = {expanded = 'm11 omit5', compact = 'm11(no5)'}
chord_names['1 4 6 8 11'] = {expanded = 'm11 omit9', compact = 'm11(no9)'}
chord_names['1 3 4 6 8 11'] = {expanded = 'm11', compact = 'm11'}
chord_names['1 3 4 6 10 11'] = {expanded = 'm13 omit5', compact = 'm13(no5)'}
chord_names['1 4 6 8 10 11'] = {expanded = 'm13 omit9', compact = 'm13(no9)'}
chord_names['1 3 4 6 8 10 11'] = {expanded = 'm13', compact = 'm13'}
chord_names['1 4 8 10'] = {expanded = 'm6', compact = 'm6'}
chord_names['1 3 4 10'] = {expanded = 'm6/9 omit5', compact = 'm6/9(no5)'}
chord_names['1 3 4 8 10'] = {expanded = 'm6/9', compact = 'm6/9'}

-- Diminished
chord_names['1 4 7'] = {expanded = 'dim', compact = 'dim'}
chord_names['1 4 7 10'] = {expanded = 'dim7', compact = 'dim7'}
chord_names['1 4 7 11'] = {expanded = 'm7b5', compact = 'm7b5'}
chord_names['1 2 4 8 11'] = {expanded = 'm7b9', compact = 'm7b9'}
chord_names['1 2 4 7 11'] = {expanded = 'm7b5b9', compact = 'm7b5b9'}
chord_names['1 2 4 11'] = {expanded = 'm7b9 omit5', compact = 'm7b9(no5)'}
chord_names['1 3 4 7 11'] = {expanded = 'm9b5', compact = 'm9b5'}
chord_names['1 3 4 6 7 11'] = {expanded = 'm11b5', compact = 'm11b5'}
chord_names['1 3 5 7 10 11'] = {expanded = '13b5', compact = '13b5'}

-- Augmented
chord_names['1 5 9'] = {expanded = 'aug', compact = 'aug'}
chord_names['1 5 9 11'] = {expanded = 'aug7', compact = 'aug7'}
chord_names['1 5 9 12'] = {expanded = 'aug/maj7', compact = 'aug/M7'}

-- Additions
chord_names['1 3 4'] = {expanded = 'm add9 omit5', compact = 'm add9(no5)'}
chord_names['1 3 4 8'] = {expanded = 'm add9', compact = 'm add9'}
chord_names['1 3 5'] = {expanded = 'maj add9 omit5', compact = 'M add9(no5)'}
chord_names['1 3 5 8'] = {expanded = 'maj add9', compact = 'M add9'}
chord_names['1 4 6 8'] = {expanded = 'm add11', compact = 'm add11'}
chord_names['1 5 6 8'] = {expanded = 'maj add11', compact = 'M add11'}
chord_names['1 5 10 11'] = {expanded = '7 add13', compact = '7 add13'}

local note_names_abc_sharp = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#',
    'A', 'A#', 'B'}

local note_names_solfege_sharp = {'Do ', 'Do# ', 'Re ', 'Re# ', 'Mi ', 'Fa ',
    'Fa# ', 'Sol ', 'Sol# ', 'La ', 'La# ', 'Si '}

local note_names_abc_flat = {'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab',
    'A', 'Bb', 'B'}

local note_names_solfege_flat = {'Do ', 'Reb ', 'Re ', 'Mib ', 'Mi ', 'Fa ',
    'Solb ', 'Sol ', 'Lab ', 'La ', 'Sib ', 'Si '}

function LoadChordNames()
    curr_chord_names = {}
    local key = use_compact and 'compact' or 'expanded'
    for inverval, names in pairs(chord_names) do
        curr_chord_names[inverval] = names[key]
    end
end
LoadChordNames()

function PitchToName(pitch)
    local note_names
    local is_sharp = use_sharps
    if use_solfege then
        if is_sharp then
            note_names = note_names_solfege_sharp
        else
            note_names = note_names_solfege_flat
        end
    else
        if is_sharp then
            note_names = note_names_abc_sharp
        else
            note_names = note_names_abc_flat
        end
    end
    return note_names[pitch % 12 + 1]
end

function ToggleCompactMode()
    use_compact = not use_compact
    ExtSave('compact', use_compact and 1 or 0)
    LoadChordNames()
end

function ToggleInversionMode()
    use_inversions = not use_inversions
    ExtSave('inversions', use_inversions and 1 or 0)
end

function ToggleOmissionMode()
    use_omissions = not use_omissions
    ExtSave('omissions', use_omissions and 1 or 0)
end

function ToggleMajorMode()
    use_major = not use_major
    ExtSave('major', use_major and 1 or 0)
end

function ToggleSolfegeMode()
    use_solfege = not use_solfege
    ExtSave('solfege', use_solfege and 1 or 0)
end

function SetSharpMode(is_sharp)
    use_sharps = is_sharp
    ExtSave('sharps', use_sharps and 1 or 0)
end

function IdentifyChord(notes)
    -- Get chord root
    local root = math.maxinteger
    for i = 1, #notes do
        local note = notes[i]
        root = note.pitch < root and note.pitch or root
    end
    -- Remove duplicates and move notes closer
    local intervals = {}
    for i = 1, #notes do
        local note = notes[i]
        intervals[(note.pitch - root) % 12 + 1] = 1
    end

    -- Create chord key string
    local interval_cnt = 0
    local key = '1'
    for i = 2, 12 do
        if intervals[i] then
            key = key .. ' ' .. i
            interval_cnt = interval_cnt + 1
        end
    end

    -- Check for compound chords / octaves
    if interval_cnt <= 1 then
        intervals = {}
        for i = 1, #notes do
            local note = notes[i]
            local diff = note.pitch - root
            if diff >= 12 then
                intervals[diff % 12 + 13] = 1
            elseif diff > 0 then
                intervals = {}
                break
            end
        end
        -- Create compound chord key string
        local comp_key = '1'
        for i = 12, 24 do
            if intervals[i] then comp_key = comp_key .. ' ' .. i end
        end

        -- Check if compound chord name exists for key
        if curr_chord_names[comp_key] then return comp_key, root end
    end

    -- Check if chord name exists for key
    if curr_chord_names[key] then return key, root end

    local key_nums = {}
    for key_num in key:gmatch('%d+') do key_nums[#key_nums + 1] = key_num end

    -- Create all possible inversions
    for n = 2, #key_nums do
        local diff = key_nums[n] - key_nums[1]
        intervals = {}
        for i = 1, #key_nums do
            intervals[(key_nums[i] - diff - 1) % 12 + 1] = 1
        end
        local inv_key = '1'
        for i = 2, 12 do
            if intervals[i] then inv_key = inv_key .. ' ' .. i end
        end
        -- Check if chord name exists for inversion key
        if curr_chord_names[inv_key] then return inv_key, root + diff, root end
    end
end

function BuildChord(notes)
    local chord_key, chord_root, inversion_root = IdentifyChord(notes)
    if chord_key then
        local chord = {
            notes = notes,
            root = chord_root,
            key = chord_key,
            inversion_root = inversion_root,
        }
        if notes[1].sqn then
            -- Determine chord start and end qn position
            local min_eqn = math.maxinteger
            local max_sqn = math.mininteger
            for i = 1, #notes do
                local note = notes[i]
                min_eqn = note.eqn < min_eqn and note.eqn or min_eqn
                max_sqn = note.sqn > max_sqn and note.sqn or max_sqn
            end
            chord.sqn = max_sqn
            chord.eqn = min_eqn
        end
        return chord
    end
end

function BuildChordName(chord)
    if not chord then return '' end
    if chord.name then return chord.name end
    local add = curr_chord_names[chord.key]
    if not use_omissions then
        add = add:gsub(use_compact and '%(no%d+%)' or ' omit%d+', '')
    end
    if not use_major then
        add = add:gsub(use_compact and '^M(%s?)' or '^(%s?)majo?r?%s?', '%1')
    end
    local name = PitchToName(chord.root) .. add
    if use_inversions and chord.inversion_root then
        name = name .. '/' .. PitchToName(chord.inversion_root)
    end
    return name
end

function OnHoverEnd()
    if prev_is_button_hovered then
        prev_is_button_hovered = false
        prev_button_color = nil
        is_redraw = true
    end
end

local prev_hover_m_x, prev_hover_m_y
local hover_cnt = 0
function OnHover(m_x, m_y)
    local is_button_hovered = button_w > 0 and m_x <= button_w
    if is_button_hovered ~= prev_is_button_hovered then
        prev_is_button_hovered = is_button_hovered
        prev_button_color = nil
        is_redraw = true
    end
    if is_button_hovered then
        if m_x == prev_hover_m_x and m_y == prev_hover_m_y then
            hover_cnt = hover_cnt + 1
        else
            hover_cnt = 0
        end
        prev_hover_m_x, prev_hover_m_y = m_x, m_y

        if hover_cnt > 11 then
            local tooltip = 'Toggle chord detection (right click for settings)'
            local offs = Scale(17, measure_scale)
            reaper.TrackCtl_SetToolTip(tooltip, mouse_x + offs, mouse_y + offs, 1)
        end
    end
end

function OnLeftClick(m_x)
    FlushMIDIInputChord()
    local all_mods_pressed = reaper.JS_Mouse_GetState(28) == 28
    if all_mods_pressed then
        PrintIni()
        return
    end
    if button_w > 0 and m_x <= button_w then
        is_toggle = not is_toggle
        detect_mode = is_toggle and detect_mode_on or detect_mode_off
        ExtSave('toggle', is_toggle and 1 or 0)
        prev_button_color = nil
        is_redraw = true
        return
    end

    -- Check if ctrl is pressed
    local is_ctrl_pressed = reaper.JS_Mouse_GetState(4) == 4
    if is_ctrl_pressed then
        local last_export = ExtLoad('last_export', '')
        local export_functions = {
            chord_track = CreateChordTrack,
            project_region = CreateChordProjectRegions,
            project_marker = CreateChordProjectMarkers,
            take_marker = CreateChordTakeMarkers,
        }
        if export_functions[last_export] then
            export_functions[last_export]()
        end
    else
        ShowChordboxMenu()
    end
end

function GetChordDetectionMenu()
    local function IsDetectOff(flag) return detect_mode_off & flag == flag end
    local function SetDetectOff(flag)
        local sign = IsDetectOff(flag) and -1 or 1
        detect_mode_off = detect_mode_off + flag * sign
        ExtSave('detect_mode_off', detect_mode_off)
        if is_toggle then detect_mode = detect_mode_off end
    end
    local function IsDetectOn(flag) return detect_mode_on & flag == flag end
    local function SetDetectOn(flag)
        local sign = IsDetectOn(flag) and -1 or 1
        detect_mode_on = detect_mode_on + flag * sign
        ExtSave('detect_mode_on', detect_mode_on)
        if is_toggle then detect_mode = detect_mode_on end
    end
    local menu = {
        {
            title = 'When button is off, detect...',
            is_grayed = true,
        },
        {separator = true},
        {
            title = 'MIDI input',
            IsChecked = IsDetectOff,
            OnReturn = SetDetectOff,
            arg = 1,
        },
        {
            title = 'Edit cursor',
            IsChecked = IsDetectOff,
            OnReturn = SetDetectOff,
            arg = 2,
        },
        {
            title = 'Play cursor',
            IsChecked = IsDetectOff,
            OnReturn = SetDetectOff,
            arg = 4,
        },
        {
            title = 'Mouse cursor',
            IsChecked = IsDetectOff,
            OnReturn = SetDetectOff,
            arg = 8,
        },
        {separator = true},
        {
            title = 'When button is on, detect...',
            is_grayed = true,
        },
        {separator = true},
        {
            title = 'MIDI input',
            IsChecked = IsDetectOn,
            OnReturn = SetDetectOn,
            arg = 1,
        },
        {
            title = 'Edit cursor',
            IsChecked = IsDetectOn,
            OnReturn = SetDetectOn,
            arg = 2,
        },
        {
            title = 'Play cursor',
            IsChecked = IsDetectOn,
            OnReturn = SetDetectOn,
            arg = 4,
        },
        {
            title = 'Mouse cursor',
            IsChecked = IsDetectOn,
            OnReturn = SetDetectOn,
            arg = 8,
        },
    }
    return menu
end

function OnRightClick(m_x)
    if button_w > 0 and m_x <= button_w then
        ShowMenu(GetChordDetectionMenu())
        return
    end
    ShowChordboxMenu()
end

function ShowChordboxMenu()
    local other_theme_menu = {}
    local curr_theme_key = GetThemeKey(prev_color_theme)
    local theme_settings = ExtLoad('theme_settings', {})
    for theme_key in pairs(theme_settings) do
        if theme_key ~= curr_theme_key then
            local title = theme_key
            if not GetThemeFromKey(theme_key) then
                title = title .. ' (not found)'
            end
            if is_windows then title = title:gsub('/', '\\') end
            other_theme_menu[#other_theme_menu + 1] = {
                title = title,
                OnReturn = function()
                    local is_shift_pressed = reaper.JS_Mouse_GetState(8) == 8
                    if is_shift_pressed then
                        local msg = 'Permanently delete all settings for \z
                            this theme?\n\n%s'
                        local ret = reaper.MB(msg:format(theme_key), 'Warning', 1)
                        if ret == 1 then
                            SaveThemeSettings(prev_color_theme)
                            theme_settings[theme_key] = nil
                            ExtSave('theme_settings', theme_settings)
                            prev_color_theme = nil
                        end
                        return
                    end
                    local msg = 'Attempt to load size and position?'
                    local ret = reaper.MB(msg, 'Settings', 3)
                    if ret >= 6 then
                        LoadThemeSettings(theme_key .. '.ReaperTheme', ret ~= 6)
                        SaveThemeSettings(prev_color_theme)
                        prev_color_theme = nil
                    end
                end,
            }
        end
    end

    if #other_theme_menu > 0 then
        -- Sorts the menu entries alphanumerically
        local function SortByName(t, key)
            local function Format(d) return ('%03d%s'):format(#d, d) end
            local function Compare(a, b)
                return tostring(a[key]):gsub('%d+', Format) <
                    tostring(b[key]):gsub('%d+', Format)
            end
            table.sort(t, Compare)
        end
        -- Add title and help info entry
        SortByName(other_theme_menu, 'title')
        table.insert(other_theme_menu, 1,
            {
                title = 'Hold shift to delete settings for theme',
                is_grayed = true,
            }
        )
        table.insert(other_theme_menu, 2, {separator = true})
        other_theme_menu.title = 'Load from'
    end

    local detection_menu = GetChordDetectionMenu()
    detection_menu.title = 'Chord detection'

    local curr_attach_mode = GetAttachMode()

    local comp_fps_entry = {}
    if is_windows then
        comp_fps_entry = {
            title = 'Anti-flickering',
            is_checked = comp_fps ~= 30,
            OnReturn = function()
                local title = 'Limit underlying window frame rate (FPS)'
                local caption = 'FPS: (lower FPS -> less flicker)'

                local GetUserInputs = reaper.GetUserInputs
                local ret, input = GetUserInputs(title, 1, caption, comp_fps)
                if not ret then return end
                comp_fps = tonumber(input) or 30
                comp_fps = math.max(0, comp_fps)
                comp_delay = comp_fps == 0 and 0 or 1 / comp_fps
                ExtSave('comp_fps', comp_fps)
                is_resize = true
            end,
        }
    end

    local last_export = ExtLoad('last_export', '')

    local menu = {
        {
            title = 'Export chords as',
            {
                title = ('%s+click on box to export with last setting')
                    :format(is_macos and 'Cmd' or 'Ctrl'),
                is_grayed = true,
            },
            {separator = true},
            {
                title = 'Project regions' ..
                    (last_export == 'project_region' and ' •' or ''),
                OnReturn = CreateChordProjectRegions,
            },
            {
                title = 'Project markers' ..
                    (last_export == 'project_marker' and ' •' or ''),
                OnReturn = CreateChordProjectMarkers,
            },
            {
                title = 'Take markers' ..
                    (last_export == 'take_marker' and ' •' or ''),
                OnReturn = CreateChordTakeMarkers,
            },
            {
                title = 'Chord track' ..
                    (last_export == 'chord_track' and ' •' or ''),
                OnReturn = CreateChordTrack,
            },
        },
        {
            title = 'Preferences',
            {
                title = 'Chord display',
                {
                    title = 'Flat',
                    OnReturn = SetSharpMode,
                    is_checked = not use_sharps,
                    arg = false,
                },
                {
                    title = 'Sharp',
                    OnReturn = SetSharpMode,
                    is_checked = use_sharps,
                    arg = true,
                },
                {separator = true},
                {
                    title = 'Compact notation',
                    OnReturn = ToggleCompactMode,
                    is_checked = use_compact,
                },
                {
                    title = 'Explicit major',
                    OnReturn = ToggleMajorMode,
                    is_checked = use_major,
                },
                {
                    title = 'Inversions',
                    OnReturn = ToggleInversionMode,
                    is_checked = use_inversions,
                },
                {
                    title = 'Omissions',
                    OnReturn = ToggleOmissionMode,
                    is_checked = use_omissions,
                },
                {
                    title = 'Solfège (do, re, mi)',
                    OnReturn = ToggleSolfegeMode,
                    is_checked = use_solfege,
                },
            },
            detection_menu,
            {
                title = 'Chord track',
                {
                    title = 'Set track name...',
                    OnReturn = SetChordTrackName,
                },
                {
                    title = 'Reuse existing chord track',
                    OnReturn = ToggleReuseChordTrack,
                    is_checked = reuse_chord_track,
                },
            },
            {
                title = ('Set box label...'):format(label),
                OnReturn = function()
                    local title = 'Chordbox'
                    local caption = 'Label:'
                    local GetUserInputs = reaper.GetUserInputs
                    local ret, input = GetUserInputs(title, 1, caption, label)
                    if not ret then return end
                    label = input == '' and 'Chord' or input
                    ExtSave('label', label)
                    is_redraw = true
                end,
            },
            comp_fps_entry,
        },
        {
            title = 'Customize',
            {title = 'Size', OnReturn = SetCustomSize},
            {title = 'Font', OnReturn = SetCustomFont},
            {title = 'Corners', OnReturn = SetCustomCornerRadius},
            {title = 'Button', OnReturn = SetCustomButtonSize},
            {separator = true},
            {title = 'Colors', OnReturn = SetCustomColors},
            {
                title = 'Choose color...',

                {
                    title = 'Background',
                    OnReturn = function()
                        user_bg_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Text',
                    OnReturn = function()
                        user_text_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Border',
                    OnReturn = function()
                        user_border_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Cursor Icon',
                    OnReturn = function()
                        user_cursor_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Play Icon',
                    OnReturn = function()
                        user_play_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Record icon',
                    OnReturn = function()
                        user_rec_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Arrow icons',
                    OnReturn = function()
                        user_arrow_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Button on',
                    OnReturn = function()
                        user_button_on_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Button off',
                    OnReturn = function()
                        user_button_off_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
                {
                    title = 'Button separator',
                    OnReturn = function()
                        user_arrow_color = GetUserColor()
                        SaveThemeSettings(prev_color_theme)
                        is_redraw = true
                    end,
                },
            },
            {separator = true},
            {
                title = 'Attach to',
                {
                    title = 'Left status edge',
                    is_checked = curr_attach_mode == 3,
                    is_grayed = attach_window_title ~= nil,
                    OnReturn = function()
                        SetAttachMode(3)
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Right status edge',
                    is_checked = curr_attach_mode == 4,
                    is_grayed = attach_window_title ~= nil,
                    OnReturn = function()
                        SetAttachMode(4)
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Left window edge',
                    is_checked = curr_attach_mode == 1,
                    OnReturn = function()
                        SetAttachMode(1)
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
                {
                    title = 'Right window edge',
                    is_checked = curr_attach_mode == 2,
                    OnReturn = function()
                        SetAttachMode(2)
                        UpdateAttachPosition()
                        SaveThemeSettings(prev_color_theme)
                    end,
                },
            },
            {separator = true},
            other_theme_menu,
            {
                title = 'Reset',
                OnReturn = function()
                    local msg = 'This will clear all customizations you made \z
                    for the active theme.\n\nProceed?'
                    local ret = reaper.MB(msg, 'Warning', 4)
                    if ret ~= 6 then return end

                    local settings = ExtLoad('theme_settings', {})
                    local theme_key = GetThemeKey(prev_color_theme)
                    settings[theme_key] = nil
                    ExtSave('theme_settings', settings)
                    prev_color_theme = nil

                    if attach_window_title then
                        msg = 'Move %s back to transport?'
                        ret = reaper.MB(msg:format(box_name), box_name, 4)
                        if ret == 6 then
                            SaveAttachedWindow(nil)
                            EndIntercepts()
                            window_hwnd = nil
                            prev_top_window_cnt = nil
                        end
                    end
                end,
            },
        },
        {
            title = 'Lock position',
            is_checked = not is_edit_mode,
            OnReturn = function()
                SetEditMode(not is_edit_mode)
            end,
        },
        {
            title = 'Run script on startup',
            IsChecked = IsStartupHookEnabled,
            OnReturn = function()
                local is_enabled = IsStartupHookEnabled()
                local comment = 'Start script: Chordbox'
                local var_name = 'chord_box_cmd_name'
                SetStartupHookEnabled(not is_enabled, comment, var_name)
            end,
        },
    }
    ShowMenu(menu)
end

function GetSourcePPQLength(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local src_length = reaper.GetMediaSourceLength(src)
    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    return reaper.MIDI_GetPPQPosFromProjQN(take, start_qn + src_length)
end

function GetOverlappingSelectedMIDITakes(item)
    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local item_length = GetItemInfo(item, 'D_LENGTH')
    local item_start_pos = GetItemInfo(item, 'D_POSITION')
    local item_end_pos = item_start_pos + item_length

    local takes = {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local other = reaper.GetSelectedMediaItem(0, i)
        if other ~= item then
            local length = GetItemInfo(other, 'D_LENGTH')
            local start_pos = GetItemInfo(other, 'D_POSITION')
            local end_pos = start_pos + length

            if item_start_pos < end_pos and item_end_pos > start_pos then
                local take = reaper.GetActiveTake(other)
                if take and reaper.TakeIsMIDI(take) then
                    takes[#takes + 1] = take
                end
            end
        end
    end
    return takes
end

function GetAudibleMIDITakesAtMeasure(track, measure)
    local measure_start_pos = reaper.TimeMap2_beatsToTime(0, 0, measure - 1)
    local measure_end_pos = reaper.TimeMap2_beatsToTime(0, 0, measure + 2)

    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local takes = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local length = GetItemInfo(item, 'D_LENGTH')
        local start_pos = GetItemInfo(item, 'D_POSITION')
        local end_pos = start_pos + length
        if start_pos >= measure_end_pos then break end

        local overlaps = end_pos > measure_start_pos + 0.0001
        if overlaps then
            local is_muted = GetItemInfo(item, 'B_MUTE') == 1
            local lane_plays = GetItemInfo(item, 'C_LANEPLAYS')
            if not is_muted and lane_plays > 0 then
                local take = reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    takes[#takes + 1] = take
                end
            end
        end
    end
    return takes
end

function LoadNotes(take)
    local GetSetTakeInfo = reaper.GetSetMediaItemTakeInfo_String
    local _, take_guid = GetSetTakeInfo(take, 'GUID', '', false)
    local notes = take_note_map[take_guid]
    local track = reaper.GetMediaItemTake_Track(take)
    local _, midi_hash = reaper.MIDI_GetTrackHash(track, false)

    local pitch = reaper.GetMediaItemTakeInfo_Value(take, 'D_PITCH')
    if not notes or notes.hash ~= midi_hash or notes.pitch ~= pitch then
        notes = GetNotes(take)
        notes.hash = midi_hash
        notes.pitch = pitch
        notes.take = take
        take_note_map[take_guid] = notes
    end

    return notes
end

function GetNotes(take)
    local notes = {}

    local GetNote = reaper.MIDI_GetNote
    local PPQFromTime = reaper.MIDI_GetPPQPosFromProjTime
    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local GetQNFromPPQ = reaper.MIDI_GetProjQNFromPPQPos

    local pitch_offs = reaper.GetMediaItemTakeInfo_Value(take, 'D_PITCH')
    pitch_offs = math.floor(pitch_offs + 0.5)

    -- Get minimum item start position and maximum item end position
    local item = reaper.GetMediaItemTake_Item(take)
    local length = GetItemInfo(item, 'D_LENGTH')
    local start_pos = GetItemInfo(item, 'D_POSITION')
    local end_pos = start_pos + length

    local start_ppq = PPQFromTime(take, start_pos)
    local end_ppq = PPQFromTime(take, end_pos)

    local loops = 1
    local source_qn_length = 0
    local source_ppq_length = 0
    -- Calculate how often item is looped (and loop length)
    if GetItemInfo(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        source_qn_length = source_length
        source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        local item_start_qn = reaper.TimeMap_timeToQN(start_pos)
        local item_end_qn = reaper.TimeMap_timeToQN(end_pos)
        local item_qn_length = item_end_qn - item_start_qn
        -- Note: Looped items repeat after full ppq length
        loops = math.ceil(item_qn_length / source_qn_length)
    end

    local _, note_cnt = reaper.MIDI_CountEvts(take)
    for loop = 1, loops do
        for i = 0, note_cnt - 1 do
            local _, sel, mute, sppq, eppq, _, pitch = GetNote(take, i)
            local loop_ppq = source_ppq_length * (loop - 1)
            local sppq_o = sppq + loop_ppq
            local eppq_o = eppq + loop_ppq
            if sppq_o >= end_ppq then break end
            -- Filter out muted notes and notes that are outside item bounds
            if not mute and eppq_o > start_ppq then
                sppq_o = sppq_o > start_ppq and sppq_o or start_ppq
                eppq_o = eppq_o < end_ppq and eppq_o or eppq_o
                local note_info = {
                    pitch = pitch + pitch_offs,
                    sel = sel,
                    sqn = GetQNFromPPQ(take, sppq_o),
                    eqn = GetQNFromPPQ(take, eppq_o),
                }
                notes[#notes + 1] = note_info
            end
        end
    end

    return notes
end

function CombineNotes(take_notes)
    if #take_notes == 0 then return {} end
    if #take_notes == 1 then return take_notes[1] end
    local new_notes = {}
    for i = 1, #take_notes do
        local notes = take_notes[i]
        for n = 1, #notes do
            new_notes[#new_notes + 1] = notes[n]
        end
    end

    table.sort(new_notes, function(a, b) return a.sqn < b.sqn end)
    return new_notes
end

function GetChords(notes)
    -- Build chords from notes
    local chords = {}
    local chord_notes = {}

    local chord_min_eqn

    for i = 1, #notes do
        local note_info = notes[i]
        local sqn, eqn = note_info.sqn, note_info.eqn

        chord_min_eqn = chord_min_eqn or eqn
        chord_min_eqn = eqn < chord_min_eqn and eqn or chord_min_eqn

        if sqn >= chord_min_eqn then
            local new_chord_notes = {}
            if #chord_notes >= 2 then
                local chord = BuildChord(chord_notes)
                if chord then chords[#chords + 1] = chord end
                for n = 3, #chord_notes do
                    -- Remove notes that end prior to chord_min_eqn
                    for _, note in ipairs(chord_notes) do
                        if note.eqn > chord_min_eqn then
                            new_chord_notes[#new_chord_notes + 1] = note
                        end
                    end
                    -- Try to build chords
                    chord = BuildChord(new_chord_notes)
                    if chord then
                        chord.sqn = chord_min_eqn
                        chord.eqn = math.min(chord.eqn, sqn)
                        -- Ignore short chords
                        if chord.eqn - chord.sqn >= 0.25 then
                            chords[#chords + 1] = chord
                        end
                        chord_min_eqn = chord.eqn
                    end
                    new_chord_notes = {}
                end
                -- Remove notes that end prior to the start of current note
                chord_min_eqn = eqn
                for _, note in ipairs(chord_notes) do
                    if note.eqn > sqn then
                        new_chord_notes[#new_chord_notes + 1] = note
                        if note.eqn < chord_min_eqn then
                            chord_min_eqn = note.eqn
                        end
                    end
                end
            else
                chord_min_eqn = eqn
            end
            chord_notes = new_chord_notes
        else
            if #chord_notes >= 2 then
                local chord = BuildChord(chord_notes)
                if chord then
                    chord.eqn = math.min(chord.eqn, sqn)
                    -- Ignore very short arpeggiated chords
                    if chord.eqn - chord.sqn >= 0.1875 then
                        chords[#chords + 1] = chord
                    end
                end
            end
        end
        chord_notes[#chord_notes + 1] = note_info
    end

    if #chord_notes >= 2 then
        local chord = BuildChord(chord_notes)
        if chord then chords[#chords + 1] = chord end
        for n = 3, #chord_notes do
            local new_chord_notes = {}
            -- Remove notes that end prior to chord_min_eqn
            for _, note in ipairs(chord_notes) do
                if note.eqn > chord_min_eqn then
                    new_chord_notes[#new_chord_notes + 1] = note
                end
            end
            -- Try to build chords
            chord = BuildChord(new_chord_notes)
            if chord then
                chord.sqn = chord_min_eqn
                -- Ignore short chords
                if chord.eqn - chord.sqn >= 0.25 then
                    chords[#chords + 1] = chord
                end
                chord_min_eqn = chord.eqn
            end
        end
    end

    return chords
end

function FlushMIDIInputChord()
    prev_input_idx = nil
    input_note_map = {}
    input_note_cnt = 0
end

function GetMIDIInputChord()
    local filter_channel = 0
    local filter_dev_id = 63
    if sel_track then
        local rec_in = reaper.GetMediaTrackInfo_Value(sel_track, 'I_RECINPUT')
        local rec_arm = reaper.GetMediaTrackInfo_Value(sel_track, 'I_RECARM')
        local is_recording_midi = rec_arm == 1 and rec_in & 4096 == 4096
        if is_recording_midi then
            filter_channel = rec_in & 31
            filter_dev_id = (rec_in >> 5) & 127
        end
    end

    local input_notes
    local idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(0)
    prev_input_idx = prev_input_idx or idx

    if idx > prev_input_idx then
        local new_idx = idx
        local i = 0
        input_notes = {}
        repeat
            if #buf == 3 then
                if filter_dev_id == 63 or filter_dev_id == dev_id then
                    local msg1 = buf:byte(1)
                    local channel = (msg1 & 0x0F) + 1
                    if filter_channel == 0 or filter_channel == channel then
                        local msg2 = buf:byte(2)
                        local msg3 = buf:byte(3)
                        local is_note_on = msg1 & 0xF0 == 0x90
                        local is_note_off = msg1 & 0xF0 == 0x80
                        -- Check for 0x90 note offs with 0 velocity
                        if is_note_on and msg3 == 0 then
                            is_note_on = false
                            is_note_off = true
                        end
                        if is_note_on then
                            local note = {pitch = msg2, is_note_on = true}
                            input_notes[#input_notes + 1] = note
                        end
                        if is_note_off then
                            local note = {pitch = msg2, is_note_on = false}
                            input_notes[#input_notes + 1] = note
                        end
                    end
                end
            end
            i = i + 1
            idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(i)
        until idx == prev_input_idx

        prev_input_idx = new_idx
    end

    if input_notes then
        for i = #input_notes, 1, -1 do
            local note = input_notes[i]
            local pitch = note.pitch
            if note.is_note_on then
                if not input_note_map[pitch] then
                    input_note_map[pitch] = 1
                    input_note_cnt = input_note_cnt + 1
                end
            else
                if input_note_map[pitch] == 1 then
                    input_note_map[pitch] = nil
                    input_note_cnt = input_note_cnt - 1
                end
            end
        end
    end

    if input_note_cnt >= 2 then
        local notes = {}
        for n = 0, 127 do
            if input_note_map[n] == 1 then
                notes[#notes + 1] = {pitch = n}
            end
        end
        return BuildChord(notes)
    end
end

function SetChordTrackName()
    local title = 'Chord track'
    local caption = 'Track name:,extrawidth=100'
    local input_text = chord_track_name

    local ret, user_text = reaper.GetUserInputs(title, 1, caption, input_text)
    if not ret then return end

    chord_track_name = user_text == '' and 'Chords' or user_text
    ExtSave('chord_track_name', chord_track_name)
end

function ToggleReuseChordTrack()
    reuse_chord_track = not reuse_chord_track
    ExtSave('reuse_chord_track', reuse_chord_track and 1 or 0)
end

function CreateChordTrack()
    local sel_takes = {}
    local sel_start_pos = math.huge
    local sel_end_pos = -math.huge
    for i = 0, reaper.CountSelectedMediaItems() - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local end_pos = start_pos + length
            sel_start_pos = math.min(start_pos, sel_start_pos)
            sel_end_pos = math.max(end_pos, sel_end_pos)
            sel_takes[#sel_takes + 1] = take
        end
    end
    ExtSave('last_export', 'chord_track')
    if #sel_takes == 0 then
        reaper.MB('No items selected!', 'ChordBox', 0)
        return
    end


    local AddItem = reaper.AddMediaItemToTrack
    local SetItemInfo = reaper.SetMediaItemInfo_Value
    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local GetSetItemInfo = reaper.GetSetMediaItemInfo_String
    local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String

    reaper.Undo_BeginBlock()

    local chord_track

    -- Find existing chord track
    if reuse_chord_track then
        for i = reaper.CountTracks(0) - 1, 0, -1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = GetSetTrackInfo(track, 'P_NAME', '', false)
            if track_name == chord_track_name then
                chord_track = track
                break
            end
        end
    end

    -- Delete/trim conflicting items on chord track
    if chord_track then
        for i = reaper.CountTrackMediaItems(chord_track) - 1, 0, -1 do
            local chord_item = reaper.GetTrackMediaItem(chord_track, i)
            local length = GetItemInfo(chord_item, 'D_LENGTH')
            local start_pos = GetItemInfo(chord_item, 'D_POSITION')
            local end_pos = start_pos + length
            if start_pos < sel_end_pos and end_pos > sel_start_pos then
                if start_pos < sel_start_pos - 0.01 then
                    local diff = sel_start_pos - start_pos
                    SetItemInfo(chord_item, 'D_LENGTH', length - diff)
                elseif end_pos > sel_end_pos + 0.01 then
                    local diff = sel_end_pos - start_pos
                    SetItemInfo(chord_item, 'D_LENGTH', length - diff)
                    SetItemInfo(chord_item, 'D_POSITION', start_pos + diff)
                else
                    reaper.DeleteTrackMediaItem(chord_track, chord_item)
                end
            end
        end
    end

    if not chord_track then
        -- Create chord track
        local track = reaper.GetMediaItemTake_Track(sel_takes[1])
        local track_num = reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')
        reaper.InsertTrackAtIndex(track_num - 1, true)
        chord_track = reaper.GetTrack(0, track_num - 1)
        GetSetTrackInfo(chord_track, 'P_NAME', chord_track_name, true)
    end

    local take_notes = {}
    for t = 1, #sel_takes do
        local take = sel_takes[t]
        local notes = LoadNotes(take)
        take_notes[#take_notes + 1] = notes
    end

    local notes = CombineNotes(take_notes)
    local chords = GetChords(notes)

    local prev_name
    local prev_start_pos
    local prev_end_pos

    for _, chord in ipairs(chords) do
        local start_pos = reaper.TimeMap_QNToTime(chord.sqn)
        local end_pos = reaper.TimeMap_QNToTime(chord.eqn)

        if prev_start_pos then
            local reg_start_pos = prev_start_pos
            local reg_end_pos = start_pos
            if reg_start_pos < sel_end_pos and reg_end_pos > sel_start_pos then
                reg_start_pos = math.max(reg_start_pos, sel_start_pos)
                if reg_end_pos > sel_end_pos then
                    reg_end_pos = math.min(prev_end_pos, sel_end_pos)
                end
                if prev_name ~= '' then
                    local chord_item = AddItem(chord_track)
                    local length = reg_end_pos - reg_start_pos
                    SetItemInfo(chord_item, 'D_POSITION', reg_start_pos)
                    SetItemInfo(chord_item, 'D_LENGTH', length)
                    GetSetItemInfo(chord_item, 'P_NOTES', prev_name, true)
                end
            end
        end

        prev_name = BuildChordName(chord)
        prev_start_pos = start_pos
        prev_end_pos = end_pos
    end

    if prev_start_pos then
        local reg_start_pos = prev_start_pos
        local reg_end_pos = prev_end_pos
        if reg_start_pos < sel_end_pos and reg_end_pos > sel_start_pos then
            reg_start_pos = math.max(reg_start_pos, sel_start_pos)
            reg_end_pos = math.min(reg_end_pos, sel_end_pos)
            if prev_name ~= '' then
                local chord_item = AddItem(chord_track)
                local length = reg_end_pos - reg_start_pos
                SetItemInfo(chord_item, 'D_POSITION', reg_start_pos)
                SetItemInfo(chord_item, 'D_LENGTH', length)
                GetSetItemInfo(chord_item, 'P_NOTES', prev_name, true)
            end
        end
    end

    -- Combine regions with same chord name
    local prev_name
    local prev_chord_item
    for i = reaper.CountTrackMediaItems(chord_track) - 1, 0, -1 do
        local chord_item = reaper.GetTrackMediaItem(chord_track, i)
        local start_pos = GetItemInfo(chord_item, 'D_POSITION')
        if start_pos >= sel_start_pos and start_pos < sel_end_pos then
            local _, name = GetSetItemInfo(chord_item, 'P_NOTES', '', false)
            if name == prev_name then
                local prev_length = GetItemInfo(prev_chord_item, 'D_LENGTH')
                prev_start_pos = GetItemInfo(prev_chord_item, 'D_POSITION')
                prev_end_pos = prev_start_pos + prev_length

                reaper.DeleteTrackMediaItem(chord_track, prev_chord_item)

                local curr_start_pos = GetItemInfo(chord_item, 'D_POSITION')
                SetItemInfo(chord_item, 'D_LENGTH', prev_end_pos - curr_start_pos)
            end
            prev_name = name
            prev_chord_item = chord_item
        end
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock('Create chord track', -1)
end

function CreateChordProjectRegions()
    local sel_takes = {}
    local sel_start_pos = math.huge
    local sel_end_pos = -math.huge

    for i = 0, reaper.CountSelectedMediaItems() - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local end_pos = start_pos + length
            sel_start_pos = math.min(start_pos, sel_start_pos)
            sel_end_pos = math.max(end_pos, sel_end_pos)
            sel_takes[#sel_takes + 1] = take
        end
    end
    ExtSave('last_export', 'project_region')
    if #sel_takes == 0 then
        reaper.MB('No items selected!', box_name, 0)
        return
    end


    local EnumMarkers = reaper.EnumProjectMarkers2
    local SetMarker = reaper.SetProjectMarker2
    local AddMarker = reaper.AddProjectMarker

    reaper.Undo_BeginBlock()

    -- Delete regions over item
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if is_reg then
            -- Delete regions within item bounds
            if start_pos >= sel_start_pos and end_pos <= sel_end_pos then
                reaper.DeleteProjectMarker(0, idx, true)
            end
            -- Shorten regions that exceed item end
            if start_pos < sel_end_pos and end_pos > sel_end_pos then
                SetMarker(0, idx, true, sel_end_pos, end_pos, name)
            end
            -- Shorten regions that proceed item start
            if start_pos < sel_start_pos and end_pos > sel_start_pos then
                SetMarker(0, idx, true, start_pos, sel_end_pos, name)
            end
        end
    end

    -- Note: Keep this for debugging purposes
    --[[ for _, chord in ipairs(curr_chords) do
        local start_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, chord.sppq)
        local end_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, chord.eppq)

        print(chord.sppq .. ' ' .. chord.eppq)
        local chord_name = BuildChordName(chord)
        reaper.AddProjectMarker(0, true, start_pos, end_pos, chord_name, -1)
    end
    reaper.Undo_EndBlock('Create chord regions', -1)
    if true then return end ]]

    local take_notes = {}
    for t = 1, #sel_takes do
        local take = sel_takes[t]
        local notes = LoadNotes(take)
        take_notes[#take_notes + 1] = notes
    end

    local notes = CombineNotes(take_notes)
    local chords = GetChords(notes)

    local prev_name
    local prev_start_pos
    local prev_end_pos

    for _, chord in ipairs(chords) do
        local start_pos = reaper.TimeMap_QNToTime(chord.sqn)
        local end_pos = reaper.TimeMap_QNToTime(chord.eqn)

        if prev_start_pos then
            local reg_start_pos = prev_start_pos
            local reg_end_pos = start_pos
            if reg_start_pos < sel_end_pos and reg_end_pos > sel_start_pos then
                reg_start_pos = math.max(reg_start_pos, sel_start_pos)
                if reg_end_pos > sel_end_pos then
                    reg_end_pos = math.min(prev_end_pos, sel_end_pos)
                end
                if prev_name ~= '' then
                    AddMarker(0, true, reg_start_pos, reg_end_pos, prev_name, -1)
                end
            end
        end

        prev_name = BuildChordName(chord)
        prev_start_pos = start_pos
        prev_end_pos = end_pos
    end

    if prev_start_pos then
        local reg_start_pos = prev_start_pos
        local reg_end_pos = prev_end_pos
        if reg_start_pos < sel_end_pos and reg_end_pos > sel_start_pos then
            reg_start_pos = math.max(reg_start_pos, sel_start_pos)
            reg_end_pos = math.min(reg_end_pos, sel_end_pos)
            if prev_name ~= '' then
                AddMarker(0, true, reg_start_pos, reg_end_pos, prev_name, -1)
            end
        end
    end

    -- Combine regions with same chord name
    local prev_name
    local prev_idx
    local prev_end_pos
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if is_reg then
            if start_pos >= sel_start_pos and end_pos <= sel_end_pos then
                if name == prev_name then
                    reaper.DeleteProjectMarker(0, prev_idx, true)
                    SetMarker(0, idx, true, start_pos, prev_end_pos, name)
                    end_pos = prev_end_pos
                end
                prev_name = name
                prev_idx = idx
                prev_end_pos = end_pos
            end
        end
    end
    reaper.Undo_EndBlock('Create chord project regions', -1)
end

function CreateChordProjectMarkers()
    local sel_takes = {}
    local sel_start_pos = math.huge
    local sel_end_pos = -math.huge

    for i = 0, reaper.CountSelectedMediaItems() - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local end_pos = start_pos + length
            sel_start_pos = math.min(start_pos, sel_start_pos)
            sel_end_pos = math.max(end_pos, sel_end_pos)
            sel_takes[#sel_takes + 1] = take
        end
    end
    ExtSave('last_export', 'project_marker')
    if #sel_takes == 0 then
        reaper.MB('No items selected!', box_name, 0)
        return
    end


    local EnumMarkers = reaper.EnumProjectMarkers2
    local AddMarker = reaper.AddProjectMarker

    reaper.Undo_BeginBlock()

    -- Delete markers over item
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if not is_reg then
            if start_pos >= sel_start_pos and end_pos < sel_end_pos then
                reaper.DeleteProjectMarker(0, idx, false)
            end
        end
    end

    local take_notes = {}
    for t = 1, #sel_takes do
        local take = sel_takes[t]
        local notes = LoadNotes(take)
        take_notes[#take_notes + 1] = notes
    end

    local notes = CombineNotes(take_notes)
    local chords = GetChords(notes)

    local prev_name
    for _, chord in ipairs(chords) do
        local start_pos = reaper.TimeMap_QNToTime(chord.sqn)
        local name = BuildChordName(chord)
        if name ~= '' and name ~= prev_name then
            AddMarker(0, false, start_pos, 0, name, -1)
        end
        prev_name = name
    end

    reaper.Undo_EndBlock('Create chord project markers', -1)
end

function CreateChordTakeMarkers()
    local sel_takes = {}
    for i = 0, reaper.CountSelectedMediaItems() - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            sel_takes[#sel_takes + 1] = take
        end
    end
    ExtSave('last_export', 'take_marker')
    if #sel_takes == 0 then
        reaper.MB('No items selected!', box_name, 0)
        return
    end

    local take_notes = {}
    for t = 1, #sel_takes do
        local take = sel_takes[t]
        local notes = LoadNotes(take)
        take_notes[#take_notes + 1] = notes
    end

    local notes = CombineNotes(take_notes)
    local chords = GetChords(notes)

    reaper.Undo_BeginBlock()

    for _, take in ipairs(sel_takes) do
        -- Delete take markers
        for i = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
            reaper.DeleteTakeMarker(take, i)
        end

        local item = reaper.GetMediaItemTake_Item(take)
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')

        local prev_name
        for _, chord in ipairs(chords) do
            local start_pos = reaper.TimeMap_QNToTime(chord.sqn)
            local name = BuildChordName(chord)
            if name ~= '' and name ~= prev_name then
                local marker_pos = start_pos - item_start_pos
                reaper.SetTakeMarker(take, -1, name, marker_pos)
            end
            prev_name = name
        end
    end

    reaper.Undo_EndBlock('Create chord take markers', -1)
end

function DrawPianoIcon(bm, color, x, y, w, h, a)
    if a == 0 then return end
    a = a or 1

    if not button_bitmap then
        button_bitmap = reaper.JS_LICE_CreateBitmap(true, w, h)
        prev_button_color = nil
    end

    if color ~= prev_button_color then
        prev_button_color = color

        -- Draw background rectangle
        DrawRect(button_bitmap, color, 0, 0, w, h, true)

        local m = Scale(1, draw_scale)
        local key_w = (w - 2 * m) // 3

        -- Carve out separators between keys
        local FillRect = reaper.JS_LICE_FillRect
        FillRect(button_bitmap, key_w, 0, m, h, 0, 1, '')
        FillRect(button_bitmap, 2 * key_w + m, 0, m, h, 0, 1, '')

        -- Carve out black keys
        local key_h = h // 1.5
        local offs = math.max(Scale(2, draw_scale), (key_w + m) // 2.2 - m)
        FillRect(button_bitmap, offs, 0, key_w, key_h, 0, 1, '')
        FillRect(button_bitmap, 2 * (key_w + m) - offs, 0, key_w, key_h, 0, 1, '')
    end
    reaper.JS_LICE_Blit(bm, x, y, button_bitmap, 0, 0, w, h, a, 'ALPHA')
end

function DrawBitmap(bm, w, h)
    local alpha = 0xFF000000

    -- Determine background color
    local bg_color = tonumber(user_bg_color or '242424', 16)
    local bg_alpha = 1
    if user_bg_color and #user_bg_color > 6 then
        bg_alpha = (bg_color >> 24) / 255
    end
    bg_color = bg_color | alpha

    ClearBitmap(bm, bg_color)

    -- Draw background
    local corner_radius
    if user_corner_radius then
        corner_radius = math.floor(user_corner_radius)
    else
        corner_radius = Scale(6, draw_scale)
    end
    DrawBackground(bm, bg_color, w, h, corner_radius, bg_alpha)

    -- Determine border color
    local border_color
    local border_alpha = 1
    if user_border_color then
        border_color = tonumber(user_border_color or '242424', 16)
        if #user_border_color > 6 then
            border_alpha = (border_color >> 24) / 255
        end
        border_color = border_color | alpha
    end
    -- Draw border
    if border_color then
        DrawRect(bm, border_color, 0, 0, w, h, false, corner_radius, border_alpha)
    end

    -- Determine text color
    local text_color = tonumber(user_text_color or 'a9a9a9', 16) | alpha

    -- Determine icon colors
    local cursor_color, play_color, rec_color

    if user_cursor_color then
        cursor_color = tonumber(user_cursor_color, 16) | alpha
    else
        cursor_color = text_color
    end

    if user_play_color then
        play_color = tonumber(user_play_color, 16) | alpha
    else
        play_color = text_color
    end

    if user_rec_color then
        rec_color = tonumber(user_rec_color, 16) | alpha
    else
        rec_color = text_color
    end

    -- Measure Text
    local text = chord_text == '' and label or chord_text
    local icon = chord_text == '' and 0 or chord_icon

    local text_w, text_h = gfx.measurestr(text)

    local left_w = 0
    if chord_text == '' then
        -- Determine if button is visible
        local m = Scale(1, draw_scale)
        local icon_h = user_button_size or h // 2
        local key_w = math.max(3 * m, icon_h // 3) + m
        local icon_w = 3 * key_w + 2 * m

        left_w = icon_w // 0.45
        button_w = left_w * measure_scale / draw_scale

        -- Check if snap icon will be visible
        local is_button_hidden = icon_h == 0 or left_w == 0
        if not is_button_hidden then
            local hide_factor = user_button_size and 1.3 or 2.3
            is_button_hidden = left_w > w / hide_factor
        end
        if is_button_hidden then
            button_w = 0
            left_w = 0
        end
        if left_w > 0 then
            local button_on_color, button_off_color, button_sep_color
            local button_on_alpha, button_off_alpha, button_sep_alpha = 1, 1, 1
            -- Determine button on color
            if user_button_on_color then
                button_on_color = tonumber(user_button_on_color, 16)
                if #user_button_on_color > 6 then
                    button_on_alpha = (button_on_color >> 24) / 255
                end
                button_on_color = button_on_color | alpha
            else
                button_on_color = GetThemeColor('areasel_outline') | alpha
            end
            -- Determine button off color
            button_off_color = tonumber(user_button_off_color or '787878', 16)
            if user_button_off_color and #user_button_off_color > 6 then
                button_off_alpha = (button_off_color >> 24) / 255
            end
            button_off_color = button_off_color | alpha
            -- Determine button separator color
            button_sep_color = tonumber(user_button_sep_color or '3a3a3b', 16)
            if user_button_sep_color and #user_button_sep_color > 6 then
                button_sep_alpha = (button_sep_color >> 24) / 255
            end
            button_sep_color = button_sep_color | alpha

            -- Choose button color based on button state
            local button_alpha = is_toggle and button_on_alpha or
                button_off_alpha
            local button_color = is_toggle and button_on_color or
                button_off_color
            if prev_is_button_hovered then
                -- Slightly brighten button color when hovered
                button_color = TintIntColor(button_color, 1.145)
            end

            -- Draw button icon
            local button_x = (left_w - icon_w) // 1.86
            local button_y = (h - icon_h) // 2
            DrawPianoIcon(bm, button_color, button_x, button_y,
                icon_w, icon_h, button_alpha)
            -- Draw button separator
            m = math.max(Scale(4, draw_scale), h // 14)
            local sep_w = math.max(1, Scale(1, draw_scale))
            local sep_x = left_w - sep_w
            local sep_h = h - 2 * m
            DrawRect(bm, button_sep_color, sep_x, m, sep_w, sep_h, true, 0,
                button_sep_alpha)
        end
    end

    local box_m = Scale(6, draw_scale)
    local text_x = left_w + math.max(box_m, (w - left_w * 1.1 - text_w) // 2)
    local text_y = (h - text_h) // 2
    if is_macos then text_y = text_y + 1 end

    -- Position icon at start of text
    local icon_x = math.max(left_w + box_m, text_x - Scale(8, draw_scale))

    -- Play icon
    if icon == 1 then
        local icon_h = text_h // 2 + 1
        -- Ensure triangle height is uneven
        if icon_h % 2 ~= 1 then icon_h = icon_h - 1 end
        local x1, y1 = icon_x, (h - icon_h) // 2
        local x2, y2 = icon_x, y1 + icon_h
        local x3, y3 = icon_x + icon_h, y1 + icon_h // 2

        reaper.JS_LICE_Line(bm, x1, y1, x3, y3, play_color, 1, '', true)
        reaper.JS_LICE_Line(bm, x2, y2, x3, y3 + 1, play_color, 1, '', true)
        reaper.JS_LICE_FillTriangle(bm, x1, y1, x2, y2, x3, y3, play_color,
            1, '')

        -- Move text slightly to the right when icon is drawn
        text_x = x3 + Scale(5, draw_scale)
    end

    -- Cursor icon
    if icon == 2 then
        local icon_w = Scale(4, draw_scale)
        local icon_h = Scale(4, draw_scale)
        local x = icon_x + Scale(1, draw_scale)
        local y = (h - icon_h) // 2

        DrawRect(bm, cursor_color, x, y, icon_w, icon_h, true)

        -- Move text slightly to the right when icon is drawn
        text_x = icon_x + Scale(10, draw_scale)
    end

    -- Record icon
    if icon == 3 then
        local x, y = icon_x + Scale(3, draw_scale), math.ceil(h / 2)
        local r = math.floor(2.5 * draw_scale * 10) / 10
        reaper.JS_LICE_FillCircle(bm, x, y, r, rec_color, 1, '', true)
        reaper.JS_LICE_FillCircle(bm, x, y, r - 0.5, rec_color, 1, '', true)

        -- Move text slightly to the right when icon is drawn
        text_x = icon_x + Scale(10, draw_scale)
    end

    local text_m_r = 0
    local text_m_l = 0
    local arr_color = tonumber(user_arrow_color or '3f3f3f', 16) | alpha

    -- Left arrow icon
    if icon == 7 then
        local icon_h = text_h // 1.5
        if icon_h % 2 == 0 then icon_h = icon_h - 1 end
        local icon_w = icon_h // 1.5
        local side_m = math.max(box_m, icon_w)
        local x1, y1 = side_m + icon_w, (h - icon_h) // 2
        local x2, y2 = x1, y1 + icon_h
        local x3, y3 = x1 - icon_w, y1 + icon_h // 2
        text_m_l = 2 * icon_h + Scale(3, draw_scale)

        local r_w, r_m = icon_h // 2, icon_h // 2.5
        local x4, y4 = x1 + 1, y1 + r_m
        DrawRect(bm, arr_color, x4, y4, r_w, icon_h - 2 * r_m + 1, 1)

        reaper.JS_LICE_Line(bm, x1, y1, x3, y3, arr_color, 1, '', true)
        reaper.JS_LICE_Line(bm, x2, y2, x3, y3 + 1, arr_color, 1, '', true)
        reaper.JS_LICE_FillTriangle(bm, x1, y1, x2, y2, x3, y3, arr_color, 1, '')
    end

    -- Right arrow icon
    if icon == 8 then
        local icon_h = text_h // 1.5
        if icon_h % 2 == 0 then icon_h = icon_h - 1 end
        local icon_w = icon_h // 1.5
        local side_m = math.max(box_m, icon_w)
        local x1, y1 = w - side_m - icon_w, (h - icon_h) // 2
        local x2, y2 = x1, y1 + icon_h
        local x3, y3 = x1 + icon_w, y1 + icon_h // 2
        text_m_r = 2 * icon_h + Scale(2, draw_scale)

        local r_w, r_m = icon_h // 2, icon_h // 2.5
        local x4, y4 = x1 - r_w, y1 + r_m
        DrawRect(bm, arr_color, x4, y4, r_w, icon_h - 2 * r_m + 1, 1)

        reaper.JS_LICE_Line(bm, x1, y1, x3, y3, arr_color, 1, '', true)
        reaper.JS_LICE_Line(bm, x2, y2, x3, y3 + 1, arr_color, 1, '', true)
        reaper.JS_LICE_FillTriangle(bm, x1, y1, x2, y2, x3, y3, arr_color, 1, '')
    end


    -- Draw Text
    reaper.JS_LICE_SetFontColor(lice_font, text_color)
    local len = tostring(text):len()
    local LICE_DrawText = reaper.JS_LICE_DrawText
    text_y = text_y + (user_font_yoffs or 0)

    if text_x < text_m_l then text_x = text_m_l end
    local m_r_diff = (text_x + text_w) - (w - text_m_r)
    if m_r_diff > 0 then text_x = math.max(box_m, text_x - m_r_diff) end

    LICE_DrawText(bm, lice_font, text, len, text_x, text_y, w - text_m_r, h)
end

local chord_name_candidate
local chord_icon_candidate

local function SetChordDisplay(name, icon)
    if chord_name_candidate == nil then
        -- First ever call: Commit immediately and stage
        chord_name_candidate = name
        chord_icon_candidate = icon
    end
    if name == chord_name_candidate and icon == chord_icon_candidate then
        -- Confirmed second call in a row, commit both
        if chord_text ~= name or chord_icon ~= icon then
            chord_text = name
            chord_icon = icon
            is_redraw = true
        end
    else
        -- Stage both
        chord_name_candidate = name
        chord_icon_candidate = icon
    end
end

function OnRun()
    sel_track = reaper.GetSelectedTrack(0, 0)
    local time = reaper.time_precise()
    -- Process input chords that user plays on MIDI keyboard
    local input_chord
    if detect_mode & 1 == 1 then
        input_chord = GetMIDIInputChord()
    end
    if input_chord then
        input_timer = time
        local chord_name = BuildChordName(input_chord)
        -- Avoid flashes: Only chance name when same for 2 cycles
        if chord_name == prev_input_chord_name then
            input_chord_name = chord_name
        end
        prev_input_chord_name = chord_name
    end

    -- Show input chords a bit longer than they are played (linger)
    if input_timer then
        if input_chord_name == '' and not input_chord then
            input_chord_name = prev_input_chord_name
        end
        SetChordDisplay(input_chord_name, 3)
        local linger_duration = 0.6
        if time < input_timer + linger_duration then
            return
        else
            input_timer = nil
            is_redraw = true
        end
    end

    if is_intercept or (detect_mode & 14 == 0) then
        SetChordDisplay('', 0)
        return
    end

    if reaper.GetItemEditingTime2() > 0 then return end

    local take_notes = {}
    local cursor_pos = -1

    local mode = 0
    local take

    if detect_mode & 8 == 8 then
        take = select(2, reaper.GetItemFromPoint(mouse_x, mouse_y, true))
    end
    if take and reaper.TakeIsMIDI(take) then
        mode = 2
        cursor_pos = reaper.GetSet_ArrangeView2(0, false, mouse_x, mouse_x + 1, 0)
        local notes = LoadNotes(take)
        take_notes = {notes}

        local item = reaper.GetMediaItemTake_Item(take)
        local active_take = reaper.GetActiveTake(item)

        if reaper.IsMediaItemSelected(item) and take == active_take then
            local other_takes = GetOverlappingSelectedMIDITakes(item)
            for i = 1, #other_takes do
                local other_notes = LoadNotes(other_takes[i])
                take_notes[#take_notes + 1] = other_notes
            end
        end
    elseif detect_mode & 6 ~= 0 then
        if detect_mode & 2 == 2 then cursor_pos = reaper.GetCursorPosition() end
        if detect_mode & 4 == 4 and reaper.GetPlayState() > 0 then
            mode = 1
            cursor_pos = reaper.GetPlayPosition()
        end

        if cursor_pos > 0 then
            cursor_pos = cursor_pos + 0.0001

            local sel_track_cnt = reaper.CountSelectedTracks(0)
            local _, measure = reaper.TimeMap2_timeToBeats(0, cursor_pos)

            if sel_track_cnt == 0 then
                local track = reaper.GetLastTouchedTrack()
                if track then
                    local takes = GetAudibleMIDITakesAtMeasure(track, measure)
                    for i = 1, #takes do
                        local notes = LoadNotes(takes[i])
                        take_notes[#take_notes + 1] = notes
                    end
                end
            else
                for t = 0, sel_track_cnt - 1 do
                    local track = reaper.GetSelectedTrack(0, t)
                    local takes = GetAudibleMIDITakesAtMeasure(track, measure)
                    for i = 1, #takes do
                        local notes = LoadNotes(takes[i])
                        take_notes[#take_notes + 1] = notes
                    end
                end
            end
        end
    end

    -- Clean up take_note_map every few seconds
    if time > cleanup_time + 5 then
        cleanup_time = time
        for guid, entry in pairs(take_note_map) do
            if not reaper.ValidatePtr(entry.take, 'MediaItem_Take*') then
                take_note_map[guid] = nil
            end
        end
    end

    local have_notes_changed = #take_notes ~= #prev_take_notes
    if not have_notes_changed then
        for t = 1, #take_notes do
            if take_notes[t] ~= prev_take_notes[t] then
                have_notes_changed = true
                break
            end
        end
    end

    if have_notes_changed then
        curr_chords = nil
        prev_take_notes = take_notes
        local combined_notes = CombineNotes(take_notes)
        if #combined_notes > 0 then
            curr_chords = GetChords(combined_notes)
        end
    end

    local curr_chord

    if curr_chords then
        local cursor_qn = reaper.TimeMap_timeToQN(cursor_pos)
        if mode == 2 then
            for i = 1, #curr_chords do
                local chord = curr_chords[i]
                if chord.sqn > cursor_qn then break end
                if cursor_qn >= chord.sqn and cursor_qn <= chord.eqn then
                    curr_chord = chord
                    break
                end
            end
        end

        if mode == 0 then
            mode = 7
            for i = 1, #curr_chords do
                local chord = curr_chords[i]
                if chord.sqn > cursor_qn then
                    if curr_chord and chord.sqn - cursor_qn < cursor_qn - curr_chord.eqn then
                        curr_chord = chord
                        mode = 8
                    end
                    break
                end
                curr_chord = chord
                if cursor_qn >= chord.sqn and cursor_qn <= chord.eqn then
                    curr_chord = chord
                    mode = 0
                    break
                end
            end
            if not curr_chord and #curr_chords > 0 then
                curr_chord = curr_chords[1]
                mode = 8
            end
        end

        if mode == 1 then
            for i = 1, #curr_chords do
                local chord = curr_chords[i]
                if chord.sqn > cursor_qn then break end
                curr_chord = chord
            end
            if not curr_chord and #curr_chords > 0 and detect_mode & 2 == 2 then
                curr_chord = curr_chords[1]
                mode = 8
            end
        end
    end

    local name = BuildChordName(curr_chord)
    if mode == 2 and name == '' then name = 'None' end
    SetChordDisplay(name, mode)
end
