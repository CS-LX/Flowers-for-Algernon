-- 六边形视觉闯关游戏入口。

local VoxelRenderer = require "VoxelRenderer"
local TriPrismGrid = require "TriPrismGrid"
local LevelEditor = require "LevelEditor"
local StarterLevel = require "StarterLevel"

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type table|nil
local levelEditor_ = nil
---@type table|nil
local levelDocument_ = nil

local CONFIG = {
    title = "Hexagon Visual Challenge",
    cameraOrthoSize = 10.0,
    cameraNearClip = 0.1,
    cameraFarClip = 100.0,
    voxelEdge = 1.0,
    voxelHeight = VoxelRenderer.DEFAULT_HEIGHT,
}

local function CreateMaterial(color, metallic, roughness)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(color))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    material:SetShaderParameter("Metallic", Variant(metallic))
    material:SetShaderParameter("Roughness", Variant(roughness))
    return material
end

function Start()
    graphics.windowTitle = CONFIG.title
    CreateScene()
    SetupCamera()

    local grid = TriPrismGrid.New(CONFIG.voxelEdge, CONFIG.voxelHeight)
    levelDocument_ = StarterLevel.LoadOrCreate(grid)
    if not levelDocument_ then
        error("无法创建或加载初始关卡")
    end

    levelEditor_ = LevelEditor.New(
        scene_,
        cameraNode_,
        camera_,
        viewport_,
        levelDocument_,
        CONFIG.voxelEdge,
        CONFIG.voxelHeight
    )
    levelEditor_:Start()

    SubscribeToEvent("Update", "HandleUpdate")
    print("Level: " .. levelDocument_.name .. " (" .. tostring(#levelDocument_:GetParts()) .. " Parts)")
    print("Level Editor: Object Tree ready")
    print("PathRuntime candidates are indexed for later visual evaluation")
end

function Stop()
    if levelEditor_ then
        levelEditor_:Stop()
        levelEditor_ = nil
    end
    levelDocument_ = nil
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    viewport_ = nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if levelEditor_ then
        levelEditor_:Refresh(eventData["TimeStep"]:GetFloat())
    end
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    local lightGroup = scene_:CreateChild("LightGroup")
    lightGroup:LoadXML(lightGroupFile:GetRoot())

    local floorNode = scene_:CreateChild("Floor")
    floorNode.position = Vector3(0, -0.15, 0)

    local floorModel = floorNode:CreateComponent("StaticModel")
    floorModel.model = BoxGeometry(24.0, 0.3, 24.0):ToModel()
    floorModel.material = CreateMaterial(
        Color(0.055, 0.075, 0.11, 1.0),
        0.15,
        0.82
    )
    floorModel.castShadows = false
end

function SetupCamera()
    cameraNode_ = scene_:CreateChild("Camera")
    cameraNode_.position = Vector3(0, 8.660254, -15.0)
    cameraNode_:LookAt(Vector3(0, 0, 0))

    camera_ = cameraNode_:CreateComponent("Camera")
    camera_.orthographic = true
    camera_.orthoSize = CONFIG.cameraOrthoSize
    camera_.nearClip = CONFIG.cameraNearClip
    camera_.farClip = CONFIG.cameraFarClip

    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)
    renderer.hdrRendering = true
end
