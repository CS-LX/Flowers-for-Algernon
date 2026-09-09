-- 第三章第一关：城市仍在，但查理第一次注意到世俗世界无法进入自己的空间观测。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter3"

local Director3_1 = LevelDirector.Extend()

local PLATFORM_HINT_KEYS = {
    ["part_part_9:node_part_part_9_4"] = true,
    ["part_part_9:node_part_part_9_5"] = true,
    ["part_part_9:node_part_part_9_6"] = true,
}

function Director3_1:OnStart()
    self.pathStoryPlayed = false
    self.platformStoryPlayed = false
    self.platformStoryPending = false
    self.finishStoryPlayed = false
    self:SetInputLocked(false)
    self:SetPlayerLocked(false)

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
    print("Director3_1: city entrance ready")
end

function Director3_1:OnPlayerStarted(targetKey)
    if self.pathStoryPlayed then
        return
    end
    self.pathStoryPlayed = true
    self:PlayStory(Story.ch3_1_path)
    print("Director3_1: Charlie started observing the city target=" .. tostring(targetKey))
end

function Director3_1:TryPlayPlatformStory()
    if self.platformStoryPlayed or not self.platformStoryPending then
        return
    end
    if self:IsStoryPlaying() then
        return
    end
    self.platformStoryPlayed = true
    self.platformStoryPending = false
    self:PlayStory(Story.ch3_1_platform)
    print("Director3_1: Charlie noticed the green platform")
end

function Director3_1:OnPlayerArrived(nodeKey)
    if self.platformStoryPlayed or self.platformStoryPending then
        return
    end
    if not PLATFORM_HINT_KEYS[nodeKey] then
        return
    end
    self.platformStoryPending = true
    print("Director3_1: green platform hint armed at " .. tostring(nodeKey))
    self:TryPlayPlatformStory()
end

function Director3_1:OnUpdate(timeStep)
    self:TryPlayPlatformStory()
end

function Director3_1:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch3_1_clear, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, payload)
            end
        end,
    })
end

function Director3_1:OnDispose()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director3_1
