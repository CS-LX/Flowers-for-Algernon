-- 关卡演出目录。
-- 对修改关闭、对扩展开放：新增某一关的演出时，
-- 1. 新建 scripts/LevelDirectors/<Name>.lua，用 LevelDirector.Extend()
-- 2. 只在 MODULES 里登记 关卡 id -> 模块名
-- 没有登记的关卡不创建导演，关卡照常可玩。
--
-- 子类模板：
-- local Chapter13 = require("LevelDirector").Extend()
-- function Chapter13:OnStart()
--     self:Subscribe("door.open", function(payload) end)
--     self:SetStillDriver("still_part", "open", 1)
-- end
-- function Chapter13:OnUpdate(timeStep) end
-- function Chapter13:OnDispose() end
-- return Chapter13

local LevelDirector = require "LevelDirector"

local LevelDirectorCatalog = {}

-- 具体关卡演出类按关卡 id 登记。当前为空：框架先落地，不写某一关剧情。
---@type table<string, string>
LevelDirectorCatalog.MODULES = {
    -- chapter_1_3 = "LevelDirectors.Chapter13",
}

---@param session table
---@return LevelDirector|nil
function LevelDirectorCatalog.Create(session)
    local definition = session and session.definition
    local levelId = definition and definition.id or nil
    if type(levelId) ~= "string" or levelId == "" then
        return nil
    end
    local moduleName = LevelDirectorCatalog.MODULES[levelId]
    if not moduleName then
        print("LevelDirectorCatalog: no director for " .. levelId)
        return nil
    end
    local ok, directorClass = pcall(require, moduleName)
    if not ok or type(directorClass) ~= "table" then
        print("LevelDirectorCatalog: failed to load " .. tostring(moduleName) .. " err=" .. tostring(directorClass))
        return nil
    end
    if type(directorClass.New) ~= "function" then
        print("LevelDirectorCatalog: " .. moduleName .. " has no New()")
        return nil
    end
    local director = directorClass.New(session)
    if director then
        print("LevelDirectorCatalog: created " .. levelId .. " -> " .. moduleName)
    end
    return director
end

LevelDirectorCatalog.Base = LevelDirector

return LevelDirectorCatalog
