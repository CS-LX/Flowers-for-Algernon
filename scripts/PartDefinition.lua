-- 关卡中一个可编辑/可运行的 Part 定义。
-- Part 由局部体素资产、共同 Transform、可编辑能力和可组合行为组成。
-- 行为不再由互斥的 Part 类型表达。

local PartDefinition = {}
PartDefinition.__index = PartDefinition

PartDefinition.MODE_ROTATOR = "rotator"
PartDefinition.MODE_TRIGGERABLE = "triggerable"

local function CopyVector(value, fallback)
    value = value or {}
    fallback = fallback or {}
    return {
        x = value.x ~= nil and value.x or (fallback.x or 0),
        y = value.y ~= nil and value.y or (fallback.y or 0),
        z = value.z ~= nil and value.z or (fallback.z or 0),
    }
end

local function CopyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyTable(item)
    end
    return result
end

local function CopySteps(steps)
    local result = {}
    for index, step in ipairs(steps or { 0, 1, 2, 3, 4, 5 }) do
        result[index] = step
    end
    return result
end

local function NormalizeSteps(steps)
    return ((math.floor(steps or 0) % 6) + 6) % 6
end

local function NormalizeAllowedSteps(steps)
    local result = {}
    local known = {}
    for _, step in ipairs(steps or { 0, 1, 2, 3, 4, 5 }) do
        local normalized = NormalizeSteps(step)
        if not known[normalized] then
            known[normalized] = true
            result[#result + 1] = normalized
        end
    end
    if #result == 0 then
        return { 0, 1, 2, 3, 4, 5 }
    end
    return result
end

local function ContainsStep(steps, wanted)
    for _, step in ipairs(steps) do
        if step == wanted then
            return true
        end
    end
    return false
end

local function CopyCapabilities(source)
    source = source or {}
    return {
        move = source.move ~= false,
        rotate = source.rotate ~= false,
        scale = source.scale == true,
    }
end

local function CopyBehaviorModes(source)
    local result = {}
    local known = {}
    for _, mode in ipairs(source or {}) do
        if type(mode) == "string" and mode ~= "" and not known[mode] then
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

function PartDefinition.New(data)
    local self = setmetatable({}, PartDefinition)
    self:Init(data)
    return self
end

function PartDefinition:Init(data)
    data = data or {}
    self.id = data.id or "part"
    self.name = data.name or self.id
    self.parentId = data.parentId
    self.localVoxelPath = data.localVoxelPath or ("parts/" .. self.id .. ".json")

    local legacyRotator = data.type == "rotator"
    local transform = data.transform or {}
    local rotation = transform.rotation or {}
    self.transform = {
        position = CopyVector(transform.position),
        rotation = {
            yawSteps = NormalizeSteps(rotation.yawSteps or transform.rotationSteps),
            pitchSteps = NormalizeSteps(rotation.pitchSteps),
            rollSteps = NormalizeSteps(rotation.rollSteps),
        },
        scale = CopyVector(transform.scale, { x = 1, y = 1, z = 1 }),
    }

    self.transformCapabilities = CopyCapabilities(data.transformCapabilities)
    self.behaviorModes = CopyBehaviorModes(data.behaviorModes)
    if legacyRotator and not HasMode(self.behaviorModes, PartDefinition.MODE_ROTATOR) then
        self.behaviorModes[#self.behaviorModes + 1] = PartDefinition.MODE_ROTATOR
    end

    local legacyBehavior = data.behavior or {}
    local sourceBehaviors = data.behaviors or {}
    self.behaviors = CopyTable(sourceBehaviors) or {}
    if HasMode(self.behaviorModes, PartDefinition.MODE_ROTATOR) then
        local source = sourceBehaviors.rotator or legacyBehavior
        self.behaviors.rotator = {
            axis = "Y",
            stepDegrees = 60,
            allowedSteps = NormalizeAllowedSteps(source.allowedSteps),
            state = NormalizeSteps(source.state or self.transform.rotation.yawSteps),
            duration = source.duration or 0.45,
        }
        self.transformCapabilities.scale = false
        self.transform.scale = { x = 1, y = 1, z = 1 }
    end

    if HasMode(self.behaviorModes, PartDefinition.MODE_TRIGGERABLE) then
        local source = sourceBehaviors.triggerable or {}
        self.behaviors.triggerable = {
            triggerId = source.triggerId or "",
        }
    end

    self:Normalize()
end

function PartDefinition:Normalize()
    self.transform.rotation.yawSteps = NormalizeSteps(self.transform.rotation.yawSteps)
    self.transform.rotation.pitchSteps = NormalizeSteps(self.transform.rotation.pitchSteps)
    self.transform.rotation.rollSteps = NormalizeSteps(self.transform.rotation.rollSteps)

    if self:HasBehavior(PartDefinition.MODE_ROTATOR) then
        self.transformCapabilities.scale = false
        self.transform.scale = { x = 1, y = 1, z = 1 }
        self.behaviors.rotator.state = NormalizeSteps(self.behaviors.rotator.state)
        if not ContainsStep(self.behaviors.rotator.allowedSteps, self.behaviors.rotator.state) then
            self.behaviors.rotator.state = self.behaviors.rotator.allowedSteps[1]
        end
        self.transform.rotation.yawSteps = self.behaviors.rotator.state
    elseif not self.transformCapabilities.scale then
        self.transform.scale = { x = 1, y = 1, z = 1 }
    else
        local uniform = self.transform.scale.x
        self.transform.scale = { x = uniform, y = uniform, z = uniform }
    end
end

function PartDefinition:HasBehavior(mode)
    return HasMode(self.behaviorModes, mode)
end

function PartDefinition:CanTransform(operation)
    return self.transformCapabilities[operation] == true
end

function PartDefinition:SetYawSteps(steps)
    if not self:CanTransform("rotate") then
        return false
    end
    local normalized = NormalizeSteps(steps)
    if self:HasBehavior(PartDefinition.MODE_ROTATOR)
        and not ContainsStep(self.behaviors.rotator.allowedSteps, normalized) then
        return false
    end
    self.transform.rotation.yawSteps = normalized
    if self:HasBehavior(PartDefinition.MODE_ROTATOR) then
        self.behaviors.rotator.state = normalized
    end
    return true
end

function PartDefinition:ToTable()
    local behaviors = CopyTable(self.behaviors) or {}
    if self:HasBehavior(PartDefinition.MODE_ROTATOR) then
        local rotator = self.behaviors.rotator
        behaviors.rotator = {
            axis = rotator.axis,
            stepDegrees = rotator.stepDegrees,
            allowedSteps = CopySteps(rotator.allowedSteps),
            state = rotator.state,
            duration = rotator.duration,
        }
    end
    if self:HasBehavior(PartDefinition.MODE_TRIGGERABLE) then
        behaviors.triggerable = {
            triggerId = self.behaviors.triggerable.triggerId,
        }
    end

    return {
        id = self.id,
        name = self.name,
        parentId = self.parentId,
        localVoxelPath = self.localVoxelPath,
        transform = {
            position = CopyVector(self.transform.position),
            rotation = {
                yawSteps = self.transform.rotation.yawSteps,
                pitchSteps = self.transform.rotation.pitchSteps,
                rollSteps = self.transform.rotation.rollSteps,
            },
            scale = CopyVector(self.transform.scale),
        },
        transformCapabilities = CopyCapabilities(self.transformCapabilities),
        behaviorModes = CopyBehaviorModes(self.behaviorModes),
        behaviors = behaviors,
    }
end

function PartDefinition.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid PartDefinition"
    end
    return PartDefinition.New(data)
end

return PartDefinition
