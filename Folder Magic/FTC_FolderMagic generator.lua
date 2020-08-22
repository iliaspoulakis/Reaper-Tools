--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @noindex
  @about Generates various configurations of FolderMagic
]]
local _, file_name = reaper.get_action_context()
local seperator = reaper.GetOS():match('win') and '\\' or '/'
local file_path = file_name:match('(.*' .. seperator .. ')')
local main_name = 'FTC_FolderMagic - Prompt dialog.lua'
local file = io.open(file_path .. main_name, 'r')

-- Load MeMagic script content
local content = {}
if file then
    for line in file:lines() do
        content[#content + 1] = line
    end
    file:close()
end

-- Create path for generated files
local gen_folder_name = 'Generated'
local dir_path = file_path .. gen_folder_name .. seperator
reaper.RecursiveCreateDirectory(dir_path, 0)

-- Remove old files
local i = 0
repeat
    local file = reaper.EnumerateFiles(dir_path, i)
    if file then
        local file_path = dir_path .. file
    end
    i = i + 1
until not file

for n = i, 0, -1 do
    local file = reaper.EnumerateFiles(dir_path, n)
    if file then
        local file_path = dir_path .. file
        os.remove(file_path)
    end
end

local config = ''
local provides = '    [main=main] '
local prefix = 'FTC_FolderMagic - '

for i = 1, 12 do
    local new_file_name = prefix .. 'Folder ' .. i .. '.lua'
    if i == 10 then
        new_file_name = prefix .. 'All tracks & folders.lua'
    end
    if i == 11 then
        new_file_name = prefix .. 'Next folder.lua'
    end
    if i == 12 then
        new_file_name = prefix .. 'Previous folder.lua'
    end
    local new_file_path = dir_path .. new_file_name
    local new_file = io.open(new_file_path, 'w')
    for _, line in ipairs(content) do
        new_file:write(line, '\n')
    end
    new_file:close()
    config = config .. provides .. gen_folder_name .. '/' .. new_file_name .. '\n'
end

config = config .. provides .. main_name .. '\n'
config = config .. provides .. prefix .. 'Settings.lua\n'

local file = io.open(file_path .. 'FTC_FolderMagic bundle.lua', 'w')

if file then
    -- Create package with configurations
    for _, line in ipairs(content) do
        if not line:match('@noindex') then
            if line:match('@about') then
                local meta_pkg = '\n  @metapackage\n'
                local line = line .. meta_pkg .. '  @provides\n' .. config .. ']]'
                content[#content + 1] = line
                file:write(line, '\n')
                break
            end
            content[#content + 1] = line
            file:write(line, '\n')
        end
    end
    file:close()
end
