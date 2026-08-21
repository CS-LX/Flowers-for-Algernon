-- 固定游戏镜头下的只读关卡 Preview。
-- 从 LevelDocument 重建独立 Part 显示层级，不改写 Editor、PartDefinition 或局部体素数据。

local PartRootRenderer = require "PartRootRenderer"

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

function GamePreview.New(levelDocument, edgeLength, voxelHeight)
    local self = setmetatable({}, GamePreview)
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.scene = nil
    self.cameraNode = nil
    self.camera = nil
    self.viewport = nil
    self.partRenderer = nil
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

function GamePreview:CreateCamera()
    local settings = self.levelDocument.fixedCamera
    local target = Vector3(settings.target.x, settings.target.y, settings.target.z)
    local distance = settings.orthoSize * 1.5
    local yaw = math.rad(settings.yaw)
    local pitch = math.rad(settings.pitch)
    local horizontal = math.cos(pitch) * distance

    self.cameraNode = self.scene:CreateChild("FixedPreviewCamera")
    self.cameraNode.position = target + Vector3(
        math.sin(yaw) * horizontal,
        math.sin(pitch) * distance,
        -math.cos(yaw) * horizontal
    )
    self.cameraNode:LookAt(target)

    self.camera = self.cameraNode:CreateComponent("Camera")
    self.camera.orthographic = true
    self.camera.orthoSize = settings.orthoSize
    self.camera.nearClip = settings.nearClip
    self.camera.farClip = settings.farClip
    self.viewport = Viewport:new(self.scene, self.camera)
end

function GamePreview:Start()
    self:CreateScene()
    self:CreateCamera()
    self.partRenderer = PartRootRenderer.New(self.scene, self.edgeLength, self.voxelHeight)
    local built, errorMessage = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        self:Stop()
        return false, errorMessage
    end
    renderer:SetNumViewports(1)
    renderer:SetViewport(0, self.viewport)
    print("Game Preview: started with fixed orthographic camera")
    return true
end

function GamePreview:Stop()
    if self.partRenderer then
        self.partRenderer:Clear()
        self.partRenderer = nil
    end
    if self.scene then
        self.scene:Clear(true, true)
        self.scene = nil
    end
    self.cameraNode = nil
    self.camera = nil
    self.viewport = nil
end

return GamePreview
