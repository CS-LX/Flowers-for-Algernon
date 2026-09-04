-- 关卡触发应用层。
-- Inspector 只提供 Trigger ID；开火条件在物体代码 / 静物辅助脚本里。
-- 当前一律 Publish +1，不从 JSON 读信号值。
-- 静物辅助脚本按 modelId 查找，不在本文件硬编码 Door。

local LevelSignalBus = require "LevelSignalBus"
local StillHelperCatalog = require "StillHelperCatalog"

---@class LevelTriggerRuntime
---@field session table
---@field fired table<string, boolean>
---@field previousPartId string|nil
---@field missingHelperWarned table<string, boolean>
local LevelTriggerRuntime = {}
LevelTriggerRuntime.__index = LevelTriggerRuntime

---@param session table
---@return LevelTriggerRuntime
function LevelTriggerRuntime.New(session)
    local self = setmetatable({}, LevelTriggerRuntime)
    self.session = session
    self.fired = {}
    ---@type string|nil
    self.previousPartId = nil
    self.missingHelperWarned = {}
    return self
end

---@param channelId string
---@param source table
---@return boolean
function LevelTriggerRuntime:PublishPositive(channelId, source)
    if type(channelId) ~= "string" or channelId == "" then
        return false
    end
    local objectId = source and source.id or nil
    if type(objectId) == "string" and self.fired[objectId] then
        return false
    end
    local bus = self.session and self.session.signalBus
    if not bus or not bus:IsAlive() then
        return false
    end
    if type(objectId) == "string" then
        self.fired[objectId] = true
    end
    source = source or {}
    print(string.format(
        "LevelTriggerRuntime: fire id=%s source=%s/%s value=+1",
        channelId,
        tostring(source.kind),
        tostring(objectId)
    ))
    return bus:Publish(channelId, LevelSignalBus.POSITIVE, source)
end

---@param object table
---@param playerPosition Vector3
---@return table
function LevelTriggerRuntime:BuildStillContext(object, playerPosition)
    local preview = self.session.preview
    local player = preview and preview.player
    local context = {
        playerPosition = playerPosition,
        playerSettled = player and player.IsSettledAtNode
            and player:IsSettledAtNode()
            or false,
        worldBox = nil,
    }
    local renderer = preview and preview.partRenderer
    if not renderer or not renderer.GetStillWorldBoundingBox then
        return context
    end
    context.worldBox = renderer:GetStillWorldBoundingBox(object.id)
    return context
end

function LevelTriggerRuntime:UpdateParts()
    local document = self.session.levelDocument
    local preview = self.session.preview
    local player = preview and preview.player
    if not document or not player then
        return
    end
    local partId = player:GetCurrentPartId()
    -- 出生点不算“踩上”；只在从其他 Part 走过来时开火。
    if self.previousPartId == nil then
        self.previousPartId = partId
        return
    end
    if partId and partId ~= self.previousPartId then
        local part = document:GetPart(partId)
        if part and part:HasBehavior("triggerable") then
            local triggerId = part:GetTriggerId()
            if triggerId ~= "" then
                print(string.format(
                    "LevelTriggerRuntime: step-on part=%s triggerId=%s",
                    part.id,
                    triggerId
                ))
                self:PublishPositive(triggerId, {
                    kind = "part",
                    id = part.id,
                })
            end
        end
    end
    self.previousPartId = partId
end

function LevelTriggerRuntime:UpdateStills()
    local document = self.session.levelDocument
    local preview = self.session.preview
    local player = preview and preview.player
    if not document or not player then
        return
    end
    local position = player:GetPosition()
    for _, object in ipairs(document:GetStillObjects()) do
        if object:HasBehavior("triggerable") and not self.fired[object.id] then
            local triggerId = object:GetTriggerId()
            if triggerId ~= "" then
                local helper = StillHelperCatalog.Get(object.modelId)
                if helper and type(helper.ShouldFire) == "function" then
                    local context = self:BuildStillContext(object, position)
                    if helper.ShouldFire(object, context) then
                        print(string.format(
                            "LevelTriggerRuntime: still ready id=%s model=%s triggerId=%s",
                            object.id,
                            tostring(object.modelId),
                            triggerId
                        ))
                        self:PublishPositive(triggerId, {
                            kind = "stillObject",
                            id = object.id,
                            modelId = object.modelId,
                        })
                    end
                elseif not self.missingHelperWarned[object.id] then
                    self.missingHelperWarned[object.id] = true
                    print(string.format(
                        "LevelTriggerRuntime: still %s model=%s has no helper, skip",
                        object.id,
                        tostring(object.modelId)
                    ))
                end
            end
        end
    end
end

function LevelTriggerRuntime:Update()
    if not self.session or not self.session.signalBus then
        return
    end
    self:UpdateParts()
    self:UpdateStills()
end

function LevelTriggerRuntime:Dispose()
    self.fired = {}
    self.previousPartId = nil
    self.missingHelperWarned = {}
end

return LevelTriggerRuntime
