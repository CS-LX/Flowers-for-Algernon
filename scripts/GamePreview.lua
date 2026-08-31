-- 固定游戏镜头下的只读关卡运行时。
-- 自己持有 Scene、Viewport 和角色表现；不依赖 LevelEditor / OverlayViewManager。
-- 不接线关卡信号应用；信号总线由 LevelSession 持有。

local PartRootRenderer = require "PartRootRenderer"
local FixedGameCamera = require "FixedGameCamera"
local PathRuntime = require "PathRuntime"
local PlayerController = require "PlayerController"
local PlayerView = require "PlayerView"
local PreviewRotatorController = require "PreviewRotatorController"
local PreviewMoverController = require "PreviewMoverController"
local LookApplier = require "LookApplier"
local UI = require("urhox-libs/UI")

local GamePreview = {}
GamePreview.__index = GamePreview

local function CreateUnlitMaterial(color)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    return material
end

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
    self.partRenderer = nil
    self.pathRuntime = nil
    self.player = nil
    ---@type table|nil
    self.playerView = nil
    self.spawnNodeKey = nil
    self.feedbackNode = nil
    self.feedbackElapsed = 0.0
    self.feedbackDuration = 0.55
    self.feedbackOriginScale = 0.12
    self.rotatorController = nil
    self.hoverAmounts = {}
    self.moverController = nil
    return self
end

function GamePreview:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
end

function GamePreview:CreateFeedback(record, reachable)
    if self.feedbackNode then
        self.feedbackNode:Remove()
        self.feedbackNode = nil
    end
    local node = self.scene:CreateChild("PathClickFeedback")
    local worldPoint = Vector3(
        record.worldPoint.x,
        record.worldPoint.y,
        record.worldPoint.z
    )
    local normal = record.worldNormal
        and Vector3(record.worldNormal.x, record.worldNormal.y, record.worldNormal.z)
        or Vector3.UP
    node.position = worldPoint + normal * 0.025
    node.rotation = Quaternion(Vector3.UP, normal)
    node.scale = Vector3(self.feedbackOriginScale, self.feedbackOriginScale, self.feedbackOriginScale)

    local ring = node:CreateComponent("StaticModel")
    ring.model = TorusGeometry(0.55, 0.055, 24, 8):ToModel()
    ring.material = CreateUnlitMaterial(
        reachable and Color(0.25, 1.0, 0.58, 1.0) or Color(1.0, 0.28, 0.24, 1.0)
    )
    self.feedbackNode = node
    self.feedbackElapsed = 0.0
end

function GamePreview:UpdateFeedback(timeStep)
    if not self.feedbackNode then
        return
    end
    self.feedbackElapsed = self.feedbackElapsed + timeStep
    local progress = math.min(1.0, self.feedbackElapsed / self.feedbackDuration)
    local scale = self.feedbackOriginScale * (1.0 + progress * 2.4)
    self.feedbackNode.scale = Vector3(scale, scale, scale)
    self.feedbackNode.enabled = progress < 1.0
    if progress >= 1.0 then
        self.feedbackNode:Remove()
        self.feedbackNode = nil
    end
end

function GamePreview:FindClickedNode()
    local mouse = input:GetMousePosition()
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    local ray = self.camera:GetScreenRay(mouse.x / width, mouse.y / height)
    local candidates = self.pathRuntime:FindNodeCandidatesAtRay(ray)
    return candidates[1] and candidates[1].record or nil
end

function GamePreview:HandlePointer()
    if not self.player then
        return
    end
    if self.player.mechanismLocked then
        return
    end
    local fromPendingClick = (self.rotatorController and self.rotatorController:ConsumePendingClick())
        or (self.moverController and self.moverController:ConsumePendingClick())
    if not fromPendingClick then
        if UI.IsPointerOverUI() then
            return
        end
        if not input:GetMouseButtonPress(MOUSEB_LEFT) then
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
    self.cameraNode, self.camera = FixedGameCamera.Create(
        self.scene,
        "FixedPreviewCamera",
        self.levelDocument.fixedCamera
    )
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
    self.player = PlayerController.New(self.pathRuntime, self.spawnNodeKey, self.camera)
    local playerStarted, playerError = self.player:Start()
    if not playerStarted then
        self:Stop()
        return false, playerError
    end
    self:PresentPlayer()

    self.rotatorController = PreviewRotatorController.New(
        self.levelDocument,
        self.partRenderer,
        self.pathRuntime,
        self.camera,
        self.scene,
        self.player
    )
    self.rotatorController.autoPick = false
    self.moverController = PreviewMoverController.New(
        self.levelDocument,
        self.partRenderer,
        self.pathRuntime,
        self.camera,
        self.player
    )
    self.moverController.autoPick = false
    print("Game Preview: started with player, rotator and mover drag")
    return true
end

local HOVER_FADE_SECONDS = 0.5

function GamePreview:GetScreenRay()
    local mouse = input:GetMousePosition()
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    return self.camera:GetScreenRay(mouse.x / width, mouse.y / height)
end

function GamePreview:CanMovePart(part)
    if self.player and self.player.mechanismLocked then
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

function GamePreview:BeginMechanismPending()
    if UI.IsPointerOverUI() then
        return false
    end
    if not input:GetMouseButtonPress(MOUSEB_LEFT) then
        return false
    end
    if self.player and (self.player:IsWalking() or self.player.mechanismLocked) then
        return false
    end
    local mouse = input:GetMousePosition()
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    local ray = self.camera:GetScreenRay(mouse.x / width, mouse.y / height)
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

function GamePreview:Update(timeStep)
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
        self:PresentPlayer()
    end
    self:UpdateHoverEmission(timeStep)
    self:UpdateFeedback(timeStep)
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
    self.playerView:Apply(self.player:GetPosition(), self.player:GetRotation())
end

function GamePreview:ClearPlayerView()
    if self.playerView then
        self.playerView:Destroy()
        self.playerView = nil
    end
end

function GamePreview:Stop()
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
    if self.feedbackNode then
        self.feedbackNode:Remove()
        self.feedbackNode = nil
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
end

return GamePreview
