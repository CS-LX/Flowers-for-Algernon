-- 第五章第一关演出：查理带阿尔吉侬离开研究所，并在空间感知衰退中背起它同行。
-- 导演只编排剧情、自动返回与载鼠表现；旋转和 Path Graph 继续由现有运行时负责。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter5"

local Director5_1 = LevelDirector.Extend()

local ROTATOR_PART_ID = "part_part_18"
local SPAWN_NODE_KEY = "part_part_20:node_part_part_20_4"
local ROTATOR_END_KEYS = {
    ["part_part_18:rotator_end1"] = true,
    ["part_part_18:rotator_end2"] = true,
    ["part_part_18:rotator_end3"] = true,
}
local ROTATOR_FAULT = {
    stallChance = 0.20,
    slipChance = 0.25,
    slowSnapChance = 1.0 / 3.0,
    slipDelay = 0.34,
}
local ALGERNON_GROUND_SCALE = 1.05
local ALGERNON_CARRY_SCALE = 0.78
local ALGERNON_HEAD_OFFSET = Vector3(0.0, 0.68, 0.0)
local ALGERNON_JUMP_DURATION = 0.7
local ALGERNON_JUMP_HEIGHT = 0.42

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

function Director5_1:OnStart()
    self.stage = "intro"
    self.carrySequenceStarted = false
    self.algernonCarried = false
    self.jumpElapsed = 0.0
    self.finishStoryPlayed = false
    self.finishPayload = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:SetRotatorFault(ROTATOR_PART_ID, ROTATOR_FAULT)

    local enabled, enableError = self:SetAlgernonEnabled(true, SPAWN_NODE_KEY)
    if not enabled then
        print("Director5_1: algernon enable failed " .. tostring(enableError))
    else
        self:SetAlgernonVisible(true)
        self:SetAlgernonLocalTransform({ scale = ALGERNON_GROUND_SCALE })
        print("Director5_1: Charlie and Algernon left the laboratory")
    end

    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch5_1_intro, {
        onComplete = function()
            self.stage = "await_rotator_end"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director5_1: waiting for Charlie to discover the moving path")
        end,
    })
end

function Director5_1:OnPlayerArrived(nodeKey)
    if self.stage == "await_rotator_end" and ROTATOR_END_KEYS[nodeKey] then
        self:BeginCarrySequence(nodeKey)
        return
    end
    if self.stage == "returning_for_algernon" and nodeKey == SPAWN_NODE_KEY then
        self:BeginAlgernonJump()
    end
end

function Director5_1:BeginCarrySequence(nodeKey)
    if self.carrySequenceStarted then
        return
    end
    self.carrySequenceStarted = true
    self.stage = "carry_story"
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch5_1_discover, {
        onComplete = function()
            self:ReturnForAlgernon()
        end,
    })
    print("Director5_1: moving path discovered at " .. tostring(nodeKey))
end

function Director5_1:ReturnForAlgernon()
    self.stage = "returning_for_algernon"
    self:SetInputLocked(true)
    self:SetPlayerLocked(false)
    local moved, moveError = self:MovePlayerTo(SPAWN_NODE_KEY)
    if not moved then
        print("Director5_1: return path failed " .. tostring(moveError))
        self:SetPlayerLocked(true)
        return
    end
    print("Director5_1: Charlie returning for Algernon")
end

function Director5_1:BeginAlgernonJump()
    if self.algernonCarried or self.stage ~= "returning_for_algernon" then
        return
    end
    self.stage = "algernon_jump"
    self.jumpElapsed = 0.0
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    self:StopAlgernon()
    self:SetAlgernonLocalTransform({
        position = { x = 0.0, y = 0.0, z = 0.0 },
        scale = ALGERNON_GROUND_SCALE,
    })
    print("Director5_1: Algernon jump begins")
end

function Director5_1:UpdateAlgernonJump(timeStep)
    self.jumpElapsed = self.jumpElapsed + timeStep
    local progress = Clamp01(self.jumpElapsed / ALGERNON_JUMP_DURATION)
    local arc = math.sin(progress * math.pi) * ALGERNON_JUMP_HEIGHT
    local carryY = ALGERNON_HEAD_OFFSET.y * progress + arc
    local scale = ALGERNON_GROUND_SCALE
        + (ALGERNON_CARRY_SCALE - ALGERNON_GROUND_SCALE) * progress
    self:SetAlgernonLocalTransform({
        position = { x = 0.0, y = carryY, z = 0.0 },
        scale = scale,
    })
    if progress >= 1.0 then
        self:FinishAlgernonJump()
    end
end

function Director5_1:FinishAlgernonJump()
    if self.algernonCarried then
        return
    end
    self.algernonCarried = true
    self:SetAlgernonLocalTransform({
        position = { x = 0.0, y = 0.0, z = 0.0 },
        scale = ALGERNON_CARRY_SCALE,
    })
    self:SetAlgernonCarried(true, ALGERNON_HEAD_OFFSET)
    self.stage = "carry_story"
    self:PlayStory(Story.ch5_1_carry, {
        onComplete = function()
            self.stage = "playable_with_algernon"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            print("Director5_1: Algernon now travels on Charlie")
        end,
    })
end

function Director5_1:OnFinish(payload)
    if self.finishStoryPlayed then
        return
    end
    self.finishStoryPlayed = true
    self.finishPayload = payload
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:PlayStory(Story.ch5_1_finish, {
        onComplete = function()
            local session = self.session
            if session and session.onFinish then
                session.onFinish(session, self.finishPayload)
            end
        end,
    })
end

function Director5_1:OnUpdate(timeStep)
    if self.stage == "algernon_jump" then
        self:UpdateAlgernonJump(timeStep)
        return
    end
    if self.stage == "await_rotator_end" then
        local player = self:GetPlayer()
        local nodeKey = player and player:GetCurrentNodeKey() or nil
        if nodeKey and ROTATOR_END_KEYS[nodeKey] then
            self:BeginCarrySequence(nodeKey)
        end
    end
end

function Director5_1:OnDispose()
    self:SetAlgernonCarried(false)
    self:StopAlgernon()
    self:SetAlgernonVisible(false)
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director5_1
