-- 关卡演出抽象基类。
-- 只服务一个关卡实例：生命周期跟 LevelSession，信号跟 LevelSignalBus。
-- 具体关卡演出继承本类；不要改这个文件去加某一关的剧情。

local LevelSignalBus = require "LevelSignalBus"
local StoryPlayer = require "StoryPlayer"

---@class LevelDirector
---@field session table
---@field definition table
---@field started boolean
---@field running boolean
---@field subscriptions table[]
---@field pendingStory table|nil
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
    self.running = false
    self.subscriptions = {}
    ---@type table|nil
    self.storyPlayer = nil
    self.storyInputLocked = false
    ---@type table|nil
    self.pendingStory = nil
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

function LevelDirector:GetAlgernon()
    local preview = self:GetPreview()
    return preview and preview.algernon or nil
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

function LevelDirector:SetInputLocked(locked)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    preview:SetInputLocked(locked)
    return true
end

function LevelDirector:SetPlayerLocked(locked)
    local preview = self:GetPreview()
    if preview and preview.riderFollow then
        preview.riderFollow:LockPlayer(locked)
        return true
    end
    local player = self:GetPlayer()
    if not player then
        return false
    end
    player:SetMechanismLocked(locked)
    return true
end

function LevelDirector:SyncRiders()
    local preview = self:GetPreview()
    if not preview or not preview.SyncRiders then
        return false
    end
    return preview:SyncRiders()
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

---@param enabled boolean
---@param nodeKey string|nil
---@return boolean, string|nil
function LevelDirector:SetAlgernonEnabled(enabled, nodeKey)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:SetAlgernonEnabled(enabled, nodeKey)
end

function LevelDirector:SetAlgernonVisible(visible)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetAlgernonVisible(visible)
end

---@param nodeKey string
---@return boolean, string|nil
function LevelDirector:MoveAlgernonTo(nodeKey)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:MoveAlgernonTo(nodeKey)
end

---@param nodeKey string
---@return boolean, string|nil
function LevelDirector:MoveAlgernonToIncludingCandidates(nodeKey)
    local preview = self:GetPreview()
    if not preview or not preview.algernon then
        return false, "no algernon"
    end
    return preview.algernon:MoveToIncludingCandidates(nodeKey)
end

function LevelDirector:MoveAlgernonToWorld(worldPoint)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:MoveAlgernonToWorld(worldPoint)
end

function LevelDirector:TeleportAlgernonTo(nodeKey)
    local preview = self:GetPreview()
    if not preview then
        return false, "no preview"
    end
    return preview:TeleportAlgernonTo(nodeKey)
end

function LevelDirector:StopAlgernon()
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:StopAlgernon()
end

function LevelDirector:SetAlgernonSpeed(speed)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetAlgernonSpeed(speed)
end

---@param transform table
---@return boolean
function LevelDirector:SetAlgernonLocalTransform(transform)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetAlgernonLocalTransform(transform)
end

---@param listener fun(nodeKey: string)|nil
---@return boolean
function LevelDirector:SetAlgernonOnArrived(listener)
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    return preview:SetAlgernonOnArrived(listener)
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

function LevelDirector:SetStillScale(objectId, scale)
    local object = self:GetStillObject(objectId)
    if not object or not object.SetPresentationScale then
        return false
    end
    if not object:SetPresentationScale(scale) then
        return false
    end
    local preview = self:GetPreview()
    return preview and preview:ApplyStillObject(object) or false
end

function LevelDirector:SetPartVisualYaw(partId, yawDegrees)
    local preview = self:GetPreview()
    if not preview or not preview.partRenderer then
        return false
    end
    return preview.partRenderer:SetVisualYaw(partId, yawDegrees)
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

function LevelDirector:AttachStoryView(view)
    if not view then
        return false
    end
    if not self.storyPlayer then
        self.storyPlayer = StoryPlayer.New(view)
    else
        self.storyPlayer:AttachView(view)
    end
    return true
end

function LevelDirector:IsStoryPlaying()
    return self.storyPlayer ~= nil and self.storyPlayer:IsPlaying()
end

function LevelDirector:IsStoryBlocking()
    return self.storyPlayer ~= nil and self.storyPlayer:IsBlocking()
end

function LevelDirector:SyncStoryInputLock()
    local preview = self:GetPreview()
    if not preview then
        return false
    end
    local shouldLock = self:IsStoryBlocking()
    if shouldLock == self.storyInputLocked then
        return true
    end
    self.storyInputLocked = shouldLock
    if preview.SetStoryBlocked then
        preview:SetStoryBlocked(shouldLock)
    elseif shouldLock then
        preview:SetInputLocked(true)
    end
    return true
end

---@param lines table
---@param options table|nil
---@return boolean
function LevelDirector:PlayStory(lines, options)
    if not self.running then
        self.pendingStory = { lines = lines, options = options }
        print("LevelDirector: story queued until run")
        return true
    end
    if not self.storyPlayer then
        print("LevelDirector: PlayStory ignored, no story view")
        if options and type(options.onComplete) == "function" then
            options.onComplete()
        end
        return false
    end
    local wrapped = options or {}
    local userComplete = wrapped.onComplete
    wrapped.onComplete = function()
        self:SyncStoryInputLock()
        if type(userComplete) == "function" then
            userComplete()
        end
    end
    local started = self.storyPlayer:Play(lines, wrapped)
    self:SyncStoryInputLock()
    return started
end

function LevelDirector:StopStory()
    if self.storyPlayer and self.storyPlayer:IsPlaying() then
        self.storyPlayer:Skip()
    end
    self:SyncStoryInputLock()
end

function LevelDirector:Halt()
    self.running = false
    self.pendingStory = nil
    self:StopStory()
end

--- 过关后由导演决定收尾剧情。默认立刻交给 GameApp。
---@param payload table|nil
function LevelDirector:OnFinish(payload)
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, payload)
    end
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
    print("LevelDirector: setup level=" .. tostring(self:GetLevelId()))
    self:OnStart()
    return true
end

function LevelDirector:BeginRun()
    if self.running then
        return true
    end
    if not self.started then
        self:Start()
    end
    self.running = true
    print("LevelDirector: run level=" .. tostring(self:GetLevelId()))
    local pending = self.pendingStory
    self.pendingStory = nil
    if pending then
        self:PlayStory(pending.lines, pending.options)
    end
    return true
end

---@param timeStep number
function LevelDirector:Update(timeStep)
    if not self.running then
        return
    end
    if self.storyPlayer then
        self.storyPlayer:Update(timeStep)
        self:SyncStoryInputLock()
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
    if self.storyPlayer then
        self.storyPlayer:Dispose()
        self.storyPlayer = nil
    end
    self.storyInputLocked = false
    self.pendingStory = nil
    self.running = false
    self.started = false
    self.session = nil
    self.definition = nil
end

return LevelDirector
