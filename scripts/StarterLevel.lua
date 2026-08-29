-- 初始关卡工厂。
-- 关卡文件不存在或损坏时，从 levels/starter-inline.json 恢复默认关卡。
-- 不阻塞启动：坏档先备份，再导入内联模板。

local LevelDocument = require "LevelDocument"

local StarterLevel = {}

local LEVEL_PATH = "levels/default-level.json"
local TEMPLATE_PATH = "levels/starter-inline.json"

local function BackupCorruptFile(path)
    if not fileSystem:FileExists(path) then
        return nil
    end
    local stamp = os.date("%Y%m%d-%H%M%S")
    local backupPath = path .. ".corrupt-" .. stamp .. ".bak"
    if fileSystem:Copy(path, backupPath) then
        fileSystem:Delete(path)
        return backupPath
    end
    if fileSystem:Rename(path, backupPath) then
        return backupPath
    end
    return nil
end

local function ReadTemplateJson()
    if not fileSystem:FileExists(TEMPLATE_PATH) then
        return nil, "missing starter template: " .. TEMPLATE_PATH
    end
    local file = File(TEMPLATE_PATH, FILE_READ)
    if not file:IsOpen() then
        return nil, "cannot open starter template"
    end
    local json = file:ReadString()
    file:Close()
    if type(json) ~= "string" or json == "" then
        return nil, "starter template is empty"
    end
    return json
end

local function CreateDefaultLevel(grid)
    local json, readError = ReadTemplateJson()
    if not json then
        return nil, readError
    end
    local level = LevelDocument.New(LEVEL_PATH)
    local imported, importError = level:ImportInlineJson(json, grid)
    if not imported then
        return nil, importError
    end
    print("Created starter level from " .. TEMPLATE_PATH)
    return level
end

function StarterLevel.LoadOrCreate(grid)
    if fileSystem:FileExists(LEVEL_PATH) then
        local level = LevelDocument.New(LEVEL_PATH)
        local loaded, errorMessage = level:Load()
        if loaded then
            return level
        end

        local backupPath = BackupCorruptFile(LEVEL_PATH)
        local recovered, recoverError = CreateDefaultLevel(grid)
        if not recovered then
            return nil, recoverError
        end
        recovered.loadWarning = {
            title = "关卡已损坏，已恢复默认关卡",
            message = "当前关卡 JSON 无法加载：" .. tostring(errorMessage)
                .. "\n已恢复为默认关卡，坏档备份为："
                .. tostring(backupPath or "备份失败，原文件未能移走"),
        }
        print("StarterLevel: corrupt level recovered from " .. tostring(errorMessage)
            .. " backup=" .. tostring(backupPath))
        return recovered, recovered.loadWarning.message
    end

    return CreateDefaultLevel(grid)
end

return StarterLevel
