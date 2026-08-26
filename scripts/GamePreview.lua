-- 固定游戏镜头下的只读关卡 Preview。
-- Preview 只持有关卡场景、PathRuntime 和角色逻辑；Overlay Viewport 由 LevelEditor 统一持有。

local PartRootRenderer = require "PartRootRenderer"
local FixedGameCamera = require "FixedGameCamera"
local PathRuntime = require "PathRuntime"
local PlayerController = require "PlayerController"
local PreviewRotatorController = require "PreviewRotatorController"

local GamePreview = {}
GamePreview.__index = GamePreview

local function CreatePreviewMaterial(color, metallic, roughness)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(metallic))
    material:SetShaderParameter("Roughness", Variant(roughness))
    return material
end

local function CreateUnlitMaterial(color)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    return material
end

function GamePreview.New(levelDocument, edgeLength, voxelHeight, overlayViewManager)
    local self = setmetatable({}, GamePreview)
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.overlayViewManager = overlayViewManager
    self.scene = nil
    self.cameraNode = nil
    self.camera = nil
    self.viewport = nil
    self.partRenderer = nil
    self.pathRuntime = nil
    self.player = nil
    self.spawnNodeKey = nil
    self.feedbackNode = nil
    self.feedbackElapsed = 0.0
    self.feedbackDuration = 0.55
    self.feedbackOriginScale = 0.12
    self.rotatorController = nil
    return self
end

function GamePreview:CreateScene()
    self.scene = Scene()
    self.scene:CreateComponent("Octree")

    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = self.scene:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    local floorNode = self.scene:CreateChild("PreviewFloor")
    floorNode.position = Vector3(0, -0.15, 0)
    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel.model = BoxGeometry(24.0, 0.3, 24.0):ToModel()
    floorModel.material = CreatePreviewMaterial(Color(0.055, 0.075, 0.11, 1.0), 0.15, 0.82)
    floorModel.castShadows = false
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
    if self.player:IsWalking() then
        return
    end
    local fromPendingClick = self.rotatorController and self.rotatorController:ConsumePendingClick()
    if not fromPendingClick and not input:GetMouseButtonPress(MOUSEB_LEFT) then
        return
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

    self.overlayViewManager:BindPreview(self.viewport)
    self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
    self.player = PlayerController.New(self.pathRuntime, self.spawnNodeKey, self.camera)
    local playerStarted, playerError = self.player:Start()
    if not playerStarted then
        self:Stop()
        return false, playerError
    end

    self.rotatorController = PreviewRotatorController.New(
        self.levelDocument,
        self.partRenderer,
        self.pathRuntime,
        self.camera,
        self.scene,
        self.player
    )
    print("Game Preview: started with player and rotator drag")
    return true
end

function GamePreview:Update(timeStep)
    local rotatorBusy = self.rotatorController and self.rotatorController:Update(timeStep)
    if not rotatorBusy then
        self:HandlePointer()
    end
    if self.player then
        self.player:Update(timeStep)
        self.overlayViewManager:PresentPlayer(self.player)
    end
    self:UpdateFeedback(timeStep)
end

function GamePreview:Stop()
    if self.rotatorController then
        self.rotatorController:RestoreAuthoredStates()
        self.rotatorController = nil
    end
    if self.player then
        self.player:Stop()
        self.player = nil
    end
    if self.overlayViewManager then
        self.overlayViewManager:ClearPlayer()
        self.overlayViewManager:BindEditor(self.overlayViewManager.mainViewport)
    end
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
