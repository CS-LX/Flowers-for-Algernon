-- 第五章第二关演出：查理只能沿实体道路前进，阿尔吉侬在途中从头顶掉落并停下。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter5"

local Director5_2 = LevelDirector.Extend()

local SPAWN_NODE_KEY = "part_part_20:node_part_part_20_15"
local DROP_TRIGGER_KEY = "part_part_20:node_part_part_20_9"
local DROP_NODE_KEY = "part_part_20:node_part_part_20_9"
local FINISH_NODE_KEYS = {
    ["part_part_20:finish_node"] = true,
    ["part_part_20:finish_node_2"] = true,
}
local ENTER_DOOR_ID = "still_enterdoor_1"
local DROP_DURATION = 0.65
local DOOR_CLOSE_DURATION = 3.0

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

-- 推拉门：open 是 DoorBone 沿轴平移，曲线按位移而不是转角。
-- 0.9s 慢启动 20%，0.9s 加快 55%，最后 1.2s 二次缓出合上剩余 25%。
local function SlowFastVerySlow(t)
    if t < 0.30 then
        local u = t / 0.30
        return 0.20 * u * u
    end
    if t < 0.60 then
        local u = (t - 0.30) / 0.30
        return 0.20 + 0.55 * u
    end
    local u = (t - 0.60) / 0.40
    local eased = 1.0 - (1.0 - u) * (1.0 - u)
    return 0.75 + 0.25 * eased
end

function Director5_2:OnStart()
    self.stage = "intro"
    self.dropStarted = false
    self.dropFinished = false
    self.finishStoryPlayed = false
    self.finishPayload = nil
    self.doorClosing = false
    self.doorCloseElapsed = 0.0
    self.enterDoorOpen = 1.0

    self:SetStillDriver(ENTER_DOOR_ID, "open", 1.0)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local enabled, enableError = self:SetAlgernonEnabled(true, SPAWN_NODE_KEY)
    if not enabled then
        print("Director5_2: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonCarried(true, Vector3(0.0, 0.68, 0.0))
        print("Director5_2: Algernon starts on Charlie")
    end

    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch5_2_intro, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director5_2: grounded path playable")
        end,
    })
end

function Director5_2:OnPlayerArrived(nodeKey)
    if self.stage == "playable" and nodeKey == DROP_TRIGGER_KEY then
        self:BeginAlgernonDrop()
    elseif self.stage == "playable_after_drop" and FINISH_NODE_KEYS[nodeKey] then
        -- finish_node or finish_node_2
        self:FinishLevel()
    end
end

function Director5_2:BeginEnterDoorClose()
    if self.doorClosing or self.enterDoorOpen <= 0.0 then
        return
    end
    self.doorClosing = true
    self.doorCloseElapsed = 0.0
    print("Director5_2: laboratory door closing behind Charlie")
end

function Director5_2:UpdateEnterDoor(timeStep)
    if self.doorClosing then
        self.doorCloseElapsed = self.doorCloseElapsed + timeStep
        local progress = Clamp01(self.doorCloseElapsed / DOOR_CLOSE_DURATION)
        self.enterDoorOpen = 1.0 - SlowFastVerySlow(progress)
        self:SetStillDriver(ENTER_DOOR_ID, "open", self.enterDoorOpen)
        if progress >= 1.0 then
            self.doorClosing = false
            self.enterDoorOpen = 0.0
            self:SetStillDriver(ENTER_DOOR_ID, "open", 0.0)
            print("Director5_2: laboratory door closed")
        end
        return
    end
    if self.enterDoorOpen <= 0.0 then
        return
    end
    if self.stage ~= "playable" then
        return
    end
    local player = self:GetPlayer()
    if player and player.IsWalking and player:IsWalking() then
        self:BeginEnterDoorClose()
    end
end

function Director5_2:BeginAlgernonDrop()
    if self.dropStarted then
        return
    end
    self.dropStarted = true
    self.stage = "dropping"
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local dropped = self:DropAlgernonAt(DROP_NODE_KEY, DROP_DURATION)
    if not dropped then
        self.stage = "playable"
        self.dropStarted = false
        self:SetPlayerLocked(false)
        self:SetInputLocked(false)
        print("Director5_2: Algernon drop could not start")
        return
    end
    print("Director5_2: Algernon is falling to the path")
end

function Director5_2:PlayLossStory()
    self.stage = "loss_story"
    self:PlayStory(Story.ch5_2_loss, {
        onComplete = function()
            self.stage = "playable_after_drop"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director5_2: Algernon remains on the path")
        end,
    })
end

function Director5_2:OnUpdate(timeStep)
    self:UpdateEnterDoor(timeStep)
    if self.stage == "dropping" then
        local preview = self:GetPreview()
        local drop = preview and preview.algernonDrop or nil
        if not drop then
            self.dropFinished = true
            self:PlayLossStory()
        end
        return
    end
    if self.stage == "playable" then
        local player = self:GetPlayer()
        if player and player:GetCurrentNodeKey() == DROP_TRIGGER_KEY then
            self:BeginAlgernonDrop()
        end
    end
end

function Director5_2:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director5_2:OnDispose()
    self:SetAlgernonCarried(false)
    self:StopAlgernon()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director5_2
