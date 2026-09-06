-- 第三章第四关：查理依靠自己的空间理解接通通往研究所的道路，随 Lift 下降回到实验室。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter3"

local Director3_4 = LevelDirector.Extend()

local LIFT_PART_ID = "part_part_1_4"
local LIFT_FINISH_KEYS = {
    ["part_part_1_4:node_part_part_1_4_1"] = true,
    ["part_part_1_4:node_part_part_1_4_2"] = true,
    ["part_part_1_4:node_part_part_1_4_3"] = true,
    ["part_part_1_4:node_part_part_1_4_4"] = true,
    ["part_part_1_4:node_part_part_1_4_5"] = true,
    ["part_part_1_4:node_part_part_1_4_6"] = true,
}
local LIFT_DROP_HEIGHT = 4.0
local LIFT_DURATION = 4.0

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function CubicInOut(t)
    t = Clamp01(t)
    if t < 0.5 then
        return 4.0 * t * t * t
    end
    local p = -2.0 * t + 2.0
    return 1.0 - p * p * p * 0.5
end

function Director3_4:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.finishStoryPlayed = false
    self.narrativeFinished = false
    self.finishPayload = nil
    self.pathBannerPlayed = false
    self.pathBannerPlaying = false
    self.liftStoryPlayed = false
    self.liftStoryPending = false
    self.liftElapsed = 0.0
    self.liftStartPosition = { x = 0.0, y = 0.0, z = 0.0 }

    local liftPart = self:GetPart(LIFT_PART_ID)
    if not liftPart then
        print("Director3_4: LiftPart missing")
        return
    end
    self.liftStartPosition.x = liftPart.transform.position.x
    self.liftStartPosition.y = liftPart.transform.position.y
    self.liftStartPosition.z = liftPart.transform.position.z

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch3_4_intro, {
        onComplete = function()
            self.stage = "playable"
            self.stageElapsed = 0.0
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director3_4: Charlie is returning to the research institute")
        end,
    })
end

function Director3_4:OnPlayerStarted(targetKey)
    if self.stage ~= "playable" or self.pathBannerPlayed then
        return
    end
    local preview = self:GetPreview()
    local record = preview and preview.pathRuntime and preview.pathRuntime:GetNode(targetKey) or nil
    if not record or record.partId ~= LIFT_PART_ID then
        return
    end
    self.pathBannerPlayed = true
    self.pathBannerPlaying = true
    self:PlayStory(Story.ch3_4_path, {
        onComplete = function()
            self.pathBannerPlaying = false
            if self.liftStoryPending then
                self:PlayLiftStory()
            end
        end,
    })
    print("Director3_4: connected path toward Lift target=" .. tostring(targetKey))
end

function Director3_4:OnPlayerArrived(nodeKey)
    if self.stage ~= "playable" or self.finishStoryPlayed then
        return
    end
    if not LIFT_FINISH_KEYS[nodeKey] then
        return
    end
    print("Director3_4: settled on research institute Lift node " .. tostring(nodeKey))
    self:FinishLevel()
end

function Director3_4:PlayLiftStory()
    if self.liftStoryPlayed then
        return
    end
    self.liftStoryPending = false
    self.liftStoryPlayed = true
    self:PlayStory(Story.ch3_4_lift_begin)
end

function Director3_4:BeginLift(payload)
    if self.stage == "lift" or self.narrativeFinished then
        return
    end
    self.finishPayload = payload
    self.stage = "lift"
    self.stageElapsed = 0.0
    self.liftElapsed = 0.0
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local player = self:GetPlayer()
    if player and player.ClearTopmostHold then
        player:ClearTopmostHold()
    end
    if self.pathBannerPlaying then
        self.liftStoryPending = true
    else
        self:PlayLiftStory()
    end
    print(string.format(
        "Director3_4: Lift transition begin drop=%.1f duration=%.1f",
        LIFT_DROP_HEIGHT,
        LIFT_DURATION
    ))
end

function Director3_4:FinishLift()
    local endPosition = {
        x = self.liftStartPosition.x,
        y = self.liftStartPosition.y - LIFT_DROP_HEIGHT,
        z = self.liftStartPosition.z,
    }
    self:SetPartVisualPosition(LIFT_PART_ID, endPosition)
    self:SetPartPosition(LIFT_PART_ID, endPosition, false)
    local player = self:GetPlayer()
    if player and player.ClearTopmostHold then
        player:ClearTopmostHold()
    end
    self.stage = "complete"
    self.stageElapsed = 0.0
    self:FinishNarrative()
    print("Director3_4: Lift reached the research institute")
end

function Director3_4:FinishNarrative()
    if self.narrativeFinished then
        return
    end
    self.narrativeFinished = true
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, self.finishPayload)
    end
end

function Director3_4:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:BeginLift(payload)
end

function Director3_4:OnUpdate(timeStep)
    self.stageElapsed = self.stageElapsed + timeStep
    if self.stage ~= "lift" then
        return
    end

    self.liftElapsed = self.liftElapsed + timeStep
    local progress = Clamp01(self.liftElapsed / LIFT_DURATION)
    local movementMix = CubicInOut(progress)
    local dropOffset = LIFT_DROP_HEIGHT * movementMix
    self:SetPartVisualPosition(LIFT_PART_ID, {
        x = self.liftStartPosition.x,
        y = self.liftStartPosition.y - dropOffset,
        z = self.liftStartPosition.z,
    })

    if progress >= 1.0 then
        self:FinishLift()
    end
end

function Director3_4:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director3_4
