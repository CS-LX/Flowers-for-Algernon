-- 第一章演出：地图从下方升起，升起完成后播放开场对话。
-- 只服务 1-1（id = ch1_1）。Part 先落到配置高度减 2 米，再 2 秒 QuadInOut 抬回配置位置。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter1"

local Chapter1 = LevelDirector.Extend()

local LIFT_DURATION = 2.0
local LIFT_OFFSET = 2.0
local PATH_STORY_DELAY = 5.0

-- 慢-快-慢。自研公式，未接入缓动库。
local function QuadInOut(t)
    if t < 0.5 then
        return 2.0 * t * t
    end
    local p = 1.0 - t
    return 1.0 - 2.0 * p * p
end

function Chapter1:OnStart()
    self.liftElapsed = 0.0
    self.lifting = false
    self.partId = nil
    self.authoredY = 0.0
    self.authoredX = 0.0
    self.authoredZ = 0.0
    self.elapsed = 0.0
    self.inLevelStoryPlayed = false
    self.pathStoryPending = false
    self.pathStoryElapsed = 0.0
    self.finishStoryPlayed = false

    local document = self:GetDocument()
    if not document then
        print("Chapter1: no document")
        return
    end
    local parts = document:GetParts()
    local part = parts[1]
    if not part then
        print("Chapter1: no part to lift")
        return
    end
    self.partId = part.id
    local position = part.transform.position
    self.authoredX = position.x
    self.authoredY = position.y
    self.authoredZ = position.z

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self.pathStoryPending = true
            self.pathStoryElapsed = 0.0
            print("Chapter1: player path started target=" .. tostring(targetKey))
        end)
    end

    self:BeginLift()
end

function Chapter1:BeginLift()
    if not self.partId then
        return
    end
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local dropped, dropError = self:SetPartPosition(self.partId, {
        x = self.authoredX,
        y = self.authoredY - LIFT_OFFSET,
        z = self.authoredZ,
    }, false)
    if not dropped then
        print("Chapter1: drop rejected " .. tostring(dropError))
        self:SetPlayerLocked(false)
        self:SetInputLocked(false)
        return
    end
    self.liftElapsed = 0.0
    self.lifting = true
    print(string.format(
        "Chapter1: lift start part=%s from y=%.3f to y=%.3f",
        self.partId,
        self.authoredY - LIFT_OFFSET,
        self.authoredY
    ))
end

function Chapter1:OnUpdate(timeStep)
    self.elapsed = (self.elapsed or 0.0) + timeStep
    if self.pathStoryPending and not self.inLevelStoryPlayed then
        self.pathStoryElapsed = self.pathStoryElapsed + timeStep
        if self.pathStoryElapsed >= PATH_STORY_DELAY and not self:IsStoryPlaying() then
            self.pathStoryPending = false
            self.inLevelStoryPlayed = true
            print("Chapter1: start delayed in-level story")
            self:PlayStory(Story.inLevel)
        end
    end
    if not self.lifting or not self.partId then
        return
    end
    self.liftElapsed = self.liftElapsed + timeStep
    local t = math.min(1.0, self.liftElapsed / LIFT_DURATION)
    -- 进度经 QuadInOut：先慢、中段快、再慢。
    local y = self.authoredY - LIFT_OFFSET + LIFT_OFFSET * QuadInOut(t)
    self:SetPartPosition(self.partId, {
        x = self.authoredX,
        y = y,
        z = self.authoredZ,
    }, false)
    if t >= 1.0 then
        self:FinishLift()
    end
end

function Chapter1:FinishLift()
    if not self.lifting then
        return
    end
    self.lifting = false
    self:SetPartPosition(self.partId, {
        x = self.authoredX,
        y = self.authoredY,
        z = self.authoredZ,
    }, true)
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    print(string.format(
        "Chapter1: lift done part=%s y=%.3f",
        tostring(self.partId),
        self.authoredY
    ))
    self:PlayStory(Story.intro, {
        onComplete = function()
            self.inLevelStoryPlayed = false
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
        end,
    })
end

function Chapter1:OnFinish(payload)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:PlayStory(Story.clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Chapter1:OnDispose()
    if self.lifting then
        self:FinishLift()
    end
end

return Chapter1
