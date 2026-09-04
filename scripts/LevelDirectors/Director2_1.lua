-- 第二章第一关演出：手术后，查理第一次看见一条不可能的路径。
-- 关卡只服务 ch2_1；正常玩家寻路仍消费当前有效 Path Graph。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter2"

local Director2_1 = LevelDirector.Extend()

local PART_ID = "part_part"
local FINISH_NODE_KEY = "part_part:finish_node"
local ROTATE_DURATION = 10.0
local ROTATE_DEGREES = 360.0
local ALGERNON_EXIT_DURATION = 1.0

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function QuadInOut(t)
    if t < 0.5 then
        return 2.0 * t * t
    end
    local p = 1.0 - t
    return 1.0 - 2.0 * p * p
end

function Director2_1:OnStart()
    self.stage = "surgery"
    self.stageElapsed = 0.0
    self.finishStoryPlayed = false
    self.narrativeFinished = false
    self.finishPayload = nil
    self.algernonExitElapsed = 0.0
    self.rotationElapsed = 0.0
    self.rotationBaseYaw = 0.0
    self.rotationBaseSteps = 0

    local part = self:GetPart(PART_ID)
    if not part then
        print("Director2_1: MainPart missing")
        return
    end
    self.rotationBaseSteps = part.transform.rotation.yawSteps
    self.rotationBaseYaw = self.rotationBaseSteps * 60.0

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:SetAlgernonOnArrived(function(nodeKey)
        self:OnAlgernonArrived(nodeKey)
    end)

    self:PlayStory(Story.surgery, {
        onComplete = function()
            self:StartAlgernon()
        end,
    })
end

function Director2_1:StartAlgernon()
    local player = self:GetPlayer()
    local playerNodeKey = player and player:GetCurrentNodeKey() or nil
    if not playerNodeKey then
        print("Director2_1: player position missing")
        return
    end
    local enabled, enableError = self:SetAlgernonEnabled(true, playerNodeKey)
    if not enabled then
        print("Director2_1: algernon enable failed " .. tostring(enableError))
        return
    end
    self:SetAlgernonVisible(true)
    self:SetAlgernonLocalTransform({ scale = 1.05 })
    self.stage = "algernon_motion"
    self.stageElapsed = 0.0
    local moved, errorMessage = self:MoveAlgernonToIncludingCandidates(FINISH_NODE_KEY)
    if not moved then
        print("Director2_1: algernon move failed " .. tostring(errorMessage))
        return
    end
    print("Director2_1: algernon moving to " .. FINISH_NODE_KEY)
end

function Director2_1:OnAlgernonArrived(nodeKey)
    if self.stage ~= "algernon_motion" then
        return
    end
    self.stage = "algernon_exit"
    self.stageElapsed = 0.0
    self.algernonExitElapsed = 0.0
    print("Director2_1: algernon reached finish " .. tostring(nodeKey))
end

function Director2_1:FinishAlgernonExit()
    self:SetAlgernonVisible(false)
    self.stage = "after_mouse"
    self.stageElapsed = 0.0
    self:PlayStory(Story.after_mouse, {
        onComplete = function()
            self.stage = "await_finish"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director2_1: waiting for Charlie at " .. FINISH_NODE_KEY)
        end,
    })
end

function Director2_1:BeginFinishReveal(payload)
    if self.stage ~= "await_finish" then
        return
    end
    self.finishPayload = payload
    self.stage = "praise"
    self.stageElapsed = 0.0
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.praise, {
        onComplete = function()
            self:BeginFullRotation()
        end,
    })
end

function Director2_1:BeginFullRotation()
    self.stage = "full_rotation"
    self.stageElapsed = 0.0
    self.rotationElapsed = 0.0
    self:SetPartVisualYaw(PART_ID, self.rotationBaseYaw)
    print("Director2_1: begin 360 degree reveal")
end

function Director2_1:FinishFullRotation()
    self:SetPartVisualYaw(PART_ID, self.rotationBaseYaw)
    self:SetPartYawSteps(PART_ID, self.rotationBaseSteps, true)
    self.stage = "reveal"
    self.stageElapsed = 0.0
    self:PlayStory(Story.reveal, {
        onComplete = function()
            self:FinishNarrative()
        end,
    })
end

function Director2_1:FinishNarrative()
    if self.narrativeFinished then
        return
    end
    self.narrativeFinished = true
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director2_1:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:BeginFinishReveal(payload)
end

function Director2_1:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep

    if self.stage == "algernon_exit" then
        self.algernonExitElapsed = self.algernonExitElapsed + timeStep
        local progress = Clamp01(self.algernonExitElapsed / ALGERNON_EXIT_DURATION)
        self:SetAlgernonLocalTransform({ scale = 1.05 * (1.0 - progress) })
        if progress >= 1.0 then
            self:FinishAlgernonExit()
        end
        return
    end

    if self.stage == "full_rotation" then
        self.rotationElapsed = self.rotationElapsed + timeStep
        local progress = Clamp01(self.rotationElapsed / ROTATE_DURATION)
        local eased = QuadInOut(progress)
        self:SetPartVisualYaw(PART_ID, self.rotationBaseYaw + ROTATE_DEGREES * eased)
        if progress >= 1.0 then
            self:FinishFullRotation()
        end
    end
end

function Director2_1:OnDispose()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director2_1
