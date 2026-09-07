-- 第四章第一关演出：查理乘 Lift 回到空实验室，并听见隔壁的异常测试。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter4"

local Director4_1 = LevelDirector.Extend()

local LIFT_PART_ID = "part_mainpart_1_2"
local ROTATOR_PART_ID = "part_mainpart_1_3"
local LIFT_OFFSET = 4.0
local LIFT_DURATION = 4.0
local ROTATOR_FAULT = {
    stallChance = 0.04,
    slipChance = 0.08,
    slowSnapChance = 0.12,
    slipDelay = 0.65,
}

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function EaseOutQuad(t)
    t = Clamp01(t)
    local remaining = 1.0 - t
    return 1.0 - remaining * remaining
end

function Director4_1:OnStart()
    self.stage = "lift_entry"
    self.liftElapsed = 0.0
    self.liftFinished = false
    self.afterLiftStoryPlayed = false
    self.pathStoryPending = false
    self.pathStoryElapsed = 0.0
    self.pathStoryPlayed = false
    self.finishStoryPlayed = false
    self.liftStartPosition = { x = 0.0, y = 0.0, z = 0.0 }

    local liftPart = self:GetPart(LIFT_PART_ID)
    if not liftPart then
        print("Director4_1: LiftPart missing")
        return
    end
    local position = liftPart.transform.position
    self.liftStartPosition.x = position.x
    self.liftStartPosition.y = position.y
    self.liftStartPosition.z = position.z

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:SetRotatorFault(ROTATOR_PART_ID, ROTATOR_FAULT)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end
    self:SetPartVisualPosition(LIFT_PART_ID, {
        x = self.liftStartPosition.x,
        y = self.liftStartPosition.y + LIFT_OFFSET,
        z = self.liftStartPosition.z,
    })
    print(string.format(
        "Director4_1: entry Lift starts above authored position y=%.3f",
        self.liftStartPosition.y + LIFT_OFFSET
    ))
end

function Director4_1:ShouldRunDuringFogReveal()
    return true
end

function Director4_1:OnPlayerStarted(targetKey)
    if self.stage ~= "playable" or self.pathStoryPlayed or self.pathStoryPending then
        return
    end
    self.pathStoryPending = true
    self.pathStoryElapsed = 0.0
    print("Director4_1: Charlie started walking, report pending target=" .. tostring(targetKey))
end

function Director4_1:PlayPathStory()
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPending = false
    self.pathStoryPlayed = true
    self:PlayStory(Story.ch4_1_path_observation)
    print("Director4_1: distant researcher report started")
end

function Director4_1:FinishLiftEntry()
    if self.liftFinished then
        return
    end
    self.liftFinished = true
    self.stage = "story"
    self.liftElapsed = 0.0
    self:SetPartVisualPosition(LIFT_PART_ID, self.liftStartPosition)
    self:SetPartPosition(LIFT_PART_ID, self.liftStartPosition, false)
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    if self.afterLiftStoryPlayed then
        return
    end
    self.afterLiftStoryPlayed = true
    self:PlayStory(Story.ch4_1_after_lift, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director4_1: entry Lift settled, empty laboratory story complete")
        end,
    })
end

function Director4_1:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.pathStoryPending = false
    self.pathStoryPlayed = true
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    self:PlayStory(Story.ch4_1_finish, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director4_1:OnUpdate(timeStep)
    if self.stage == "lift_entry" then
        self.liftElapsed = self.liftElapsed + timeStep
        local progress = Clamp01(self.liftElapsed / LIFT_DURATION)
        local movementMix = EaseOutQuad(progress)
        local dropOffset = LIFT_OFFSET * movementMix
        self:SetPartVisualPosition(LIFT_PART_ID, {
            x = self.liftStartPosition.x,
            y = self.liftStartPosition.y + LIFT_OFFSET - dropOffset,
            z = self.liftStartPosition.z,
        })
        if progress >= 1.0 then
            self:FinishLiftEntry()
        end
        return
    end

    if self.stage ~= "playable" or not self.pathStoryPending or self.pathStoryPlayed then
        return
    end
    if self:IsStoryPlaying() then
        return
    end
    self.pathStoryElapsed = self.pathStoryElapsed + timeStep
    if self.pathStoryElapsed >= 1.0 then
        self:PlayPathStory()
    end
end

function Director4_1:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director4_1
