--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Specify custom colors (override) for unthemeable areas
 ]]

local extname = 'FTC.LibSwell_Colorizer'
local colors_str = reaper.GetExtState(extname, 'custom_colors')

local title = 'Color override'
local captions = 'Button: (e.g. #FF0000)'

local ret, inputs = reaper.GetUserInputs(title, 1, captions, colors_str)
if not ret then return end

local invalid_flag = false
local function ValidateColor(color)
    color = color:gsub('^#', '')
    local num = tonumber(color, 16)
    local is_valid = num and #color <= 6
    if is_valid then return ('#%06x'):format(num) end
    if color ~= '' then invalid_flag = true end
    return ''
end

local colors = {}
for color in (inputs .. ','):gmatch('[^,]*') do
    colors[#colors + 1] = ValidateColor(color)
end

colors_str = table.concat(colors, ',')

reaper.SetExtState(extname, 'custom_colors', colors_str, true)

if invalid_flag then
    local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
    reaper.MB(msg, 'Invalid input', 0)
end
