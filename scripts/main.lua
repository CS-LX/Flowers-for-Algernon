-- 六边形视觉闯关游戏：六边形体素基础场景
-- 当前版本：正交相机 + 30 度俯视 + 六个三棱柱体素组成中央六边形

local VoxelRenderer = require "VoxelRenderer"
local VoxelSandbox = require "VoxelSandbox"
local TriPrismGrid = require "TriPrismGrid"
local PartEditSession = require "PartEditSession"
local StarterLevel = require "StarterLevel"

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type DebugRenderer|nil
local debugRenderer_ = nil
---@type VoxelSandbox|nil
local sandbox_ = nil
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

local VOXEL_COLORS = {
    Color(0.95, 0.25, 0.30, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.88, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
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

    local editablePart = levelDocument_:GetPart("part_static_base")
    local session, sessionError = PartEditSession.Open(grid, editablePart)
    if not session then
        error("无法打开 Part 编辑会话：" .. tostring(sessionError))
    end

    sandbox_ = VoxelSandbox.New(
        scene_,
        cameraNode_,
        camera_,
        debugRenderer_,
        CONFIG.voxelEdge,
        CONFIG.voxelHeight,
        session
    )
    sandbox_:Start()

    SubscribeToEvent("Update", "HandleUpdate")
    print("Level: " .. levelDocument_.name .. " (" .. tostring(#levelDocument_:GetParts()) .. " Parts)")
    print("Part Editor: " .. editablePart.name)
end

function Stop()
    if sandbox_ then
        sandbox_:Stop()
        sandbox_ = nil
    end
    levelDocument_ = nil
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    debugRenderer_ = nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if sandbox_ then
        sandbox_:Refresh()
    end
end

function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    debugRenderer_ = scene_:CreateComponent("DebugRenderer")

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

    local camera = cameraNode_:CreateComponent("Camera")
    camera_ = camera
    camera.orthographic = true
    camera.orthoSize = CONFIG.cameraOrthoSize
    camera.nearClip = CONFIG.cameraNearClip
    camera.farClip = CONFIG.cameraFarClip

    local viewport = Viewport:new(scene_, camera)
    renderer:SetViewport(0, viewport)
    renderer.hdrRendering = true
end

function CreateHexagonVoxelAssembly()
    VoxelRenderer.CreateHexagonOfVoxels(
        scene_,
        Vector3(0, 0, 0),
        VOXEL_COLORS,
        {
            edgeLength = CONFIG.voxelEdge,
            height = CONFIG.voxelHeight,
        }
    )

    print("Voxel spec: edge=" .. CONFIG.voxelEdge .. ", height=" .. CONFIG.voxelHeight)
end
