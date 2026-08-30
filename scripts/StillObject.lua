-- 关卡装饰静物。
-- 无体素、无 PathNode、无机关；保存父节点局部 Transform、模型绑定和覆盖参数。

local StillModelCatalog = require "StillModelCatalog"

---@class StillObject
---@field kind string
---@field id string
---@field name string
---@field parentId string|nil
---@field modelPath string
---@field modelId string
---@field paramStore table<string, table<string, string>>
---@field driverState table<string, number>
---@field transform table
---@field behaviorModes string[]
---@field behaviors table
local StillObject = {}
StillObject.__index = StillObject

local KIND = "stillObject"
local MODE_TRIGGERABLE = "triggerable"

local ALLOWED_MODES = {
    triggerable = true,
}


local function CopyVector(value, fallback)
    value = value or {}
    fallback = fallback or {}
    return {
        x = value.x ~= nil and value.x or (fallback.x or 0),
        y = value.y ~= nil and value.y or (fallback.y or 0),
        z = value.z ~= nil and value.z or (fallback.z or 0),
    }
end

local function CopyBehaviorModes(source)
    local result = {}
    local known = {}
    for _, mode in ipairs(source or {}) do
        if ALLOWED_MODES[mode] and not known[mode] then
            known[mode] = true
            result[#result + 1] = mode
        end
    end
    return result
end

local function HasMode(modes, wanted)
    for _, mode in ipairs(modes) do
        if mode == wanted then
            return true
        end
    end
    return false
end

local function CopyStringMap(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        if type(key) == "string" and type(value) == "string" then
            result[key] = value
        end
    end
    return result
end

local function CopyNumberMap(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for key, value in pairs(source) do
        local number = tonumber(value)
        if type(key) == "string" and number then
            result[key] = number * 1.0
        end
    end
    return result
end

local function CopyParamStore(source)
    local result = {}
    if type(source) ~= "table" then
        return result
    end
    for modelId, params in pairs(source) do
        if type(modelId) == "string" and modelId ~= "" then
            result[modelId] = CopyStringMap(params)
        end
    end
    return result
end

function StillObject.New(data)
    local self = setmetatable({}, StillObject)
    self:Init(data)
    return self
end

function StillObject:Init(data)
    data = data or {}
    self.kind = KIND
    self.id = data.id or "still"
    self.name = data.name or self.id
    self.parentId = data.parentId
    self.modelPath = type(data.modelPath) == "string" and data.modelPath or ""
    self.modelId = type(data.modelId) == "string" and data.modelId or ""
    if self.modelId == "" and self.modelPath == "Meshes/Door.mdl" then
        self.modelId = "door"
    end
    self.paramStore = CopyParamStore(data.paramStore)
    if type(data.params) == "table" and self.modelId ~= "" and not self.paramStore[self.modelId] then
        self.paramStore[self.modelId] = CopyStringMap(data.params)
    end
    self.driverState = CopyNumberMap(data.driverState)
    if self.modelId ~= "" then
        local asset = StillModelCatalog.Get(self.modelId)
        if asset then
            self.modelPath = asset.modelPath
            local defaults = StillModelCatalog.DefaultDrivers(asset)
            for driverId, value in pairs(defaults) do
                if self.driverState[driverId] == nil then
                    self.driverState[driverId] = value
                end
            end
        end
    end
    local transform = data.transform or {}
    self.transform = {
        position = CopyVector(transform.position),
        rotation = CopyVector(transform.rotation),
        scale = CopyVector(transform.scale, { x = 1, y = 1, z = 1 }),
    }
    self.behaviorModes = CopyBehaviorModes(data.behaviorModes)
    self.behaviors = {}
    if HasMode(self.behaviorModes, MODE_TRIGGERABLE) then
        local source = (data.behaviors or {}).triggerable or {}
        self.behaviors.triggerable = {
            triggerId = type(source.triggerId) == "string" and source.triggerId or "",
        }
    end
end

function StillObject:SetName(name)
    name = tostring(name or "")
    if name == "" then
        return false
    end
    self.name = name
    return true
end

function StillObject:SetParentId(parentId)
    if parentId == "" then
        parentId = nil
    end
    self.parentId = parentId
    return true
end

function StillObject:SetPosition(position)
    self.transform.position = CopyVector(position)
    return true
end

function StillObject:SetRotation(rotation)
    self.transform.rotation = CopyVector(rotation)
    return true
end

function StillObject:SetScale(scale)
    if type(scale) == "number" then
        scale = { x = scale, y = scale, z = scale }
    end
    local copied = CopyVector(scale, { x = 1, y = 1, z = 1 })
    if copied.x <= 0 or copied.y <= 0 or copied.z <= 0 then
        return false
    end
    self.transform.scale = copied
    return true
end

function StillObject:SetModelPath(path)
    self.modelPath = type(path) == "string" and path or ""
    return true
end

function StillObject:GetAsset()
    return StillModelCatalog.Get(self.modelId)
end

function StillObject:SetModelId(modelId)
    if type(modelId) ~= "string" then
        modelId = ""
    end
    if self.modelId == modelId then
        return true
    end
    if self.modelId ~= "" then
        self.paramStore[self.modelId] = CopyStringMap(self.paramStore[self.modelId] or {})
    end
    self.modelId = modelId
    local asset = self:GetAsset()
    self.modelPath = asset and asset.modelPath or ""
    if modelId ~= "" then
        self.paramStore[modelId] = CopyStringMap(self.paramStore[modelId] or {})
        local defaults = StillModelCatalog.DefaultDrivers(asset)
        for driverId, value in pairs(defaults) do
            if self.driverState[driverId] == nil then
                self.driverState[driverId] = value
            end
        end
    end
    return true
end

function StillObject:HasModel()
    return self.modelId ~= "" or self.modelPath ~= ""
end

function StillObject:GetActiveParams()
    if self.modelId == "" then
        return {}
    end
    return CopyStringMap(self.paramStore[self.modelId] or {})
end

function StillObject:SetParam(path, value)
    if self.modelId == "" or type(path) ~= "string" or path == "" then
        return false
    end
    self.paramStore[self.modelId] = self.paramStore[self.modelId] or {}
    if value == nil or value == "" then
        self.paramStore[self.modelId][path] = nil
    else
        self.paramStore[self.modelId][path] = tostring(value)
    end
    return true
end

function StillObject:GetDriverState()
    local asset = self:GetAsset()
    local result = StillModelCatalog.DefaultDrivers(asset)
    for key, value in pairs(self.driverState) do
        result[key] = value
    end
    return result
end

function StillObject:GetDriver(driverId)
    local state = self:GetDriverState()
    return state[driverId] or 0.0
end

function StillObject:SetDriver(driverId, value)
    local asset = self:GetAsset()
    local driver = StillModelCatalog.GetDriver(asset, driverId)
    if not driver then
        return false
    end
    local number = tonumber(value)
    if not number then
        return false
    end
    if number < driver.min then
        number = driver.min
    elseif number > driver.max then
        number = driver.max
    end
    self.driverState[driverId] = number * 1.0
    return true
end

function StillObject:HasBehavior(mode)
    return HasMode(self.behaviorModes, mode)
end

function StillObject:SetInteraction(mode, enabled)
    if not ALLOWED_MODES[mode] then
        return false
    end
    local hasMode = self:HasBehavior(mode)
    if enabled and not hasMode then
        self.behaviorModes[#self.behaviorModes + 1] = mode
    elseif (not enabled) and hasMode then
        local nextModes = {}
        for _, current in ipairs(self.behaviorModes) do
            if current ~= mode then
                nextModes[#nextModes + 1] = current
            end
        end
        self.behaviorModes = nextModes
        self.behaviors[mode] = nil
    end
    if enabled and mode == MODE_TRIGGERABLE then
        self.behaviors.triggerable = self.behaviors.triggerable or { triggerId = "" }
    end
    return true
end

function StillObject:SetTriggerId(triggerId)
    if not self:HasBehavior(MODE_TRIGGERABLE) then
        return false
    end
    self.behaviors.triggerable.triggerId = tostring(triggerId or "")
    return true
end


function StillObject:ToTable()
    local data = {
        kind = KIND,
        id = self.id,
        name = self.name,
        parentId = self.parentId,
        modelId = self.modelId ~= "" and self.modelId or nil,
        modelPath = self.modelPath ~= "" and self.modelPath or nil,
        transform = {
            position = CopyVector(self.transform.position),
            rotation = CopyVector(self.transform.rotation),
            scale = CopyVector(self.transform.scale, { x = 1, y = 1, z = 1 }),
        },
    }
    if #self.behaviorModes > 0 then
        data.behaviorModes = {}
        for index, mode in ipairs(self.behaviorModes) do
            data.behaviorModes[index] = mode
        end
    end
    if self:HasBehavior(MODE_TRIGGERABLE) then
        data.behaviors = {
            triggerable = {
                triggerId = self.behaviors.triggerable.triggerId,
            },
        }
    end
    local paramStore = CopyParamStore(self.paramStore)
    if next(paramStore) then
        data.paramStore = paramStore
        if self.modelId ~= "" and paramStore[self.modelId] then
            data.params = CopyStringMap(paramStore[self.modelId])
        end
    end
    local driverState = CopyNumberMap(self.driverState)
    if next(driverState) then
        data.driverState = driverState
    end
    return data
end

function StillObject.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid StillObject"
    end
    return StillObject.New(data)
end

return StillObject
