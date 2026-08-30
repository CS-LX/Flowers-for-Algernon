-- 静物资产绑定实验：当前预览 Algernon sidecar。
-- 纯色 Unlit 代替 emission；尺寸按查理胶囊约 1/3 高。

local UI = require("urhox-libs/UI")
local LookApplier = require "LookApplier"
local FixedGameCamera = require "FixedGameCamera"
local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"

local StillImportLab = {}

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local cameraNode_ = nil
---@type Camera|nil
local camera_ = nil
---@type Viewport|nil
local viewport_ = nil
---@type Node|nil
local stillRoot_ = nil
---@type table|nil
local stillRuntime_ = nil
---@type StillObject?
local stillObject_ = nil
---@type Label|nil
local statusLabel_ = nil

local yawOrbit_ = 0.0
local LEVEL_ATMOSPHERE_PATH = "levels/default-level.json"

local CAMERA = {
    pitch = 30.0,
    orthoSize = 2.4,
    target = { x = 0.0, y = 0.16, z = 0.0 },
    nearClip = 0.1,
    farClip = 100.0,
}

local function LoadLevelAtmosphere()
    local atmosphere = LookApplier.DefaultAtmosphere()
    if not fileSystem:FileExists(LEVEL_ATMOSPHERE_PATH) then
        print("StillImportLab: missing " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local file = File(LEVEL_ATMOSPHERE_PATH, FILE_READ)
    if not file or not file:IsOpen() then
        print("StillImportLab: cannot open " .. LEVEL_ATMOSPHERE_PATH)
        return atmosphere
    end
    local json = file:ReadString()
    file:Close()
    local ok, data = pcall(cjson.decode, json)
    if not ok or type(data) ~= "table" then
        print("StillImportLab: atmosphere decode failed: " .. tostring(data))
        return atmosphere
    end
    return LookApplier.CopyAtmosphere(data.atmosphere)
end

local function CreateAlgernon()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    stillObject_ = StillObject.New({
        id = "lab_algernon",
        name = "阿尔吉侬",
        modelId = "algernon",
        transform = {
            position = { x = 0, y = 0, z = 0 },
            rotation = { x = 0, y = 0, z = 0 },
            scale = { x = 1, y = 1, z = 1 },
        },
    })
    stillRoot_ = scene_:CreateChild("Algernon")
    stillRuntime_ = StillObjectRuntime.Bind(stillRoot_, stillObject_)
    if not stillRuntime_ then
        error("StillImportLab: failed to bind algernon asset")
    end
    print("StillImportLab: Algernon Mouse.glb bound")
end

local function CreateCharlieReference()
    if not scene_ then
        return
    end
    local node = scene_:CreateChild("CharlieRef")
    node.position = Vector3(0.45, 0, 0)
    local body = node:CreateChild("Body")
    body.position = Vector3(0, 0.22, 0)
    local bodyModel = body:CreateComponent("StaticModel")
    bodyModel.model = CapsuleGeometry(0.16, 0.38, 12, 6):ToModel()
    local material = LookApplier.CreateStillObjectUnlitMaterial({
        color = "#F5DB5C",
        opaque = true,
    })
    bodyModel.material = material
    local head = node:CreateChild("Head")
    head.position = Vector3(0, 0.46, 0)
    head.scale = Vector3(0.72, 0.72, 0.72)
    local headModel = head:CreateComponent("StaticModel")
    headModel.model = SphereGeometry(0.16, 16, 8):ToModel()
    headModel.material = LookApplier.CreateStillObjectUnlitMaterial({
        color = "#FAB87A",
        opaque = true,
    })
end

local function CreateGroundMark()
    if not scene_ then
        error("StillImportLab: scene is missing")
    end
    local node = scene_:CreateChild("AxisMark")
    node.position = Vector3(0, 0.01, 0)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Plane.mdl"))
    node.scale = Vector3(3, 1, 3)
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Vector4(0.18, 0.22, 0.28, 1)))
    material:SetShaderParameter("Metallic", Variant(0.0))
    material:SetShaderParameter("Roughness", Variant(0.85))
    model:SetMaterial(material)
end

local function CreateUI()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    statusLabel_ = UI.Label {
        text = "Toy Mouse · 白身体 / 粉内耳尾巴 / 黑眼睛 / 红鼻子",
        fontSize = 13,
        fontColor = { 231, 238, 248, 255 },
        whiteSpace = "normal",
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        padding = 16,
        justifyContent = "flex-start",
        alignItems = "flex-start",
        backgroundColor = { 0, 0, 0, 0 },
        children = {
            UI.Panel {
                width = 380,
                padding = 12,
                gap = 8,
                backgroundColor = { 21, 27, 38, 220 },
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = "静物资产 / 阿尔吉侬",
                        fontSize = 18,
                        fontWeight = "bold",
                        fontColor = { 231, 238, 248, 255 },
                    },
                    UI.Label {
                        text = "Poly Pizza Toy Mouse。身体白、内耳/尾巴粉、眼睛黑、鼻子红。右侧胶囊是查理对照。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                        whiteSpace = "normal",
                    },
                    statusLabel_,
                    UI.Label {
                        text = "RMB 绕模型转。",
                        fontSize = 11,
                        fontColor = { 145, 160, 184, 255 },
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end

local function ApplyCamera()
    local config = {
        pitch = CAMERA.pitch,
        orthoSize = CAMERA.orthoSize,
        target = CAMERA.target,
        nearClip = CAMERA.nearClip,
        farClip = CAMERA.farClip,
    }
    if not cameraNode_ then
        return
    end
    local target, position = FixedGameCamera.GetWorldPosition(config)
    local orbit = Quaternion(yawOrbit_, Vector3.UP)
    local offset = position - target
    cameraNode_.position = target + orbit * offset
    cameraNode_:LookAt(target)
end

function StillImportLab.Start()
    graphics.windowTitle = "Still Import Lab — Algernon"
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    renderer.hdrRendering = false

    LookApplier.ApplyAtmosphere(scene_, LoadLevelAtmosphere())
    cameraNode_, camera_ = FixedGameCamera.Create(scene_, "LabCamera", CAMERA)
    viewport_ = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport_)

    CreateGroundMark()
    CreateAlgernon()
    CreateCharlieReference()
    CreateUI()
    ApplyCamera()

    SubscribeToEvent("Update", "HandleStillImportLabUpdate")
    print("StillImportLab: Algernon bound from StillModels/Algernon.json")
end

function StillImportLab.Stop()
    UI.Shutdown()
    stillRuntime_ = nil
    stillObject_ = nil
    stillRoot_ = nil
    scene_ = nil
    cameraNode_ = nil
    camera_ = nil
    viewport_ = nil
    statusLabel_ = nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleStillImportLabUpdate(eventType, eventData)
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        local mouseMove = input:GetMouseMove()
        yawOrbit_ = yawOrbit_ + mouseMove.x * 0.35
        ApplyCamera()
    end
end

return StillImportLab
