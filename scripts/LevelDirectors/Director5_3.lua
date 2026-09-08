-- 第五章第三关演出：查理沿着逐段显现的真实道路，把花送到阿尔吉侬墓前。

local LevelDirector = require "LevelDirector"
local Story = require "Story.Chapter5"
local LookApplier = require "LookApplier"

local Director5_3 = LevelDirector.Extend()

local STATIC_PATH_PARTS = {
    "part_staticpath_1_1",
    "part_staticpath_2_1",
    "part_staticpath_3_1",
    "part_staticpath_4_1",
    "part_staticpath_5_1",
    "part_staticpath_6_1",
    "part_staticpath_7_1",
}
local PATH_NODE_KEYS = {
    ["part_staticpath_1_1:node_part_staticpath_1_1_1"] = 1,
    ["part_staticpath_2_1:node_part_staticpath_2_1_1"] = 2,
    ["part_staticpath_3_1:node_part_staticpath_3_1_1"] = 3,
    ["part_staticpath_4_1:node_part_staticpath_4_1_1"] = 4,
    ["part_staticpath_5_1:node_part_staticpath_5_1_1"] = 5,
    ["part_staticpath_6_1:node_part_staticpath_6_1_1"] = 6,
    ["part_staticpath_7_1:node_part_staticpath_7_1_1"] = 7,
}
local TOMB_PART_ID = "part_staticpath_8_1"
local TOMB_OBJECT_ID = "still_part"
local FLOWER_MODEL_ID = "flower"
local PATH_RISE_HEIGHT = 0.0
local TOMB_RISE_HEIGHT = 0.0
local PATH_RISE_DURATION = 0.85
local TOMB_RISE_DURATION = 1.15
local FOCUS_DELAY = 1.0
local FOCUS_DURATION = 2.2
local FLOWER_DROP_DURATION = 0.9
local FLOWER_OFFSET = Vector3(0.0, 0.68, 0.0)
local FLOWER_SCALE = 0.28
local FOCUS_ORTHO_SIZE = 8.0

local DARK_NEG = Color(0.0, 0.0, 0.0, 1.0)
local DARK_MID = Color(0.0, 0.0, 0.0, 1.0)
local DARK_POS = Color(0.0, 0.0, 0.0, 1.0)

local function ColorToHex(color)
    return string.format(
        "#%02X%02X%02X",
        math.floor(color.r * 255.0 + 0.5),
        math.floor(color.g * 255.0 + 0.5),
        math.floor(color.b * 255.0 + 0.5)
    )
end

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

local function EaseOutCubic(value)
    local inverse = 1.0 - Clamp01(value)
    return 1.0 - inverse * inverse * inverse
end

function Director5_3:OnStart()
    self.stage = "intro"
    self.stageElapsed = 0.0
    self.nextPathIndex = 1
    self.pathRiseElapsed = 0.0
    self.tombRiseElapsed = 0.0
    self.focusElapsed = 0.0
    self.flowerDropped = false
    self.finishStarted = false
    self.originalPartPositions = {}
    self.originalPartLooks = {}
    self.originalGraveLook = nil
    self.focusStartTarget = nil
    self.focusStartSize = nil

    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:CaptureAndDarkenLevel()
    self:RefreshPathRuntime()
    self:SetCarriedStillObject(FLOWER_MODEL_ID, FLOWER_OFFSET, FLOWER_SCALE)

    local player = self:GetPlayer()
    if player and player.AddOnArrived then
        player:AddOnArrived(function(nodeKey)
            self:OnPlayerArrived(nodeKey)
        end)
    end

    self:PlayStory(Story.ch5_3_intro, {
        onComplete = function()
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
            self:RaisePathPart(1)
            print("Director5_3: true path memorial journey started")
        end,
    })
end

function Director5_3:CaptureAndDarkenLevel()
    for index, partId in ipairs(STATIC_PATH_PARTS) do
        local part = self:GetPart(partId)
        if part then
            local position = part.transform.position
            self.originalPartPositions[partId] = {
                x = position.x,
                y = position.y,
                z = position.z,
            }
            self.originalPartLooks[partId] = {
                colorNeg = LookApplier.HexToColor(part.look.colorNeg, DARK_NEG),
                colorMid = LookApplier.HexToColor(part.look.colorMid, DARK_MID),
                colorPos = LookApplier.HexToColor(part.look.colorPos, DARK_POS),
                fogColor = LookApplier.HexToColor(part.look.fogColor, DARK_NEG),
            }
            if index <= #STATIC_PATH_PARTS then
                self:SetPartVisualPosition(partId, {
                    x = position.x,
                    y = -1.0,
                    z = position.z,
                })
                self:SetPartLookColors(partId, DARK_NEG, DARK_MID, DARK_POS, DARK_NEG)
                self:SetPartPosition(partId, {
                    x = position.x,
                    y = -1.0,
                    z = position.z,
                }, false)
            end
        end
    end

    local tomb = self:GetPart(TOMB_PART_ID)
    if tomb then
        local position = tomb.transform.position
        self.originalPartPositions[TOMB_PART_ID] = {
            x = position.x,
            y = position.y,
            z = position.z,
        }
        self.originalPartLooks[TOMB_PART_ID] = {
            colorNeg = LookApplier.HexToColor(tomb.look.colorNeg, DARK_NEG),
            colorMid = LookApplier.HexToColor(tomb.look.colorMid, DARK_MID),
            colorPos = LookApplier.HexToColor(tomb.look.colorPos, DARK_POS),
            fogColor = LookApplier.HexToColor(tomb.look.fogColor, DARK_NEG),
        }
        self:SetPartVisualPosition(TOMB_PART_ID, {
            x = position.x,
            y = -1.0,
            z = position.z,
        })
        self:SetPartLookColors(TOMB_PART_ID, DARK_NEG, DARK_MID, DARK_POS, DARK_NEG)
    end

    local grave = self:GetStillObject(TOMB_OBJECT_ID)
    if grave then
        local params = grave:GetActiveParams()
        self.originalGraveLook = {
            meshColor = params["slots.stone.meshColor"] or "#333333",
            colorNeg = params["slots.stone.colorNeg"] or "#342D19",
            colorMid = params["slots.stone.colorMid"] or "#A28B58",
            colorPos = params["slots.stone.colorPos"] or "#FFFFFF",
            fogColor = params["slots.stone.fogColor"] or "#000000",
        }
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.meshColor", "#000000")
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorNeg", "#000000")
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorMid", "#000000")
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorPos", "#000000")
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.fogColor", "#000000")
    end
end

function Director5_3:GetOriginalPartPosition(partId)
    local position = self.originalPartPositions[partId]
    return position or { x = 0.0, y = 0.0, z = 0.0 }
end

function Director5_3:ApplyPartRise(partId, progress)
    local original = self:GetOriginalPartPosition(partId)
    local eased = EaseOutCubic(progress)
    local startY = -1.0
    local y = startY + (PATH_RISE_HEIGHT - startY) * eased
    self:SetPartVisualPosition(partId, {
        x = original.x,
        y = y,
        z = original.z,
    })
    local look = self.originalPartLooks[partId]
    if look then
        self:SetPartLookColors(
            partId,
            LookApplier.MixColor(DARK_NEG, look.colorNeg, eased),
            LookApplier.MixColor(DARK_MID, look.colorMid, eased),
            LookApplier.MixColor(DARK_POS, look.colorPos, eased),
            LookApplier.MixColor(DARK_NEG, look.fogColor, eased)
        )
    end
end

function Director5_3:RaisePathPart(index)
    if index > #STATIC_PATH_PARTS then
        self.nextPathIndex = index
        return
    end
    self.nextPathIndex = index
    self.stage = "raising_path"
    self.pathRiseElapsed = 0.0
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    self:ApplyPartRise(STATIC_PATH_PARTS[index], 0.0)
    print("Director5_3: raising " .. STATIC_PATH_PARTS[index])
end

function Director5_3:OnPlayerArrived(nodeKey)
    local pathIndex = PATH_NODE_KEYS[nodeKey]
    if self.stage == "playable" and pathIndex then
        if pathIndex == #STATIC_PATH_PARTS then
            self:BeginTombRise()
        elseif pathIndex >= self.nextPathIndex then
            self:RaisePathPart(pathIndex + 1)
        end
    end
end

function Director5_3:BeginTombRise()
    if self.stage == "raising_tomb" or self.stage == "focus_wait"
        or self.stage == "focusing" or self.stage == "flower_drop"
        or self.stage == "complete" then
        return
    end
    self.stage = "raising_tomb"
    self.tombRiseElapsed = 0.0
    self:SetPlayerLocked(true)
    self:SetInputLocked(true)
    print("Director5_3: raising Tomb")
end

function Director5_3:ApplyTombRise(progress)
    local tombPosition = self:GetOriginalPartPosition(TOMB_PART_ID)
    local eased = EaseOutCubic(progress)
    self:SetPartVisualPosition(TOMB_PART_ID, {
        x = tombPosition.x,
        y = -1.0 + (TOMB_RISE_HEIGHT + 1.0) * eased,
        z = tombPosition.z,
    })
    local tombLook = self.originalPartLooks[TOMB_PART_ID]
    if tombLook then
        self:SetPartLookColors(
            TOMB_PART_ID,
            LookApplier.MixColor(DARK_NEG, tombLook.colorNeg, eased),
            LookApplier.MixColor(DARK_MID, tombLook.colorMid, eased),
            LookApplier.MixColor(DARK_POS, tombLook.colorPos, eased),
            LookApplier.MixColor(DARK_NEG, tombLook.fogColor, eased)
        )
    end
    local graveLook = self.originalGraveLook
    if graveLook then
        local meshColor = LookApplier.MixColor(
            DARK_MID,
            LookApplier.HexToColor(graveLook.meshColor, DARK_MID),
            eased
        )
        local colorNeg = LookApplier.MixColor(
            DARK_NEG,
            LookApplier.HexToColor(graveLook.colorNeg, DARK_NEG),
            eased
        )
        local colorMid = LookApplier.MixColor(
            DARK_MID,
            LookApplier.HexToColor(graveLook.colorMid, DARK_MID),
            eased
        )
        local colorPos = LookApplier.MixColor(
            DARK_POS,
            LookApplier.HexToColor(graveLook.colorPos, DARK_POS),
            eased
        )
        local fogColor = LookApplier.MixColor(
            DARK_NEG,
            LookApplier.HexToColor(graveLook.fogColor, DARK_NEG),
            eased
        )
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.meshColor", ColorToHex(meshColor))
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorNeg", ColorToHex(colorNeg))
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorMid", ColorToHex(colorMid))
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.colorPos", ColorToHex(colorPos))
        self:SetStillParam(TOMB_OBJECT_ID, "slots.stone.fogColor", ColorToHex(fogColor))
    end
end

function Director5_3:BeginFocus()
    self.stage = "focus_wait"
    self.stageElapsed = 0.0
    local cameraState = self:GetCameraFocusState()
    self.focusStartTarget = cameraState and cameraState.target or nil
    self.focusStartSize = cameraState and cameraState.orthoSize or nil
    print("Director5_3: waiting before memorial focus")
end

function Director5_3:UpdateFocus(timeStep)
    self.focusElapsed = self.focusElapsed + timeStep
    local progress = Clamp01(self.focusElapsed / FOCUS_DURATION)
    local tombPosition = self:GetOriginalPartPosition(TOMB_PART_ID)
    local target = Vector3(tombPosition.x, tombPosition.y + 0.7, tombPosition.z)
    local preview = self:GetPreview()
    local startTarget = self.focusStartTarget or target
    local startSize = self.focusStartSize
        or (preview and preview.levelDocument.fixedCamera.orthoSize or FOCUS_ORTHO_SIZE)
    local eased = EaseOutCubic(progress)
    local focusTarget = startTarget + (target - startTarget) * eased
    local size = startSize + (FOCUS_ORTHO_SIZE - startSize) * eased
    self:SetCameraFocus(focusTarget, size)
    if progress >= 1.0 then
        self:BeginFlowerDrop()
    end
end

function Director5_3:BeginFlowerDrop()
    if self.flowerDropped then
        return
    end
    self.flowerDropped = true
    self.stage = "flower_drop"
    local graveRoot = self:GetPreview().partRenderer:GetRoot(TOMB_OBJECT_ID)
    local tombRoot = self:GetPreview().partRenderer:GetRoot(TOMB_PART_ID)
    local gravePosition = graveRoot and graveRoot.worldPosition or nil
    if not gravePosition and tombRoot then
        gravePosition = tombRoot.worldPosition + Vector3(0.0, 0.2, 0.0)
    end
    if not gravePosition then
        gravePosition = Vector3(0.0, 0.2, 0.0)
    end
    local playerPosition = self:GetPlayer() and self:GetPlayer():GetPosition() or gravePosition
    local direction = gravePosition - playerPosition
    direction.y = 0.0
    local distance = direction:Length()
    if distance > 0.001 then
        gravePosition = gravePosition - direction / distance * 0.35
    end
    if not self:DropCarriedStillObject(gravePosition, FLOWER_DROP_DURATION) then
        self.stage = "complete"
        self:FinishLevel()
        return
    end
    print("Director5_3: Charlie places the flower")
end

function Director5_3:OnFinish(payload)
    if self.finishStarted then
        return
    end
    self.finishStarted = true
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
    local session = self.session
    if session and session.onFinish then
        session.onFinish(session, payload)
    end
end

function Director5_3:OnUpdate(timeStep)
    if self.stage == "raising_path" then
        self.pathRiseElapsed = self.pathRiseElapsed + timeStep
        local progress = Clamp01(self.pathRiseElapsed / PATH_RISE_DURATION)
        self:ApplyPartRise(STATIC_PATH_PARTS[self.nextPathIndex], progress)
        if progress >= 1.0 then
            local partId = STATIC_PATH_PARTS[self.nextPathIndex]
            local original = self:GetOriginalPartPosition(partId)
            self:SetPartPosition(partId, {
                x = original.x,
                y = PATH_RISE_HEIGHT,
                z = original.z,
            }, true)
            self.stage = "playable"
            self:SetPlayerLocked(false)
            self:SetInputLocked(false)
        end
        return
    end
    if self.stage == "raising_tomb" then
        self.tombRiseElapsed = self.tombRiseElapsed + timeStep
        local progress = Clamp01(self.tombRiseElapsed / TOMB_RISE_DURATION)
        self:ApplyTombRise(progress)
        if progress >= 1.0 then
            self:SetPartPosition(TOMB_PART_ID, self:GetOriginalPartPosition(TOMB_PART_ID), false)
            self:BeginFocus()
        end
        return
    end
    if self.stage == "focus_wait" then
        self.stageElapsed = self.stageElapsed + timeStep
        if self.stageElapsed >= FOCUS_DELAY then
            self.stage = "focusing"
            self.focusElapsed = 0.0
        end
        return
    end
    if self.stage == "focusing" then
        self:UpdateFocus(timeStep)
        return
    end
    if self.stage == "flower_drop" and self:IsCarriedStillObjectDropped() then
        self.stage = "complete"
        self:FinishLevel()
    end
end

function Director5_3:OnDispose()
    self:ClearCarriedStillObject()
    self:SetInputLocked(true)
    self:SetPlayerLocked(true)
end

return Director5_3
