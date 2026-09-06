-- 第三章第二关：城市仍然清晰，但查理确认这里不只是没有人，连城市活动也无法被观测。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter3"

local Director3_2 = LevelDirector.Extend()

function Director3_2:OnStart()
    self.pathStoryPlayed = false
    self.finishStoryPlayed = false
    self:SetInputLocked(false)
    self:SetPlayerLocked(false)

    local player = self:GetPlayer()
    if player and player.SetOnStarted then
        player:SetOnStarted(function(targetKey)
            self:OnPlayerStarted(targetKey)
        end)
    end
    print("Director3_2: empty district ready")
end

function Director3_2:OnPlayerStarted(targetKey)
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPlayed = true
    self:PlayStory(Story.ch3_2_path)
    print("Director3_2: Charlie started observing city activity target=" .. tostring(targetKey))
end

function Director3_2:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch3_2_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director3_2:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director3_2
