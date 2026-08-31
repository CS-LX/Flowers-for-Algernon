-- 关卡演出抽象基类。
-- 只服务一个关卡实例：生命周期跟 LevelSession，信号跟 LevelSignalBus。
-- 具体关卡演出继承本类；不要改这个文件去加某一关的剧情。

local LevelSignalBus = require "LevelSignalBus"

---@class LevelDirector
---@field session table
---@field definition table
---@field started boolean
---@field subscriptions table[]
local LevelDirector = {}
LevelDirector.__index = LevelDirector

---@param session table
---@return LevelDirector
function LevelDirector.New(session)
    local self = setmetatable({}, LevelDirector)
    self:Init(session)
    return self
end

--- 新建一个只服务某一关的演出类。新增关卡演出时继承这个，不要改基类。
---@return LevelDirector
function LevelDirector.Extend()
    local class = setmetatable({}, { __index = LevelDirector })
    class.__index = class
    ---@param session table
    ---@return LevelDirector
    function class.New(session)
        local self = setmetatable({}, class)
        self:Init(session)
        return self
    end
    return class
end

---@param session table
function LevelDirector:Init(session)
    self.session = session
    self.definition = session and session.definition or nil
    self.started = false
    self.subscriptions = {}
end

function LevelDirector:GetSession()
    return self.session
end

function LevelDirector:GetDefinition()
    return self.definition
end

function LevelDirector:GetLevelId()
    return self.definition and self.definition.id or nil
end

function LevelDirector:GetDocument()
    return self.session and self.session.levelDocument or nil
end

function LevelDirector:GetPreview()
    return self.session and self.session.preview or nil
end

function LevelDirector:GetSignalBus()
    return self.session and self.session.signalBus or nil
end

function LevelDirector:GetPlayer()
    local preview = self:GetPreview()
    return preview and preview.player or nil
end

---@param channelId string
---@param value number
---@param source table|nil
---@return boolean, string|nil
function LevelDirector:Publish(channelId, value, source)
    local bus = self:GetSignalBus()
    if not bus then
        return false, "no signal bus"
    end
    return bus:Publish(channelId, value, source or {
        kind = "director",
        id = self:GetLevelId(),
    })
end

---@param channelId string
---@param listener fun(payload: table)
---@return number|nil
function LevelDirector:Subscribe(channelId, listener)
    local bus = self:GetSignalBus()
    if not bus then
        return nil
    end
    local handle = bus:Subscribe(channelId, listener)
    if handle then
        self.subscriptions[#self.subscriptions + 1] = {
            channelId = channelId,
            handle = handle,
        }
    end
    return handle
end

function LevelDirector:UnsubscribeAll()
    local bus = self:GetSignalBus()
    if bus then
        for _, item in ipairs(self.subscriptions) do
            bus:Unsubscribe(item.channelId, item.handle)
        end
    end
    self.subscriptions = {}
end

function LevelDirector:GetPart(partId)
    local document = self:GetDocument()
    return document and document:GetPart(partId) or nil
end

function LevelDirector:GetStillObject(objectId)
    local document = self:GetDocument()
    return document and document:GetStillObject(objectId) or nil
end

---@param objectId string
---@return table|nil
function LevelDirector:GetAlgernon(objectId)
    local document = self:GetDocument()
    if not document then
        return nil
    end
    if type(objectId) == "string" and objectId ~= "" then
        local object = document:GetStillObject(objectId)
        if object and object.modelId == "algernon" then
            return object
        end
        return nil
    end
    for _, object in ipairs(document:GetStillObjects()) do
        if object.modelId == "algernon" then
            return object
        end
    end
    return nil
end

function LevelDirector:SetInputLocked(locked)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    preview:SetInputLocked(locked)
    return true
end

function LevelDirector:SetPlayerLocked(locked)
    local player = self:GetPlayer()
    if not player then
        return false
    end
    player:SetMechanismLocked(locked)
    return true
end

function LevelDirector:SetPlayerVisible(visible)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetPlayerVisible(visible)
end

function LevelDirector:SetPlayerSpeed(speed)
    local player = self:GetPlayer()
    if not player then
        return false
    end
    return player:SetSpeed(speed)
end

function LevelDirector:MovePlayerTo(nodeKey)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:MovePlayerTo(nodeKey)
end

function LevelDirector:TeleportPlayerTo(nodeKey)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:TeleportPlayerTo(nodeKey)
end

function LevelDirector:StopPlayer()
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:StopPlayer()
end

function LevelDirector:SetObjectEnabled(objectId, enabled)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetObjectEnabled(objectId, enabled)
end

function LevelDirector:SetStillVisible(objectId, visible)
    return self:SetObjectEnabled(objectId, visible)
end

---@param objectId string
---@param driverId string
---@param value number
---@return boolean
function LevelDirector:SetStillDriver(objectId, driverId, value)
    local object = self:GetStillObject(objectId)
    if not object then
        return false
    end
    if not object:SetDriver(driverId, value) then
        return false
    end
    local preview = self:GetPreview()
    return preview and preview:ApplyStillObject(object) or false
end

---@param objectId string
---@param path string
---@param value string|nil
---@return boolean
function LevelDirector:SetStillParam(objectId, path, value)
    local object = self:GetStillObject(objectId)
    if not object then
        return false
    end
    if not object:SetParam(path, value) then
        return false
    end
    local preview = self:GetPreview()
    return preview and preview:ApplyStillObject(object) or false
end

---@param objectId string
---@param transform table
---@return boolean
function LevelDirector:SetStillTransform(objectId, transform)
    local object = self:GetStillObject(objectId)
    if not object or type(transform) ~= "table" then
        return false
    end
    if transform.position then
        object:SetPosition(transform.position)
    end
    if transform.rotation then
        object:SetRotation(transform.rotation)
    end
    if transform.scale then
        object:SetScale(transform.scale)
    end
    local preview = self:GetPreview()
    return preview and preview:ApplyStillObject(object) or false
end

---@param partId string
---@param steps number
---@param refreshPath boolean|nil
---@return boolean, string|nil
function LevelDirector:SetPartYawSteps(partId, steps, refreshPath)
    local part = self:GetPart(partId)
    if not part then
        return false, "part-not-found"
    end
    if not part:SetYawSteps(steps) then
        return false, "yaw-rejected"
    end
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:ApplyPart(part, refreshPath)
end

---@param partId string
---@param position table
---@param refreshPath boolean|nil
---@return boolean, string|nil
function LevelDirector:SetPartPosition(partId, position, refreshPath)
    local part = self:GetPart(partId)
    if not part then
        return false, "part-not-found"
    end
    if not part:SetPosition(position) then
        return false, "position-rejected"
    end
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:ApplyPart(part, refreshPath)
end

function LevelDirector:FinishLevel()
    return self:Publish(LevelSignalBus.FINISH_ID, LevelSignalBus.POSITIVE, {
        kind = "director",
        id = self:GetLevelId(),
    })
end

--- 子类覆盖：关卡场景已启动，可订阅信号并做开场准备。
function LevelDirector:OnStart()
end

--- 子类覆盖：每帧演出逻辑。
---@param timeStep number
function LevelDirector:OnUpdate(timeStep)
end

--- 子类覆盖：关卡拆除前清理本关演出状态。基类会 UnsubscribeAll。
function LevelDirector:OnDispose()
end

function LevelDirector:Start()
    if self.started then
        return false, "director already started"
    end
    self.started = true
    print("LevelDirector: start level=" .. tostring(self:GetLevelId()))
    self:OnStart()
    return true
end

---@param timeStep number
function LevelDirector:Update(timeStep)
    if not self.started then
        return
    end
    self:OnUpdate(timeStep)
end

function LevelDirector:Dispose()
    print(string.format(
        "LevelDirector: dispose level=%s",
        tostring(self:GetLevelId())
    ))
    self:OnDispose()
    self:UnsubscribeAll()
    self.started = false
    self.session = nil
    self.definition = nil
end

return LevelDirector
