--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about Reads colors from libSwell.colortheme and applies them to active theme
  @changelog
    - Fix issue with Windows newline characters
 ]]

local root_theme_path = reaper.GetExePath() .. '/libSwell.colortheme'
local user_theme_path = reaper.GetResourcePath() .. '/libSwell-user.colortheme'

local theme_path = user_theme_path
if not reaper.file_exists(theme_path) then
    theme_path = root_theme_path
    if not reaper.file_exists(theme_path) then
        reaper.MB('Could not find libswell color theme!', 'Error', 0)
        return
    end
end

local function GetSwellColor(color)
    color = color:gsub('^#', '')
    if #color ~= 6 or not tonumber(color, 16) then return end
    local r = tonumber(color:sub(1, 2), 16)
    local g = tonumber(color:sub(3, 4), 16)
    local b = tonumber(color:sub(5, 6), 16)
    if r and g and b then return reaper.ColorToNative(r, g, b) end
end

local swell_colors = {}
local file = io.open(theme_path, 'r')
if not file then return end
for line in file:lines() do
    local key, val = line:match('^([^ ]+) (#?%w+)')
    if key then
        swell_colors[key] = GetSwellColor(val)
    end
end
io.close(file)

local function SetThemeColor(key, color)
    if color then reaper.SetThemeColor(key, color, 0) end
end

SetThemeColor('col_main_bg', swell_colors._3dface)
SetThemeColor('col_main_text', swell_colors.button_text)
SetThemeColor('io_text', swell_colors.button_text)
SetThemeColor('io_text', swell_colors.button_text)
SetThemeColor('io_3dhl', swell_colors.button_text)
SetThemeColor('io_3dsh', swell_colors.button_text)

--SetThemeColor('midi_leftbg', swell_colors._3dface)
--SetThemeColor('col_main_3dhl', swell_colors._3dhilight)
--SetThemeColor('col_main_3dsh', swell_colors._3dshadow)
--SetThemeColor('col_main_editbk', swell_colors.edit_bg)

SetThemeColor('genlist_bg', swell_colors.listview_bg)
SetThemeColor('genlist_selbg', swell_colors.listview_bg_sel)
SetThemeColor('genlist_seliabg', swell_colors.listview_bg_sel_inactive
    or swell_colors.listview_bg_sel)

SetThemeColor('genlist_fg', swell_colors.listview_text)
SetThemeColor('genlist_selfg', swell_colors.listview_text_sel)
SetThemeColor('genlist_seliafg', swell_colors.listview_text_sel_inactive
    or swell_colors.listview_text_sel)

SetThemeColor('genlist_grid', swell_colors.listview_grid)

reaper.ThemeLayout_RefreshAll()
reaper.UpdateArrange()
