-- 第一章第三关演出：研究员第一次让查理看到道路可以改变。
-- 只服务 1-3（id = ch1_3）。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter1"

local Director1_3 = LevelDirector.Extend()

local ROTATOR_PART_ID = "part_part_18"
local ROTATOR_START_YAW = 0
local ROTATOR_END_YAW = 2
local ROTATOR_TRIGGER_KEY = "part_part_18:jump_node"
local ROTATOR_END_KEY = "part_part_18:rotator_end1"
local ROTATE_DURATION = 5.0
local RESTORE_DURATION = 5.0
local AFTER_ROTATE_BANNER_DELAY = 0.8

local function QuadInOut(t)
    if t < 0.5 then
        return 2.0 * t * t
    end
    local p = 1.0 - t
    return 1.0 - 2.0 * p * p
end

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

function Director1_3:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.finishStoryPlayed = false
    self.rotatorStartPosition = { x = 0.0, y = 0.0, z = 0.0 }
    self.rotatorStartYaw = ROTATOR_START_YAW
    self.rotatorEndYaw = ROTATOR_END_YAW
    self.rotationTweenState = nil
    self.rotationElapsed = 0.0
    self.rotationTween = nil
    self.restoreTweenState = nil
    self.restoreElapsed = 0.0
    self.restoreTween = nil

    local part = self:GetPart(ROTATOR_PART_ID)
    if not part then
        print("Director1_3: rotator part missing")
        return
    end
    self.rotatorStartYaw = part.transform.rotation.yawSteps
    self.rotatorStartPosition.x = part.transform.position.x
    self.rotatorStartPosition.y = part.transform.position.y
    self.rotatorStartPosition.z = part.transform.position.z

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch1_3_intro, {
        onComplete = function()
            self.stage = "await_cliff"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director1_3: waiting for player at " .. ROTATOR_TRIGGER_KEY)
        end,
    })
end

function Director1_3:OnPlayerArrived(nodeKey)
    if self.stage == "await_cliff" and nodeKey == ROTATOR_TRIGGER_KEY then
        self:BeginRotation()
    elseif self.stage == "await_rotator_end" and nodeKey == ROTATOR_END_KEY then
        self:OnPlayerAtRotatorEnd()
    end
end

function Director1_3:BeginRotation()
    if self.stage ~= "await_cliff" then
        return
    end
    self.stage = "halt_for_rotate"
    self.stageElapsed = 0.0
    self:SetInputLocked(true)
    print("Director1_3: player reached cliff, waiting to settle before rotate")
    self:SetPlayerLocked(true, function()
        self:StartRotation()
    end)
end

function Director1_3:StartRotation()
    if self.stage ~= "halt_for_rotate" then
        return
    end
    self.stage = "rotate"
    self.stageElapsed = 0.0
    self.rotationTweenState = { yaw = self.rotatorStartYaw }
    self.rotationElapsed = 0.0
    self.rotationTween = true
    self:SetPartVisualYaw(ROTATOR_PART_ID, self.rotatorStartYaw * 60.0)
    self:PlayStory(Story.ch1_3_rotate)
    print("Director1_3: settled, rotating Part to yawSteps=" .. tostring(self.rotatorEndYaw))
end

function Director1_3:FinishRotation()
    self.rotationTween = nil
    self.rotationTweenState = nil
    self:SetPartYawSteps(ROTATOR_PART_ID, self.rotatorEndYaw, true)
    self.stage = "after_rotate_delay"
    self.stageElapsed = 0.0
end

function Director1_3:StartAfterRotate()
    self.stage = "after_rotate"
    self.stageElapsed = 0.0
    self:PlayStory(Story.ch1_3_after_rotate, {
        onComplete = function()
            self.stage = "await_rotator_end"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director1_3: waiting for player at " .. ROTATOR_END_KEY)
        end,
    })
end

function Director1_3:OnPlayerAtRotatorEnd()
    if self.stage ~= "await_rotator_end" then
        return
    end
    self.stage = "halt_for_restore"
    self.stageElapsed = 0.0
    self:SetInputLocked(true)
    print("Director1_3: player reached rotator end, waiting to settle before restore")
    self:SetPlayerLocked(true, function()
        self:StartRestore()
    end)
end

function Director1_3:StartRestore()
    if self.stage ~= "halt_for_restore" then
        return
    end
    self.stage = "restore"
    self.stageElapsed = 0.0
    self.restoreTweenState = { yaw = self.rotatorEndYaw }
    self.restoreElapsed = 0.0
    self.restoreTween = true
    print("Director1_3: settled, restoring Part")
end

function Director1_3:FinishRestore()
    self.restoreTween = nil
    self.restoreTweenState = nil
    self:SetPartYawSteps(ROTATOR_PART_ID, self.rotatorStartYaw, true)
    self.stage = "restore_complete"
    self.stageElapsed = 0.0
    self:SetPlayerLocked(false)
    self:SetInputLocked(false)
end

function Director1_3:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep

    if self.stage == "await_cliff" then
        local player = self:GetPlayer()
        if player and player:GetCurrentNodeKey() == ROTATOR_TRIGGER_KEY then
            self:OnPlayerArrived(ROTATOR_TRIGGER_KEY)
        end
        return
    end

    if self.stage == "rotate" and self.rotationTween and self.rotationTweenState then
        self.rotationElapsed = self.rotationElapsed + timeStep
        local progress = Clamp01(self.rotationElapsed / ROTATE_DURATION)
        self.rotationTweenState.yaw = self.rotatorStartYaw
            + (self.rotatorEndYaw - self.rotatorStartYaw) * QuadInOut(progress)
        self:SetPartVisualYaw(ROTATOR_PART_ID, self.rotationTweenState.yaw * 60.0)
        if progress >= 1.0 then
            self:FinishRotation()
        end
        return
    end

    if self.stage == "after_rotate_delay" and self.stageElapsed >= AFTER_ROTATE_BANNER_DELAY then
        self:StartAfterRotate()
        return
    end

    if self.stage == "await_rotator_end" then
        local player = self:GetPlayer()
        if player and player:GetCurrentNodeKey() == ROTATOR_END_KEY then
            self:OnPlayerArrived(ROTATOR_END_KEY)
        end
        return
    end

    if self.stage == "restore" and self.restoreTween and self.restoreTweenState then
        self.restoreElapsed = self.restoreElapsed + timeStep
        local progress = Clamp01(self.restoreElapsed / RESTORE_DURATION)
        self.restoreTweenState.yaw = self.rotatorEndYaw
            + (self.rotatorStartYaw - self.rotatorEndYaw) * QuadInOut(progress)
        self:SetPartVisualYaw(ROTATOR_PART_ID, self.restoreTweenState.yaw * 60.0)
        if progress >= 1.0 then
            self:FinishRestore()
        end
    end
end

function Director1_3:OnFinish(payload)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:PlayStory(Story.ch1_3_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director1_3:OnDispose()
    self.rotationTween = nil
    self.rotationTweenState = nil
    self.restoreTween = nil
    self.restoreTweenState = nil
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director1_3
