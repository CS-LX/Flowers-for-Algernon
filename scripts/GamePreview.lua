-- 固定游戏镜头下的只读关卡运行时。
-- 自己持有 Scene、Viewport 和角色表现；不依赖 LevelEditor / OverlayViewManager。
-- 信号总线与关卡演出由 LevelSession 持有；本模块提供玩家 / 静物 / Part 的运行时操控入口。

local PartRootRenderer = require "PartRootRenderer"
local FixedGameCamera = require "FixedGameCamera"
local PathRuntime = require "PathRuntime"
local PlayerController = require "PlayerController"
local PlayerView = require "PlayerView"
local AlgernonController = require "AlgernonController"
local AlgernonView = require "AlgernonView"
local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"
local PreviewRotatorController = require "PreviewRotatorController"
local PreviewMoverController = require "PreviewMoverController"
local RiderFollow = require "RiderFollow"
local LookApplier = require "LookApplier"
local ClickFeedbackVfx = require "ClickFeedbackVfx"
local PointerInput = require "PointerInput"
local BgmTracks = require "BgmTracks"
local Sfx = require "Sfx"
local UI = require("urhox-libs/UI")

local FOG_REVEAL_DURATION = 1.0
local COVER_FOG_START = 0.1
local COVER_FOG_END = 2.0
local COVER_FOG_DENSITY = 1.0
-- 卡顿帧 dt 远大于 50ms；连续 3 帧正常后再散雾。
local SETTLE_STABLE_DT = 0.05
local SETTLE_NEEDED = 3
-- 散雾期间再卡一帧也不把 1s tween 一次吃完。
local MAX_REVEAL_DT = 1.0 / 30.0

local GamePreview = {}
GamePreview.__index = GamePreview

function GamePreview.New(levelDocument, edgeLength, voxelHeight)
    local self = setmetatable({}, GamePreview)
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    ---@type Scene|nil
    self.scene = nil
    ---@type Node|nil
    self.cameraNode = nil
    ---@type Camera|nil
    self.camera = nil
    ---@type Viewport|nil
    self.viewport = nil
    ---@type Vector3|nil
    self.cameraBaseTarget = nil
    ---@type Vector3|nil
    self.cameraBasePosition = nil
    self.cameraFocusTarget = nil
    self.partRenderer = nil
    self.pathRuntime = nil
    self.player = nil
    ---@type table|nil
    self.playerView = nil
    ---@type table|nil
    self.algernon = nil
    ---@type table|nil
    self.algernonView = nil
    self.algernonCarried = false
    self.algernonCarryOffset = Vector3(0.0, 0.68, 0.0)
    ---@type table|nil
    self.algernonDrop = nil
    self.spawnNodeKey = nil
    ---@type table|nil
    self.carryObjectView = nil
    ---@type table|nil
    self.carryObjectState = nil
    self.clickFeedback = ClickFeedbackVfx.New()
    self.rotatorController = nil
    ---@type fun(payload: table)|nil
    self.onRotatorFault = nil
    self.hoverAmounts = {}
    self.moverController = nil
    ---@type table|nil
    self.riderFollow = nil
    self.inputLocked = false
    self.storyBlocked = false
    ---@type table|nil
    self.fogReveal = nil
    self.waitingSettle = false
    self.settleCount = 0
    ---@type fun()|nil
    self.onFogRevealFinished = nil
    ---@type fun()|nil
    self.onLevelSettled = nil
    ---@type fun()|nil
    self.onFogCoverFinished = nil
    self.coverOnStart = false
    ---@type Color|nil
    self.coverColor = nil
    self.frameTimeStep = 0.016
    ---@type Node|nil
    self.bgmNode = nil
    ---@type SoundSource|nil
    self.bgmSource = nil
    ---@type string|nil
    self.bgmPath = nil
    self.bgmGain = 0.0
    self.bgmFrom = 0.0
    self.bgmTo = 0.0
    self.bgmFadeElapsed = 0.0
    self.bgmFadeDuration = 0.0
    ---@type table|nil
    self.sfx = nil
    return self
end

function GamePreview:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
    -- 玩法进关时立刻盖近雾，避免 hitch 期间露出关卡配置雾。编辑器 Preview 不盖。
    if self.coverOnStart then
        self:ApplyCoverFog(COVER_FOG_DENSITY)
        self:SetInputLocked(true)
    end
    Sfx.BindUiScene(self.scene)
end

function GamePreview:CreateFeedback(record, reachable)
    if not self.clickFeedback then
        self.clickFeedback = ClickFeedbackVfx.New()
    end
    self.clickFeedback:Play(self.scene, record, reachable, self.edgeLength * 0.5)
end

function GamePreview:UpdateFeedback(timeStep)
    if self.clickFeedback then
        self.clickFeedback:Update(timeStep)
    end
end

function GamePreview:FindClickedNode()
    local ray = PointerInput.GetScreenRay(self.camera)
    local candidates = self.pathRuntime:FindNodeCandidatesAtRay(ray)
    return candidates[1] and candidates[1].record or nil
end

function GamePreview:SetInputLocked(locked)
    self.inputLocked = locked == true
end

function GamePreview:SetStoryBlocked(blocked)
    self.storyBlocked = blocked == true
end

function GamePreview:IsInputLocked()
    return self.inputLocked == true
end

function GamePreview:HandlePointer()
    if not self.player then
        return
    end
    if self.inputLocked or self.storyBlocked or self.player.mechanismLocked
        or (self.player.IsInputLocked and self.player:IsInputLocked()) then
        return
    end
    local fromPendingClick = (self.rotatorController and self.rotatorController:ConsumePendingClick())
        or (self.moverController and self.moverController:ConsumePendingClick())
    if not fromPendingClick then
        if PointerInput.IsOverUI() then
            return
        end
        if not PointerInput.Get().pressed then
            return
        end
    end
    local target = self:FindClickedNode()
    if not target then
        return
    end
    local path, errorMessage = self.pathRuntime:FindPath(
        self.player:GetCurrentNodeKey(),
        target.key
    )
    local reachable = path ~= nil
    self:CreateFeedback(target, reachable)
    if not reachable then
        print("Game Preview: target unreachable " .. target.key .. " (" .. tostring(errorMessage) .. ")")
        return
    end
    local moved, moveError = self.player:MoveTo(path, target.key)
    if not moved then
        print("Game Preview: player move rejected: " .. tostring(moveError))
        return
    end
    print("Game Preview: BFS path " .. table.concat(path, " -> "))
end

function GamePreview:Start()
    self.spawnNodeKey = self.levelDocument:GetSpawnNodeKey()
    if not self.spawnNodeKey or self.spawnNodeKey == "" then
        return false, "必须先配置有效的出生点"
    end
    self:CreateScene()
    self.sfx = Sfx.New(self.scene)
    self.cameraNode, self.camera = FixedGameCamera.Create(
        self.scene,
        "FixedPreviewCamera",
        self.levelDocument.fixedCamera
    )
    self.cameraBaseTarget, self.cameraBasePosition = FixedGameCamera.GetWorldPosition(
        self.levelDocument.fixedCamera
    )
    self.cameraFocusTarget = self.cameraBaseTarget
    self.viewport = Viewport:new(self.scene, self.camera)
    self.partRenderer = PartRootRenderer.New(self.scene, self.edgeLength, self.voxelHeight)
    local built, errorMessage = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        self:Stop()
        return false, errorMessage
    end

    self.pathRuntime = PathRuntime.New(self.levelDocument, self.partRenderer.grid)
    self.pathRuntime:ConfigureEvaluation(
        self.partRenderer,
        self.cameraNode,
        self.camera,
        {}
    )
    local rebuilt, rebuildError = self.pathRuntime:Rebuild()
    if not rebuilt then
        self:Stop()
        return false, rebuildError
    end
    local spawn = self.pathRuntime:GetNode(self.spawnNodeKey)
    if not spawn or not spawn.node.walkable or not spawn.worldPoint then
        self:Stop()
        return false, "出生点必须是有效的可走 PathNode"
    end

    renderer:SetViewport(0, self.viewport)
    renderer:SetNumViewports(1)
    if self.coverOnStart then
        self:ApplyCoverFog(COVER_FOG_DENSITY)
        self:SetInputLocked(true)
    end
    self.player = PlayerController.New(self.pathRuntime, self.spawnNodeKey, self.camera)
    local playerStarted, playerError = self.player:Start()
    if not playerStarted then
        self:Stop()
        return false, playerError
    end
    self:PresentPlayer()
    self.player:SetOnArrived(function(nodeKey)
        if self.clickFeedback then
            self.clickFeedback:NotifyArrived(nodeKey)
        end
    end)
    self.algernon = AlgernonController.New(self.pathRuntime, self.spawnNodeKey, self.camera)
    self.riderFollow = RiderFollow.New(self.levelDocument, self.partRenderer)
    self.riderFollow:Bind(self.player, self.algernon)

    self.rotatorController = PreviewRotatorController.New(
        self.levelDocument,
        self.partRenderer,
        self.pathRuntime,
        self.camera,
        self.scene,
        self.player,
        self.algernon,
        self.riderFollow
    )
    self.rotatorController.autoPick = false
    if self.onRotatorFault then
        self.rotatorController.onFault = self.onRotatorFault
    end
    self.moverController = PreviewMoverController.New(
        self.levelDocument,
        self.partRenderer,
        self.pathRuntime,
        self.camera,
        self.player,
        self.algernon,
        self.riderFollow
    )
    self.moverController.autoPick = false
    print("Game Preview: started with player, rotator and mover drag")
    return true
end

local HOVER_FADE_SECONDS = 0.25

function GamePreview:GetScreenRay()
    return PointerInput.GetScreenRay(self.camera)
end

function GamePreview:CanMovePart(part)
    if self.inputLocked or self.storyBlocked then
        return false
    end
    if self.player and (
        self.player:IsWalking()
        or self.player.mechanismLocked
        or (self.player.IsInputLocked and self.player:IsInputLocked())
    ) then
        return false
    end
    if not part then
        return false
    end
    local isRotator = part:HasBehavior("rotator")
    local isMover = part:HasBehavior("mover")
    if not isRotator and not isMover then
        return false
    end
    if isRotator and self.rotatorController and self.rotatorController:IsWalkingOnPart(part) then
        return false
    end
    if isMover and self.moverController and self.moverController:IsWalkingOnPart(part) then
        return false
    end
    return true
end

function GamePreview:FindHoveredMovablePart()
    if not self.partRenderer or not self.camera then
        return nil
    end
    local ray = self:GetScreenRay()
    local bestPart = nil
    local bestDistance = math.huge
    for _, part in ipairs(self.levelDocument:GetParts()) do
        if self:CanMovePart(part) then
            local distance = self.partRenderer:RaycastPart(part.id, ray)
            if distance and distance < bestDistance then
                bestDistance = distance
                bestPart = part
            end
        end
    end
    return bestPart
end

function GamePreview:IsPartActive(part)
    if not part then
        return false
    end
    if self.rotatorController and self.rotatorController.activePart and self.rotatorController.activePart.id == part.id then
        return self.rotatorController.phase == "pending"
            or self.rotatorController.phase == "drag"
            or self.rotatorController.phase == "snap"
    end
    if self.moverController and self.moverController.activePart and self.moverController.activePart.id == part.id then
        return self.moverController.phase == "pending"
            or self.moverController.phase == "drag"
            or self.moverController.phase == "snap"
    end
    return false
end

function GamePreview:UpdateHoverEmission(timeStep)
    if not self.partRenderer then
        return
    end
    local hovered = self:FindHoveredMovablePart()
    local hoveredId = hovered and hovered.id or nil
    self.hoverAmounts = self.hoverAmounts or {}
    for _, part in ipairs(self.levelDocument:GetParts()) do
        local shouldLit = false
        if hoveredId == part.id then
            shouldLit = true
        elseif self:IsPartActive(part) and self:CanMovePart(part) then
            shouldLit = true
        end
        local current = self.hoverAmounts[part.id] or 0.0
        local target = shouldLit and 1.0 or 0.0
        if current ~= target then
            local step = (timeStep / HOVER_FADE_SECONDS)
            if target > current then
                current = math.min(target, current + step)
            else
                current = math.max(target, current - step)
            end
        end
        self.hoverAmounts[part.id] = current
        self.partRenderer:SetHoverAmount(part.id, current)
    end
end

function GamePreview:MovePlayerTo(nodeKey)
    if not self.player or not self.pathRuntime then
        return false, "no player"
    end
    if type(nodeKey) ~= "string" or nodeKey == "" then
        return false, "empty node key"
    end
    local path, errorMessage = self.pathRuntime:FindPath(
        self.player:GetCurrentNodeKey(),
        nodeKey
    )
    if not path then
        return false, errorMessage
    end
    return self.player:MoveTo(path, nodeKey)
end

function GamePreview:TeleportPlayerTo(nodeKey)
    if not self.player then
        return false, "no player"
    end
    local teleported, errorMessage = self.player:TeleportTo(nodeKey)
    if not teleported then
        return false, errorMessage
    end
    self:PresentPlayer()
    return true
end

function GamePreview:StopPlayer()
    if not self.player then
        return false
    end
    if self.player.StopAtCurrentNode then
        local stopped = self.player:StopAtCurrentNode()
        return stopped
    end
    self.player:Stop()
    return true
end

function GamePreview:SetPlayerVisible(visible)
    if not self.playerView then
        return false
    end
    return self.playerView:SetVisible(visible)
end

function GamePreview:SetCameraLiftOffset(offsetY)
    if not self.cameraNode or not self.cameraBaseTarget or not self.cameraBasePosition then
        return false
    end
    local offset = Vector3(0, offsetY or 0.0, 0)
    self.cameraFocusTarget = self.cameraBaseTarget + offset
    self.cameraNode.position = self.cameraBasePosition + offset
    self.cameraNode:LookAt(self.cameraFocusTarget)
    return true
end

function GamePreview:NotifyPartMotion(part)
    if not self.riderFollow or not part then
        return
    end
    if self.riderFollow:IsOnPart(self.player, part) and self.player and self.player.ClearTopmostHold then
        self.player:ClearTopmostHold()
    end
    if self.riderFollow:IsOnPart(self.algernon, part) and self.algernon and self.algernon.ClearTopmostHold then
        self.algernon:ClearTopmostHold()
    end
end

function GamePreview:SetRotatorFault(partId, config)
    if not self.rotatorController then
        return false
    end
    return self.rotatorController:SetFault(partId, config)
end

function GamePreview:SetOnRotatorFault(listener)
    self.onRotatorFault = listener
    if self.rotatorController then
        self.rotatorController.onFault = listener
    end
    return true
end

function GamePreview:SetPartVisualYaw(partId, yawDegrees)
    if not self.partRenderer then
        return false
    end
    local applied = self.partRenderer:SetVisualYaw(partId, yawDegrees)
    if applied then
        local part = self.levelDocument:GetPart(partId)
        self:NotifyPartMotion(part)
        self:SyncRiders()
    end
    return applied
end

function GamePreview:PresentCarriedStillObject()
    local view = self.carryObjectView
    local state = self.carryObjectState
    if not view or not state or not self.player then
        return
    end
    local playerRotation = self.player:GetRotation()
    if state.carried then
        view.root.position = self.player:GetPosition()
            + playerRotation * state.offset
        view.root.rotation = playerRotation
    elseif state.dropPosition then
        view.root.position = state.dropPosition
        view.root.rotation = state.dropRotation or playerRotation
    end
end

function GamePreview:SetCarriedStillObject(modelId, offset, scale)
    if not self.scene or not self.player or type(modelId) ~= "string" then
        return false
    end
    self:ClearCarriedStillObject()
    local object = StillObject.New({
        id = "carried_still_object",
        modelId = modelId,
        transform = {
            scale = { x = 1.0, y = 1.0, z = 1.0 },
        },
    })
    local root = self.scene:CreateChild("CarriedStillObject")
    local runtime = StillObjectRuntime.Bind(root, object)
    if not runtime then
        root:Remove()
        return false
    end
    for _, slot in ipairs(runtime.asset.slots) do
        object:SetParam("slots." .. slot.id .. ".fogHeightA", "0.0")
        object:SetParam("slots." .. slot.id .. ".fogHeightB", "0.0")
        object:SetParam("slots." .. slot.id .. ".fogColor", "#000000")
        object:SetParam("slots." .. slot.id .. ".gradeSaturation", "1.0")
        object:SetParam("slots." .. slot.id .. ".gradeValue", "1.08")
        object:SetParam("slots." .. slot.id .. ".gradeContrast", "1.0")
        object:SetParam("slots." .. slot.id .. ".gradeHaze", "0.0")
    end
    StillObjectRuntime.ApplyLooks(runtime, object)
    local bounds = runtime.localBounds
    local targetHeight = tonumber(scale) or 0.55
    if bounds and bounds.max.y > bounds.min.y then
        local factor = targetHeight / (bounds.max.y - bounds.min.y)
        root.scale = Vector3(factor, factor, factor)
        runtime.node.position = Vector3(
            -(bounds.min.x + bounds.max.x) * 0.5,
            -bounds.min.y,
            -(bounds.min.z + bounds.max.z) * 0.5
        )
    end
    local carryOffset = offset or Vector3(0.0, 0.68, 0.0)
    self.carryObjectView = {
        root = root,
        runtime = runtime,
    }
    self.carryObjectState = {
        carried = true,
        offset = Vector3(carryOffset.x, carryOffset.y, carryOffset.z),
        dropPosition = nil,
        dropRotation = nil,
        elapsed = 0.0,
        duration = 0.0,
        startPosition = nil,
        targetPosition = nil,
    }
    self:PresentCarriedStillObject()
    print("GamePreview: carried still object set " .. modelId)
    return true
end

function GamePreview:DropCarriedStillObject(targetPosition, duration)
    local state = self.carryObjectState
    if not state or not state.carried or not self.player then
        return false
    end
    local playerRotation = self.player:GetRotation()
    local startPosition = self.player:GetPosition()
        + playerRotation * state.offset
    state.carried = false
    state.elapsed = 0.0
    state.duration = math.max(0.1, tonumber(duration) or 0.7)
    state.startPosition = startPosition
    state.targetPosition = Vector3(
        targetPosition.x,
        targetPosition.y,
        targetPosition.z
    )
    state.dropPosition = startPosition
    state.dropRotation = playerRotation
    self:PresentCarriedStillObject()
    print("GamePreview: carried still object drop started")
    return true
end

function GamePreview:IsCarriedStillObjectDropping()
    local state = self.carryObjectState
    return state ~= nil and state.carried == false and state.targetPosition ~= nil
        and state.dropFinished ~= true
end

function GamePreview:IsCarriedStillObjectDropped()
    local state = self.carryObjectState
    return state ~= nil and state.dropFinished == true
end

function GamePreview:UpdateCarriedStillObject(timeStep)
    local state = self.carryObjectState
    if not state then
        return
    end
    if state.carried then
        self:PresentCarriedStillObject()
        return
    end
    if not state.targetPosition or state.dropFinished then
        return
    end
    state.elapsed = state.elapsed + timeStep
    local progress = math.max(0.0, math.min(1.0, state.elapsed / state.duration))
    local eased = progress * progress * (3.0 - 2.0 * progress)
    local base = state.startPosition
        + (state.targetPosition - state.startPosition) * eased
    local dropOffset = -math.sin(progress * math.pi) * 0.12
    state.dropPosition = base + Vector3(0.0, dropOffset, 0.0)
    self:PresentCarriedStillObject()
    if progress >= 1.0 then
        state.dropPosition = state.targetPosition
        state.dropFinished = true
        self:PresentCarriedStillObject()
        print("GamePreview: carried still object drop finished")
    end
end

function GamePreview:ClearCarriedStillObject()
    if self.carryObjectView and self.carryObjectView.root then
        self.carryObjectView.root:Remove()
    end
    self.carryObjectView = nil
    self.carryObjectState = nil
end

function GamePreview:SetCameraFocus(target, orthoSize)
    if not self.cameraNode or not self.camera or not self.cameraBaseTarget
        or not self.cameraBasePosition then
        return false
    end
    local targetPoint = Vector3(target.x, target.y, target.z)
    local baseOffset = self.cameraBasePosition - self.cameraBaseTarget
    local baseSize = self.levelDocument.fixedCamera.orthoSize
    local size = tonumber(orthoSize) or baseSize
    local ratio = size / math.max(0.001, baseSize)
    self.cameraFocusTarget = targetPoint
    self.camera.orthoSize = size
    self.cameraNode.position = targetPoint + baseOffset * ratio
    self.cameraNode:LookAt(targetPoint)
    return true
end

function GamePreview:GetCameraFocusState()
    if not self.cameraNode or not self.camera then
        return nil
    end
    return {
        target = self.cameraFocusTarget or self.cameraBaseTarget,
        orthoSize = self.camera.orthoSize,
    }
end

function GamePreview:SetPartVisualPosition(partId, position)
    if not self.partRenderer then
        return false
    end
    local applied = self.partRenderer:SetVisualPosition(partId, position)
    if applied then
        local part = self.levelDocument:GetPart(partId)
        self:NotifyPartMotion(part)
        self:SyncRiders()
    end
    return applied
end

function GamePreview:SetPartLookColors(partId, colorNeg, colorMid, colorPos, fogColor)
    if not self.partRenderer then
        return false
    end
    return self.partRenderer:SetPartLookColors(
        partId,
        colorNeg,
        colorMid,
        colorPos,
        fogColor
    )
end

function GamePreview:SetAtmosphereFogColor(color)
    if not self.scene then
        return false
    end
    return LookApplier.SetFogColor(self.scene, color)
end

function GamePreview:ApplyStillObject(object)
    if not self.partRenderer then
        return false
    end
    return self.partRenderer:ApplyStillObject(object)
end

function GamePreview:ApplyPart(part, refreshPath)
    if not self.partRenderer or not part then
        return false
    end
    if not self.partRenderer:ApplyPart(part) then
        return false
    end
    self:NotifyPartMotion(part)
    if refreshPath ~= false and self.pathRuntime then
        local refreshed, errorMessage = self.pathRuntime:RefreshAfterMechanismSnap()
        if not refreshed then
            print("GamePreview: path refresh failed: " .. tostring(errorMessage))
            return false, errorMessage
        end
    end
    self:SyncRiders()
    return true
end

function GamePreview:RefreshPathRuntime()
    if not self.pathRuntime then
        return false, "no path runtime"
    end
    return self.pathRuntime:RefreshAfterMechanismSnap()
end

function GamePreview:SyncRiders()
    if not self.riderFollow then
        return false
    end
    local followed = self.riderFollow:Sync()
    self:PresentPlayer()
    self:PresentAlgernon()
    return followed
end

function GamePreview:SetObjectEnabled(objectId, enabled)
    if not self.partRenderer then
        return false
    end
    return self.partRenderer:SetObjectEnabled(objectId, enabled)
end

function GamePreview:BeginMechanismPending()
    if self.inputLocked or self.storyBlocked then
        return false
    end
    if PointerInput.IsOverUI() then
        return false
    end
    if not PointerInput.Get().pressed then
        return false
    end
    if self.player and (self.player:IsWalking() or self.player.mechanismLocked) then
        return false
    end
    local mouse = PointerInput.Get().position
    local ray = PointerInput.GetScreenRay(self.camera)
    local rotatorPart, rotatorDistance = nil, math.huge
    local moverPart, moverDistance = nil, math.huge
    if self.rotatorController then
        rotatorPart = self.rotatorController:PickRotatorPart(ray)
        if rotatorPart then
            rotatorDistance = self.partRenderer:RaycastPart(rotatorPart.id, ray) or math.huge
        end
    end
    if self.moverController then
        moverPart, moverDistance = self.moverController:PickMoverPart(ray)
        moverDistance = moverDistance or math.huge
    end
    if rotatorPart and moverPart and rotatorPart.id == moverPart.id then
        local startedRotator = self.rotatorController:BeginPending(rotatorPart, ray, mouse)
        local startedMover = self.moverController:BeginPending(moverPart, ray, mouse)
        return startedRotator or startedMover
    end
    if rotatorPart and rotatorDistance <= moverDistance then
        return self.rotatorController:BeginPending(rotatorPart, ray, mouse)
    end
    if moverPart then
        return self.moverController:BeginPending(moverPart, ray, mouse)
    end
    return false
end

function GamePreview:ResolveSharedPending()
    local rotator = self.rotatorController
    local mover = self.moverController
    if not rotator or not mover then
        return
    end
    local part = rotator.activePart
    if not part or not rotator:HasPendingPart(part) or not mover:HasPendingPart(part) then
        return
    end
    local rotatorScore = rotator:GetPendingDragScore()
    local moverScore = mover:GetPendingDragScore()
    if rotatorScore <= 0 and moverScore <= 0 then
        return
    end
    if rotatorScore >= moverScore then
        mover:CancelPendingQuietly()
    else
        rotator:CancelPendingQuietly()
    end
end

function GamePreview:EnsureBgmSource()
    if self.bgmSource then
        return self.bgmSource
    end
    if not self.scene then
        return nil
    end
    self.bgmNode = self.scene:CreateChild("LevelBgm")
    local source = self.bgmNode:CreateComponent("SoundSource")
    if not source then
        print("GamePreview: failed to create level SoundSource")
        return nil
    end
    source:SetSoundType(SOUND_MUSIC)
    source:SetGain(0.0)
    self.bgmSource = source
    return source
end

function GamePreview:ApplyBgmGain()
    if self.bgmSource then
        self.bgmSource:SetGain(self.bgmGain)
    end
end

function GamePreview:PlayBgmPath(path, looped)
    local source = self:EnsureBgmSource()
    if not path or not source then
        return false
    end
    if self.bgmPath == path and source.playing then
        if self.bgmTo < 1.0 then
            self.bgmFrom = self.bgmGain
            self.bgmTo = 1.0
            self.bgmFadeElapsed = 0.0
            self.bgmFadeDuration = BgmTracks.FADE
        end
        return true
    end
    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("GamePreview: missing bgm " .. path)
        return false
    end
    sound:SetLooped(looped ~= false)
    self.bgmPath = path
    self.bgmGain = 0.0
    self.bgmFrom = 0.0
    self.bgmTo = 1.0
    self.bgmFadeElapsed = 0.0
    self.bgmFadeDuration = BgmTracks.FADE
    source:Play(sound, sound:GetFrequency(), 0.0)
    self:ApplyBgmGain()
    print("GamePreview: play bgm " .. path)
    return true
end

function GamePreview:PlayChapterBgm(chapter)
    return self:PlayBgmPath(BgmTracks.ChapterPath(chapter), true)
end

function GamePreview:ReleaseBgm()
    if not self.bgmNode or not self.bgmSource then
        return nil
    end
    local snapshot = {
        node = self.bgmNode,
        source = self.bgmSource,
        path = self.bgmPath,
        gain = self.bgmGain,
        from = self.bgmFrom,
        to = self.bgmTo,
        fadeElapsed = self.bgmFadeElapsed,
        fadeDuration = self.bgmFadeDuration,
    }
    self.bgmNode = nil
    self.bgmSource = nil
    self.bgmPath = nil
    self.bgmGain = 0.0
    self.bgmFrom = 0.0
    self.bgmTo = 0.0
    self.bgmFadeElapsed = 0.0
    self.bgmFadeDuration = 0.0
    return snapshot
end

function GamePreview:AdoptBgm(snapshot)
    if not snapshot or not snapshot.node or not snapshot.source or not self.scene then
        return false
    end
    snapshot.node:SetParent(self.scene)
    self.bgmNode = snapshot.node
    self.bgmSource = snapshot.source
    local sound = snapshot.source:GetSound()
    if sound then
        snapshot.source:SetFrequency(sound:GetFrequency())
    end
    self.bgmPath = snapshot.path
    self.bgmGain = snapshot.gain or 0.0
    self.bgmFrom = snapshot.from or self.bgmGain
    self.bgmTo = snapshot.to or 1.0
    self.bgmFadeElapsed = snapshot.fadeElapsed or 0.0
    self.bgmFadeDuration = snapshot.fadeDuration or 0.0
    self:ApplyBgmGain()
    print("GamePreview: adopt bgm " .. tostring(self.bgmPath))
    return true
end

function GamePreview:PlayCreditsBgm()
    return self:PlayBgmPath(BgmTracks.CreditsPath(), true)
end

function GamePreview:FadeOutBgm(duration)
    if not self.bgmSource then
        return
    end
    if self.bgmTo <= 0.0 then
        if self.bgmFadeDuration > 0.0 or self.bgmGain <= 0.0 then
            return
        end
    end
    self.bgmFrom = self.bgmGain
    self.bgmTo = 0.0
    self.bgmFadeElapsed = 0.0
    self.bgmFadeDuration = tonumber(duration) or BgmTracks.FADE
end

function GamePreview:UpdateBgm(timeStep)
    if self.bgmFadeDuration <= 0.0 then
        return
    end
    local elapsed = self.bgmFadeElapsed + timeStep
    self.bgmFadeElapsed = elapsed
    local t = elapsed / self.bgmFadeDuration
    if t >= 1.0 then
        self.bgmGain = self.bgmTo
        self.bgmFadeDuration = 0.0
        self:ApplyBgmGain()
        if self.bgmTo <= 0.0 and self.bgmSource then
            self.bgmSource:Stop()
            self.bgmPath = nil
        end
        return
    end
    self.bgmGain = self.bgmFrom + (self.bgmTo - self.bgmFrom) * t
    self:ApplyBgmGain()
end

function GamePreview:Update(timeStep)
    self.frameTimeStep = timeStep
    self:UpdateBgm(timeStep)
    PointerInput.BeginFrame()
    self:ResolveSharedPending()
    ---@type boolean
    local rotatorBusy = false
    ---@type boolean
    local moverBusy = false
    if self.rotatorController then
        rotatorBusy = self.rotatorController:Update(timeStep) and true or false
    end
    if self.moverController then
        moverBusy = self.moverController:Update(timeStep) and true or false
    end
    if not rotatorBusy and not moverBusy then
        if not self:BeginMechanismPending() then
            self:HandlePointer()
        end
    end
    if self.player then
        self.player:Update(timeStep)
    end
    if self.algernon then
        self.algernon:Update(timeStep)
    end
    self:UpdateAlgernonDrop(timeStep)
    self:UpdateCarriedStillObject(timeStep)
    self:SyncRiders()
    self:UpdateHoverEmission(timeStep)
    self:UpdateFeedback(timeStep)
    self:UpdateFogReveal(timeStep)
end

function GamePreview:PresentPlayer()
    if not self.player or not self.scene then
        self:ClearPlayerView()
        return
    end
    local topmost = self.player:GetViewState() == "topmost"
    if not self.playerView or self.playerView.topmost ~= topmost
        or self.playerView.scene ~= self.scene then
        print(string.format(
            "GamePreview: recreate player viewState=%s scene=level",
            topmost and "topmost" or "normal"
        ))
        self:ClearPlayerView()
        self.playerView = PlayerView.New(self.scene, topmost)
    end
    self.playerView:Apply(
        self.player:GetPosition(),
        self.player:GetRotation(),
        self.player:IsWalking(),
        self.frameTimeStep or 0.016
    )
end

function GamePreview:ClearPlayerView()
    if self.playerView then
        self.playerView:Destroy()
        self.playerView = nil
    end
end

function GamePreview:PresentAlgernon()
    if not self.algernon or not self.scene or not self.algernon:IsEnabled() then
        self:ClearAlgernonView()
        return
    end
    if not self.algernonView or self.algernonView.scene ~= self.scene then
        self:ClearAlgernonView()
        self.algernonView = AlgernonView.New(self.scene)
    end
    self.algernonView:SetVisible(self.algernon:IsVisible())
    if self.algernonDrop then
        self.algernonView:Apply(
            self.algernonDrop.position,
            self.algernonDrop.rotation
        )
        return
    end
    if self.algernonCarried and self.player then
        local playerRotation = self.player:GetRotation()
        local carryPosition = self.player:GetPosition()
            + playerRotation * self.algernonCarryOffset
        self.algernonView:Apply(carryPosition, playerRotation)
        return
    end
    self.algernonView:Apply(self.algernon:GetPosition(), self.algernon:GetRotation())
end

---@param carried boolean
---@param offset Vector3|nil
---@return boolean
function GamePreview:SetAlgernonCarried(carried, offset)
    if not self.algernon or not self.algernon:IsEnabled() then
        return false
    end
    self.algernonCarried = carried == true
    self.algernonDrop = nil
    if offset then
        self.algernonCarryOffset = Vector3(offset.x, offset.y, offset.z)
    end
    if self.algernonCarried then
        self.algernon:Stop()
        self.algernon:ClearTopmostHold()
    end
    self:PresentAlgernon()
    print("GamePreview: Algernon carried=" .. tostring(self.algernonCarried))
    return true
end

---@param nodeKey string
---@param duration number|nil
---@return boolean
function GamePreview:DropAlgernonAt(nodeKey, duration)
    if not self.algernon or not self.algernon:IsEnabled() or not self.player then
        return false
    end
    local record = self.pathRuntime and self.pathRuntime:GetNode(nodeKey) or nil
    if not record or not record.worldPoint then
        return false
    end
    local playerRotation = self.player:GetRotation()
    local startPosition = self.player:GetPosition()
        + playerRotation * self.algernonCarryOffset
    self.algernonCarried = false
    self.algernon:Stop()
    self.algernon:ClearTopmostHold()
    self.algernonDrop = {
        elapsed = 0.0,
        duration = math.max(0.1, tonumber(duration) or 0.55),
        startPosition = startPosition,
        position = startPosition,
        targetPosition = record.worldPoint,
        rotation = playerRotation,
        targetKey = nodeKey,
    }
    self:PresentAlgernon()
    print("GamePreview: Algernon drop started at " .. nodeKey)
    return true
end

function GamePreview:UpdateAlgernonDrop(timeStep)
    local drop = self.algernonDrop
    if not drop then
        return
    end
    drop.elapsed = drop.elapsed + timeStep
    local progress = math.max(0.0, math.min(1.0, drop.elapsed / drop.duration))
    local eased = progress * progress * (3.0 - 2.0 * progress)
    local base = drop.startPosition + (drop.targetPosition - drop.startPosition) * eased
    local fall = -math.sin(progress * math.pi) * 0.12
    drop.position = base + Vector3(0.0, fall, 0.0)
    if progress >= 1.0 then
        drop.position = drop.targetPosition
        self.algernon:TeleportTo(drop.targetKey)
        print("GamePreview: Algernon drop finished at " .. drop.targetKey)
        drop = nil
        self.algernonDrop = nil
    end
end

function GamePreview:ClearAlgernonView()
    if self.algernonView then
        self.algernonView:Destroy()
        self.algernonView = nil
    end
end

function GamePreview:SetAlgernonEnabled(enabled, nodeKey)
    if not self.algernon then
        return false, "no algernon"
    end
    if not enabled then
        self.algernonCarried = false
    end
    local ok, errorMessage = self.algernon:SetEnabled(enabled, nodeKey)
    if not ok then
        return false, errorMessage
    end
    self:PresentAlgernon()
    return true
end

function GamePreview:SetAlgernonVisible(visible)
    if not self.algernon then
        return false
    end
    if not self.algernon:SetVisible(visible) then
        return false
    end
    if self.algernonView then
        self.algernonView:SetVisible(self.algernon:IsVisible())
    end
    return true
end

function GamePreview:MoveAlgernonTo(nodeKey)
    if not self.algernon then
        return false, "no algernon"
    end
    return self.algernon:MoveTo(nodeKey)
end

function GamePreview:MoveAlgernonToWorld(worldPoint)
    if not self.algernon then
        return false, "no algernon"
    end
    return self.algernon:MoveToWorld(worldPoint)
end

function GamePreview:TeleportAlgernonTo(nodeKey)
    if not self.algernon then
        return false, "no algernon"
    end
    local teleported, errorMessage = self.algernon:TeleportTo(nodeKey)
    if not teleported then
        return false, errorMessage
    end
    self:PresentAlgernon()
    return true
end

function GamePreview:StopAlgernon()
    if not self.algernon then
        return false
    end
    return self.algernon:Stop()
end

function GamePreview:SetAlgernonSpeed(speed)
    if not self.algernon then
        return false
    end
    return self.algernon:SetSpeed(speed)
end

function GamePreview:SetAlgernonLocalTransform(transform)
    if not self.algernonView then
        if not self.algernon or not self.algernon:IsEnabled() or not self.scene then
            return false
        end
        self:PresentAlgernon()
    end
    if not self.algernonView then
        return false
    end
    return self.algernonView:SetLocalTransform(transform)
end

function GamePreview:SetAlgernonOnArrived(listener)
    if not self.algernon then
        return false
    end
    self.algernon:SetOnArrived(listener)
    return true
end

function GamePreview:CoverFogColor()
    if self.coverColor then
        return self.coverColor
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument and self.levelDocument.atmosphere)
    return LookApplier.HexToColor(atmosphere.fog.color, Color(0.79, 0.76, 0.71, 1))
end

function GamePreview:ApplyCoverFog(density)
    if not self.scene or not self.levelDocument then
        return false
    end
    return LookApplier.SetCoverFog(self.scene, self:CoverFogColor(), density)
end

function GamePreview:BeginFogCover(coverColor)
    if not self.scene or not self.levelDocument then
        return false
    end
    if coverColor then
        self.coverColor = coverColor
    end
    self:ApplyCoverFog(COVER_FOG_DENSITY)
    self:SetInputLocked(true)
    self.fogReveal = nil
    self.waitingSettle = true
    self.settleCount = 0
    print("GamePreview: cover fog on, wait for stable frames then reveal")
    return true
end

function GamePreview:BeginFogConceal(toColor, duration)
    if not self.scene or not self.levelDocument then
        return false
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    local zone = LookApplier.GetZone(self.scene)
    local fromColor = zone and zone.fogColor or self:CoverFogColor()
    local cover = toColor or fromColor
    local fromDensity = zone and zone.fogDensity or atmosphere.fog.density
    local concealDuration = tonumber(duration) or FOG_REVEAL_DURATION
    if concealDuration < 0.1 then
        concealDuration = FOG_REVEAL_DURATION
    end
    LookApplier.SetCoverFog(self.scene, fromColor, fromDensity)
    self:SetInputLocked(true)
    self.waitingSettle = false
    self.fogReveal = {
        duration = concealDuration,
        clock = 0.0,
        fromDensity = fromDensity,
        toDensity = COVER_FOG_DENSITY,
        fromColor = fromColor,
        toColor = cover,
        conceal = true,
    }
    print(string.format(
        "GamePreview: fog conceal 1s density %.2f -> %.2f, keep cover 0.1/2",
        fromDensity,
        COVER_FOG_DENSITY
    ))
    return true
end

function GamePreview:StartFogReveal()
    if not self.scene or not self.levelDocument then
        return false
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    self:ApplyCoverFog(COVER_FOG_DENSITY)
    -- 镜头大约 18m。线性把 fogEnd 从 2 拉到 2000，几十毫秒雾就已经出画面。
    -- 散雾期间锁住 0.1/2，只把 density 从 1 收到关卡值。
    self.fogReveal = {
        duration = FOG_REVEAL_DURATION,
        clock = 0.0,
        fromDensity = COVER_FOG_DENSITY,
        toDensity = atmosphere.fog.density,
        fromColor = self:CoverFogColor(),
        toColor = self:CoverFogColor(),
        conceal = false,
    }
    print(string.format(
        "GamePreview: fog reveal 1s density %.2f -> %.2f, keep cover 0.1/2",
        COVER_FOG_DENSITY,
        atmosphere.fog.density
    ))
    return true
end

function GamePreview:UpdateFogReveal(timeStep)
    if self.waitingSettle then
        self:ApplyCoverFog(COVER_FOG_DENSITY)
        if timeStep > 0.0 and timeStep <= SETTLE_STABLE_DT then
            local settled = self.settleCount + 1
            self.settleCount = settled
        else
            self.settleCount = 0
        end
        if self.settleCount >= SETTLE_NEEDED then
            self.waitingSettle = false
            print(string.format(
                "GamePreview: level settled after %d frames dt=%.3f, start fog reveal",
                SETTLE_NEEDED,
                timeStep
            ))
            if self.onLevelSettled then
                local settled = self.onLevelSettled
                self.onLevelSettled = nil
                settled()
            end
            self:ApplyCoverFog(COVER_FOG_DENSITY)
            self:StartFogReveal()
        end
        return
    end
    local reveal = self.fogReveal
    if not reveal then
        return
    end
    local dt = timeStep
    if dt > MAX_REVEAL_DT then
        dt = MAX_REVEAL_DT
    end
    local nextClock = reveal.clock + dt
    reveal.clock = nextClock
    local t = nextClock / reveal.duration
    if t < 0.0 then
        t = 0.0
    elseif t > 1.0 then
        t = 1.0
    end
    -- 散雾 t^2 后半段才清；盖雾 (1-(1-t)^2) 前半段就迅速盖住。
    local mix = reveal.conceal and (1.0 - (1.0 - t) * (1.0 - t)) or (t * t)
    local zone = LookApplier.GetZone(self.scene)
    local fogColor = LookApplier.MixColor(reveal.fromColor, reveal.toColor, mix)
    if zone then
        zone.fogStart = COVER_FOG_START
        zone.fogEnd = COVER_FOG_END
        zone.fogDensity = reveal.fromDensity + (reveal.toDensity - reveal.fromDensity) * mix
        zone.fogColor = fogColor
    end
    if t >= 1.0 then
        self.fogReveal = nil
        if reveal.conceal then
            self.coverColor = reveal.toColor
            LookApplier.SetCoverFog(self.scene, reveal.toColor, COVER_FOG_DENSITY)
            print("GamePreview: fog conceal finished")
            if self.onFogCoverFinished then
                local finished = self.onFogCoverFinished
                self.onFogCoverFinished = nil
                finished()
            end
            return
        end
        LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
        print("GamePreview: fog reveal finished")
        if self.onFogRevealFinished then
            local finished = self.onFogRevealFinished
            self.onFogRevealFinished = nil
            finished()
        else
            self:SetInputLocked(false)
        end
    end
end

function GamePreview:Stop()
    self.inputLocked = false
    self.storyBlocked = false
    self.fogReveal = nil
    self.waitingSettle = false
    self.settleCount = 0
    self.onFogRevealFinished = nil
    self.onLevelSettled = nil
    self.onFogCoverFinished = nil
    self.coverColor = nil
    self.algernonCarried = false
    self.algernonDrop = nil
    self:ClearCarriedStillObject()
    self.riderFollow = nil
    if self.rotatorController then
        self.rotatorController:RestoreAuthoredStates()
        self.rotatorController = nil
    end
    if self.moverController then
        self.moverController:RestoreAuthoredStates()
        self.moverController = nil
    end
    if self.player then
        self.player = nil
    end
    self:ClearPlayerView()
    if self.algernon then
        self.algernon:SetEnabled(false)
        self.algernon = nil
    end
    self:ClearAlgernonView()
    if self.sfx then
        self.sfx:Destroy()
        self.sfx = nil
    end
    if self.bgmSource then
        self.bgmSource:Stop()
        self.bgmSource = nil
    end
    self.bgmNode = nil
    self.bgmPath = nil
    if self.clickFeedback then
        self.clickFeedback:Destroy()
        self.clickFeedback = nil
    end
    if self.partRenderer then
        self.partRenderer:Clear()
        self.partRenderer = nil
    end
    if self.scene then
        self.scene:Clear(true, true)
        self.scene = nil
    end
    self.pathRuntime = nil
    self.cameraNode = nil
    self.camera = nil
    self.viewport = nil
    self.cameraBaseTarget = nil
    self.cameraBasePosition = nil
    self.cameraFocusTarget = nil
end

return GamePreview
