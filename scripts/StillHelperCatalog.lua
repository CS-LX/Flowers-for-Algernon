-- 静物辅助脚本目录。
-- 按 modelId 查找；没有辅助脚本的静物不会自动开火。

local StillHelperCatalog = {}

local MODULES = {
    door = "StillHelpers.Door",
}

---@type table<string, table|boolean>
local loaded_ = {}

---@param modelId string|nil
---@return table|nil
function StillHelperCatalog.Get(modelId)
    if type(modelId) ~= "string" or modelId == "" then
        return nil
    end
    local cached = loaded_[modelId]
    if cached == false then
        return nil
    end
    if type(cached) == "table" then
        return cached
    end
    local moduleName = MODULES[modelId]
    if not moduleName then
        loaded_[modelId] = false
        return nil
    end
    local ok, helper = pcall(require, moduleName)
    if ok and type(helper) == "table" then
        loaded_[modelId] = helper
        print("StillHelperCatalog: loaded " .. modelId .. " -> " .. moduleName)
        return helper
    end
    print("StillHelperCatalog: failed to load " .. tostring(moduleName) .. " err=" .. tostring(helper))
    loaded_[modelId] = false
    return nil
end

return StillHelperCatalog
